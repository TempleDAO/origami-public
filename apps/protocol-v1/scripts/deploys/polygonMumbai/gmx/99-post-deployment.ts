import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { ZERO_ADDRESS } from '../../helpers';
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory,
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory,
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory,
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory,
    TokenPrices, TokenPrices__factory, 
    GMX_GMX, GMX_NamedToken, 
    GMX_GMX__factory, GMX_NamedToken__factory,
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts as gmxDeployedContracts } from './contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';

interface ContractInstances {
    gmxEarnAccount: OrigamiGmxEarnAccount,
    glpPrimaryEarnAccount: OrigamiGmxEarnAccount,
    glpSecondaryEarnAccount: OrigamiGmxEarnAccount,
    gmxManager: OrigamiGmxManager,
    glpManager: OrigamiGmxManager,
    gmxRewardsAggregator: OrigamiGmxRewardsAggregator,
    glpRewardsAggregator: OrigamiGmxRewardsAggregator,
    oGMX: OrigamiGmxInvestment,
    oGLP: OrigamiGlpInvestment,
    ovGMX: OrigamiInvestmentVault,
    ovGLP: OrigamiInvestmentVault,
    tokenPrices: TokenPrices,
    gmxToken: GMX_GMX,
    wethToken: GMX_NamedToken,
}

function connectToContracts(DEPLOYED: GmxDeployedContracts, owner: SignerWithAddress): ContractInstances {
    return {
        gmxEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner),
        glpPrimaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner),
        glpSecondaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner),
        gmxManager: OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner),
        glpManager: OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner),
        gmxRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner),
        glpRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner),
        oGMX: OrigamiGmxInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGMX, owner),
        oGLP: OrigamiGlpInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGLP, owner),
        ovGMX: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGMX, owner),
        ovGLP: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGLP, owner),
        tokenPrices: TokenPrices__factory.connect(DEPLOYED.ORIGAMI.TOKEN_PRICES, owner),
        gmxToken: GMX_GMX__factory.connect(DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner),
        wethToken: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN, owner),
    }
}

type TokenPricesArg = string | boolean | BigNumberish;

const encodeFunction = (fn: string, ...args: TokenPricesArg[]): string => {
    const tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
    return tokenPricesInterface.encodeFunctionData(fn, args);
}

const encodedOraclePrice = (oracle: string, stalenessThreshold: number): string => encodeFunction("oraclePrice", oracle, stalenessThreshold);
const encodedGmxVaultPrice = (vault: string, token: string): string => encodeFunction("gmxVaultPrice", vault, token);
const encodedGlpPrice = (glpManager: string): string => encodeFunction("glpPrice", glpManager);
const encodedUniV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("univ3Price", pool, inQuotedOrder);
const encodedDivPrice = (numerator: string, denominator: string): string => encodeFunction("div", numerator, denominator);
const encodedAliasFor = (sourceToken: string): string => encodeFunction("aliasFor", sourceToken);
const encodedRepricingTokenPrice = (repricingToken: string): string => encodeFunction("repricingTokenPrice", repricingToken);

async function setupPrices(contracts: ContractInstances, DEPLOYED: GmxDeployedContracts) {
    // These are 'static' prices which never really change. So set the threshold to be super large.
    const stalenessThreshold = 86400 * 365 * 10;

    // $ETH
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        ZERO_ADDRESS, 
        encodedOraclePrice(DEPLOYED.PRICES.NATIVE_USD_ORACLE, stalenessThreshold),
    ));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN,
        encodedAliasFor(ZERO_ADDRESS)
    ));

    // The other GLP input tokens
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.DAI_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.DAI_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.BNB_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.BNB_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.BTC_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.BTC_USD_ORACLE, stalenessThreshold)));

    // $GMX
    const encodedEthGmx = encodedUniV3Price(DEPLOYED.PRICES.NATIVE_GMX_POOL, true);
    const encodedEthUsdGmx = encodedGmxVaultPrice(DEPLOYED.GMX.CORE.VAULT, DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN);
    const encodedGmxUsd = encodedDivPrice(encodedEthUsdGmx, encodedEthGmx);
    await mine(contracts.tokenPrices.setTokenPriceFunction(DEPLOYED.GMX.TOKENS.GMX_TOKEN, encodedGmxUsd));

    // $GLP
    const encodedGlpUsd = encodedGlpPrice(DEPLOYED.GMX.CORE.GLP_MANAGER);
    await mine(contracts.tokenPrices.setTokenPriceFunction(DEPLOYED.GMX.TOKENS.GLP_TOKEN, encodedGlpUsd));

    // $sGLP -- staked GLP
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.STAKING.STAKED_GLP,
        encodedAliasFor(DEPLOYED.GMX.TOKENS.GLP_TOKEN)
    ));

    // $oGMX
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.ORIGAMI.GMX.oGMX,
        encodedAliasFor(DEPLOYED.GMX.TOKENS.GMX_TOKEN)
    ));

    // $ovGMX
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.ORIGAMI.GMX.ovGMX,
        encodedRepricingTokenPrice(DEPLOYED.ORIGAMI.GMX.ovGMX)
    ));

    // $oGLP
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.ORIGAMI.GMX.oGLP,
        encodedAliasFor(DEPLOYED.GMX.TOKENS.GLP_TOKEN)
    ));

    // $ovGLP
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.ORIGAMI.GMX.ovGLP,
        encodedRepricingTokenPrice(DEPLOYED.ORIGAMI.GMX.ovGLP)
    ));
}

async function main() {
    ensureExpectedEnvvars();
  
    const [owner] = await ethers.getSigners();
    const GMX_DEPLOYED = gmxDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();
    const contracts = connectToContracts(GMX_DEPLOYED, owner);

    // The Investments are added as manager operators such that they can sell oGLP/oGMX
    await mine(contracts.gmxManager.addOperator(contracts.oGMX.address));
    await mine(contracts.glpManager.addOperator(contracts.oGLP.address));

    // The reward aggregators are added as manager operators so they can call harvestRewards()
    await mine(contracts.gmxManager.addOperator(contracts.gmxRewardsAggregator.address));
    await mine(contracts.glpManager.addOperator(contracts.gmxRewardsAggregator.address));
    await mine(contracts.glpManager.addOperator(contracts.glpRewardsAggregator.address));

    // Add the timelock and multisig as valid pausers
    await mine(contracts.gmxManager.setPauser(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(contracts.gmxManager.setPauser(GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK, true));
    await mine(contracts.glpManager.setPauser(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(contracts.glpManager.setPauser(GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK, true));
    await mine(contracts.gmxManager.setPauser(owner.getAddress(), true));
    await mine(contracts.glpManager.setPauser(owner.getAddress(), true));

    // The Investments & managers are added as operators such that they can buy/sell/stake/unstake GLP/GMX
    await mine(contracts.gmxEarnAccount.addOperator(contracts.gmxManager.address));

    // The investment only needs access to the secondary GLP earn account. The manager needs operator on both.
    await mine(contracts.glpPrimaryEarnAccount.addOperator(contracts.glpManager.address));
    await mine(contracts.glpSecondaryEarnAccount.addOperator(contracts.glpManager.address));

    // Allow the multisig to perform operations on the earn accounts.
    await mine(contracts.gmxEarnAccount.addOperator(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.glpPrimaryEarnAccount.addOperator(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.glpSecondaryEarnAccount.addOperator(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    
    // The Investments & managers mints/burns oGMXtokens.
    // The GLP manager also needs mint access on oGMX, for rewards.
    await mine(contracts.oGMX.addMinter(contracts.gmxManager.address));
    await mine(contracts.oGMX.addMinter(contracts.glpManager.address));

    // Set the investment manager as the rewards aggregator in the ovGMX/ovGLP, for APR calcs
    await mine(contracts.ovGMX.setInvestmentManager(contracts.gmxRewardsAggregator.address));
    await mine(contracts.ovGLP.setInvestmentManager(contracts.glpRewardsAggregator.address));
    
    // The rewards aggregator compounds and adds reserves to the vaults
    await mine(contracts.ovGMX.addOperator(contracts.gmxRewardsAggregator.address));
    await mine(contracts.ovGLP.addOperator(contracts.glpRewardsAggregator.address));

    // Set the multisig as an operator on ovGMX/ovGLP, such that we can manually add reserves
    // to boost rewards if required.
    await mine(contracts.ovGMX.addOperator(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.ovGLP.addOperator(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.ovGMX.addOperator(owner.getAddress()));
    await mine(contracts.ovGLP.addOperator(owner.getAddress()));

    // Allow the Overlord Automation Bot to harvest rewards and transfer staked GLP
    await mine(contracts.gmxRewardsAggregator.addOperator(GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA));
    await mine(contracts.glpRewardsAggregator.addOperator(GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA));
    await mine(contracts.glpSecondaryEarnAccount.addOperator(GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA));
    await mine(contracts.gmxRewardsAggregator.addOperator(owner.getAddress()));
    await mine(contracts.glpRewardsAggregator.addOperator(owner.getAddress()));

    // Allow the Overlord Automation Bot to harvest secondary rewards.
    await mine(contracts.gmxManager.addOperator(GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA));
    await mine(contracts.glpManager.addOperator(GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA));
    
    // Set the investment managers in both the GMX & GLP Manager
    await mine(contracts.gmxManager.setRewardsAggregators(
        contracts.gmxRewardsAggregator.address,
        contracts.glpRewardsAggregator.address,
    ));
    await mine(contracts.glpManager.setRewardsAggregators(
        contracts.gmxRewardsAggregator.address,
        contracts.glpRewardsAggregator.address,
    ));

    // Link the manager contracts into the investments.
    {
        await contracts.oGLP.setOrigamiGlpManager(contracts.glpManager.address);
        await contracts.oGMX.setOrigamiGmxManager(contracts.gmxManager.address);
    }

    // Set default policy
    {
        // GMX Manager
        await mine(contracts.gmxManager.setSellFeeRate(5, 1000)); // 0.5% fee on oGMX when selling
        await mine(contracts.gmxManager.setOGmxRewardsFeeRate(30, 100)); // 30% fee on oGMX rewards
        await mine(contracts.gmxManager.setEsGmxVestingRate(10, 100)); // Vest 10% of the esGMX rewards into GMX

        // GLP Manager
        // No fees on oGLP when selling
        await mine(contracts.glpManager.setOGmxRewardsFeeRate(30, 100)); // 30% fee on oGMX rewards
        // setEsGmxVestingRate left at 0%
    }

    await setupPrices(contracts, GMX_DEPLOYED);

    // testnet only - add minting rights to the msig.
    await mine(contracts.oGMX.addMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.oGLP.addMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.oGMX.addMinter(owner.getAddress()));
    await mine(contracts.oGLP.addMinter(owner.getAddress()));

    // testnet only - load the dummy dex up with a tonne of GMX and weth for swaps
    await mine(contracts.gmxToken.mint(GMX_DEPLOYED.ZERO_EX_PROXY, ethers.utils.parseEther("10000000")));
    await mine(contracts.wethToken.mint(GMX_DEPLOYED.ZERO_EX_PROXY,  ethers.utils.parseEther("10000000")));
  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });