import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { ZERO_ADDRESS } from '../../../../test/helpers';
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory,
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory,
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory,
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory,
    TokenPrices, TokenPrices__factory,
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts } from './contract-addresses';

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
    }
}

type TokenPricesArg = string | boolean | BigNumberish;

const encodeFunction = (fn: string, ...args: TokenPricesArg[]): string => {
    const tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
    return tokenPricesInterface.encodeFunctionData(fn, args);
}

const encodedOraclePrice = (oracle: string): string => encodeFunction("oraclePrice", oracle);
const encodedGmxVaultPrice = (vault: string, token: string): string => encodeFunction("gmxVaultPrice", vault, token);
const encodedGlpPrice = (glpManager: string): string => encodeFunction("glpPrice", glpManager);
const encodedUniV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("univ3Price", pool, inQuotedOrder);
const encodedDivPrice = (numerator: string, denominator: string): string => encodeFunction("div", numerator, denominator);
const encodedAliasFor = (sourceToken: string): string => encodeFunction("aliasFor", sourceToken);
const encodedRepricingTokenPrice = (repricingToken: string): string => encodeFunction("repricingTokenPrice", repricingToken);

async function setupPrices(contracts: ContractInstances, DEPLOYED: GmxDeployedContracts) {
    // $ETH
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        ZERO_ADDRESS, 
        encodedOraclePrice(DEPLOYED.PRICES.NATIVE_USD_ORACLE),
    ));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN,
        encodedAliasFor(ZERO_ADDRESS)
    ));

    // The other GLP input tokens
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.DAI_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.DAI_USD_ORACLE)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.BNB_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.BNB_USD_ORACLE)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.BTC_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.BTC_USD_ORACLE)));

    // $GMX
    const encodedEthGmx = encodedUniV3Price(DEPLOYED.PRICES.NATIVE_GMX_POOL, true);
    const encodedEthUsdGmx = encodedGmxVaultPrice(DEPLOYED.GMX.CORE.VAULT, DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN);
    const encodedGmxUsd = encodedDivPrice(encodedEthUsdGmx, encodedEthGmx);
    await mine(contracts.tokenPrices.setTokenPriceFunction(DEPLOYED.GMX.TOKENS.GMX_TOKEN, encodedGmxUsd));

    // $GLP
    const encodedGlpUsd = encodedGlpPrice(DEPLOYED.GMX.CORE.GLP_MANAGER);
    await mine(contracts.tokenPrices.setTokenPriceFunction(DEPLOYED.GMX.TOKENS.GLP_TOKEN, encodedGlpUsd));

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
    const DEPLOYED = getDeployedContracts();
    const contracts = connectToContracts(DEPLOYED, owner);

    // The Investments are added as manager operators such that they can sell oGLP/oGMX
    await mine(contracts.gmxManager.addOperator(contracts.oGMX.address));
    await mine(contracts.glpManager.addOperator(contracts.oGLP.address));

    // The Investments & managers are added as operators such that they can buy/sell/stake/unstake GLP/GMX
    await mine(contracts.gmxEarnAccount.addOperator(contracts.oGMX.address));
    await mine(contracts.gmxEarnAccount.addOperator(contracts.gmxManager.address));

    // The investment only needs access to the secondary GLP earn account. The manager needs operator on both.
    await mine(contracts.glpSecondaryEarnAccount.addOperator(contracts.oGLP.address));
    await mine(contracts.glpPrimaryEarnAccount.addOperator(contracts.glpManager.address));
    await mine(contracts.glpSecondaryEarnAccount.addOperator(contracts.glpManager.address));

    // Allow the multisig to perform operations on the earn accounts.
    await mine(contracts.gmxEarnAccount.addOperator(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.glpPrimaryEarnAccount.addOperator(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.glpSecondaryEarnAccount.addOperator(DEPLOYED.ORIGAMI.MULTISIG));
    
    // The Investments & managers mints/burns oGMXtokens.
    // The GLP manager also needs mint access on oGMX, for rewards.
    await mine(contracts.oGMX.addMinter(contracts.gmxManager.address));
    await mine(contracts.oGMX.addMinter(contracts.glpManager.address));
    await mine(contracts.oGLP.addMinter(contracts.glpManager.address));

    // Set the investment manager as the rewards aggregator in the ovGMX/ovGLP, for APR calcs
    await mine(contracts.ovGMX.setInvestmentManager(contracts.gmxRewardsAggregator.address));
    await mine(contracts.ovGLP.setInvestmentManager(contracts.glpRewardsAggregator.address));
    
    // Set the multisig as an operator on ovGMX/ovGLP.
    // The OZ defender relayer will also be added when we automate adding new reserves
    await mine(contracts.ovGMX.addOperator(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.ovGMX.addOperator(owner.getAddress()));
    await mine(contracts.ovGLP.addOperator(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.ovGLP.addOperator(owner.getAddress()));

    // Give the reward distributors as the multisig for day 1. Will be updated to OZ defender relayer
    await mine(contracts.gmxRewardsAggregator.setRewardsDistributor(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.gmxRewardsAggregator.setRewardsDistributor(owner.getAddress()));
    await mine(contracts.glpRewardsAggregator.setRewardsDistributor(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.glpRewardsAggregator.setRewardsDistributor(owner.getAddress()));

    // Set the investment managers in both the GMX & GLP Manager
    await mine(contracts.gmxManager.setRewardsAggregators(
        contracts.gmxRewardsAggregator.address,
        ZERO_ADDRESS, // GLP aggregator doesn't need to pull from GMX Manager.
    ));
    await mine(contracts.glpManager.setRewardsAggregators(
        contracts.gmxRewardsAggregator.address,
        contracts.glpRewardsAggregator.address,
    ));

    // Initial setup -- link the manager contracts into the investments.
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

    await setupPrices(contracts, DEPLOYED);

    // testnet only - add minting rights to the msig.
    await mine(contracts.oGMX.addMinter(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.oGLP.addMinter(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(contracts.oGMX.addMinter(owner.getAddress()));
    await mine(contracts.oGLP.addMinter(owner.getAddress()));
  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });