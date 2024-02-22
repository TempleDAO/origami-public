import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { ZERO_ADDRESS, setExplicitAccess } from '../../helpers';
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

const encodedOraclePrice = (oracle: string, stalenessThreshold: number): string => encodeFunction("oraclePrice", oracle, stalenessThreshold);
const encodedGmxVaultPrice = (vault: string, token: string): string => encodeFunction("gmxVaultPrice", vault, token);
const encodedGlpPrice = (glpManager: string): string => encodeFunction("glpPrice", glpManager);
const encodedUniV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("univ3Price", pool, inQuotedOrder);
const encodedDivPrice = (numerator: string, denominator: string): string => encodeFunction("div", numerator, denominator);
const encodedAliasFor = (sourceToken: string): string => encodeFunction("aliasFor", sourceToken);
const encodedRepricingTokenPrice = (repricingToken: string): string => encodeFunction("repricingTokenPrice", repricingToken);

async function setupPrices(contracts: ContractInstances, DEPLOYED: GmxDeployedContracts) {
    // Chainlink data fees may only update once per day if non-volatile prices, eg:
    // https://data.chain.link/arbitrum/mainnet/stablecoins/usdc-usd
    const stalenessThreshold = 86400 + 300;
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        ZERO_ADDRESS, 
        encodedOraclePrice(DEPLOYED.PRICES.ETH_USD_ORACLE, stalenessThreshold),
    ));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN,
        encodedAliasFor(ZERO_ADDRESS)
    ));

    // The other GLP input tokens
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.WBTC_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.BTC_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.LINK_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.LINK_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.UNI_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.UNI_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.USDC_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.USDC_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.USDC_E_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.USDC_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.USDT_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.USDT_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.DAI_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.DAI_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.FRAX_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.FRAX_USD_ORACLE, stalenessThreshold)));

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
    await setExplicitAccess(
        contracts.gmxManager,
        contracts.oGMX.address,
        ["investOGmx", "exitOGmx"],
        true
    );
    await setExplicitAccess(
        contracts.glpManager,
        contracts.oGLP.address,
        ["investOGlp", "exitOGlp"],
        true
    );

    // The reward aggregators are added as manager operators so they can call harvestRewards()
    await setExplicitAccess(
        contracts.gmxManager,
        contracts.gmxRewardsAggregator.address,
        ["harvestRewards"],
        true
    );
    await setExplicitAccess(
        contracts.glpManager,
        contracts.gmxRewardsAggregator.address,
        ["harvestRewards"],
        true
    );
    await setExplicitAccess(
        contracts.glpManager,
        contracts.glpRewardsAggregator.address,
        ["harvestRewards"],
        true
    );

    // Add the timelock and multisig as valid pausers
    await mine(contracts.gmxManager.setPauser(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(contracts.glpManager.setPauser(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));

    // The Investments & managers are added as operators such that they can buy/sell/stake/unstake GLP/GMX
    await setExplicitAccess(
        contracts.gmxEarnAccount,
        contracts.gmxManager.address,
        ["harvestRewards", "handleRewards", "unstakeGmx", "stakeGmx"],
        true
    );
    await setExplicitAccess(
        contracts.glpPrimaryEarnAccount,
        contracts.glpManager.address,
        ["harvestRewards", "handleRewards", "stakeGmx", "transferStakedGlp", "unstakeAndRedeemGlp"],
        true
    );
    await setExplicitAccess(
        contracts.glpSecondaryEarnAccount,
        contracts.glpManager.address,
        ["handleRewards", "mintAndStakeGlp"],
        true
    );
   
    // The Investments & managers mints/burns oGMXtokens.
    // The GLP manager also needs mint access on oGMX, for rewards.
    await mine(contracts.oGMX.addMinter(contracts.gmxManager.address));
    await mine(contracts.oGMX.addMinter(contracts.glpManager.address));

    // The rewards aggregator compounds and adds reserves to the vaults
    await setExplicitAccess(
        contracts.ovGMX,
        contracts.gmxRewardsAggregator.address,
        ["addPendingReserves"],
        true
    );
    await setExplicitAccess(
        contracts.ovGLP,
        contracts.glpRewardsAggregator.address,
        ["addPendingReserves"],
        true
    );

    // Allow the Overlord Automation Bot to harvest rewards and transfer staked GLP
    await setExplicitAccess(
        contracts.gmxRewardsAggregator,
        GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA,
        ["harvestRewards"],
        true
    );
    await setExplicitAccess(
        contracts.glpRewardsAggregator,
        GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA,
        ["harvestRewards"],
        true
    );
    await setExplicitAccess(
        contracts.glpSecondaryEarnAccount,
        GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA,
        ["transferStakedGlpOrPause", "transferStakedGlp"],
        true
    );

    // Allow the Overlord Automation Bot to harvest secondary rewards.
    await setExplicitAccess(
        contracts.gmxManager,
        GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA,
        ["harvestSecondaryRewards"],
        true
    );
    await setExplicitAccess(
        contracts.glpManager,
        GMX_DEPLOYED.ORIGAMI.OVERLORD_EOA,
        ["harvestSecondaryRewards"],
        true
    );
    
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
        // await mine(contracts.gmxManager.setSellFeeRate(0, 1000)); // No fees on oGMX when selling
        await mine(contracts.gmxManager.setOGmxRewardsFeeRate(3_000)); // 30% fee on oGMX rewards
        await mine(contracts.gmxManager.setEsGmxVestingRate(10_000)); // Vest 100% of the esGMX rewards into GMX

        // GLP Manager
        // No fees on oGLP when selling
        await mine(contracts.glpManager.setOGmxRewardsFeeRate(3_000)); // 30% fee on oGMX rewards
        // setEsGmxVestingRate left at 0%
    }

    await setupPrices(contracts, GMX_DEPLOYED);
  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });