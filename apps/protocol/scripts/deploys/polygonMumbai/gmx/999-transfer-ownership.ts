import '@nomiclabs/hardhat-ethers';
import { Signer } from 'ethers';
import { ethers, network } from 'hardhat';
import { 
    GMX_BonusDistributor__factory,
    GMX_EsGMX__factory,
    GMX_GlpManager__factory,
    GMX_GLP__factory, 
    GMX_GMX__factory, 
    GMX_MintableBaseToken__factory, 
    GMX_PriceFeed__factory, 
    GMX_RewardDistributor__factory, 
    GMX_RewardRouterV2__factory, 
    GMX_RewardTracker__factory, 
    GMX_Router__factory, 
    GMX_USDG__factory, 
    GMX_VaultErrorController__factory, 
    GMX_VaultPriceFeed__factory, 
    GMX_VaultUtils__factory, 
    GMX_Vault__factory, 
    GMX_Vester__factory,
    OrigamiGmxEarnAccount__factory,
    OrigamiInvestment__factory,
    OrigamiGmxManager__factory,
    OrigamiGmxRewardsAggregator__factory,
    OrigamiInvestmentVault__factory,
    TokenPrices__factory,
 } from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts as gmxDeployedContracts } from './contract-addresses';
import { GovernanceDeployedContracts, getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';

async function updateGmxCore(GMX_DEPLOYED: GmxDeployedContracts, GOV_DEPLOYED: GovernanceDeployedContracts, owner: Signer) {
    // GMX.LIQUIDITY_POOL
    const bnbPriceFeed = GMX_PriceFeed__factory.connect(GMX_DEPLOYED.GMX.LIQUIDITY_POOL.BNB_PRICE_FEED, owner);
    await mine(bnbPriceFeed.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    const wethPriceFeed = GMX_PriceFeed__factory.connect(GMX_DEPLOYED.GMX.LIQUIDITY_POOL.WETH_PRICE_FEED, owner);
    await mine(wethPriceFeed.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    const btcPriceFeed = GMX_PriceFeed__factory.connect(GMX_DEPLOYED.GMX.LIQUIDITY_POOL.BTC_PRICE_FEED, owner);
    await mine(btcPriceFeed.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    const daiPriceFeed = GMX_PriceFeed__factory.connect(GMX_DEPLOYED.GMX.LIQUIDITY_POOL.DAI_PRICE_FEED, owner);
    await mine(daiPriceFeed.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));

    // GMX.TOKENS
    const glp = GMX_GLP__factory.connect(GMX_DEPLOYED.GMX.TOKENS.GLP_TOKEN, owner);
    await mine(glp.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(glp.addAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glp.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const gmx = GMX_GMX__factory.connect(GMX_DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner);
    await mine(gmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(gmx.addAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmx.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const esGmx = GMX_EsGMX__factory.connect(GMX_DEPLOYED.GMX.TOKENS.ESGMX_TOKEN, owner);
    await mine(esGmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(esGmx.addAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(esGmx.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const bnGmx = GMX_MintableBaseToken__factory.connect(GMX_DEPLOYED.GMX.TOKENS.BNGMX_TOKEN, owner);
    await mine(bnGmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(bnGmx.addAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(bnGmx.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    // GMX.CORE
    const vault = GMX_Vault__factory.connect(GMX_DEPLOYED.GMX.CORE.VAULT, owner);
    await mine(vault.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const vaultPriceFeed = GMX_VaultPriceFeed__factory.connect(GMX_DEPLOYED.GMX.CORE.VAULT_PRICE_FEED, owner);
    await mine(vaultPriceFeed.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const vaultUtils = GMX_VaultUtils__factory.connect(GMX_DEPLOYED.GMX.CORE.VAULT_UTILS, owner);
    await mine(vaultUtils.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const vaultErrorController = GMX_VaultErrorController__factory.connect(GMX_DEPLOYED.GMX.CORE.VAULT_ERROR_CONTROLLER, owner);
    await mine(vaultErrorController.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const usdg = GMX_USDG__factory.connect(GMX_DEPLOYED.GMX.CORE.USDG_TOKEN, owner);
    await mine(usdg.addAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(usdg.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const router = GMX_Router__factory.connect(GMX_DEPLOYED.GMX.CORE.ROUTER, owner);
    await mine(router.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const glpManager = GMX_GlpManager__factory.connect(GMX_DEPLOYED.GMX.CORE.GLP_MANAGER, owner);
    await mine(glpManager.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    // GMX.STAKING
    const stakedGmxTracker = GMX_RewardTracker__factory.connect(GMX_DEPLOYED.GMX.STAKING.STAKED_GMX_TRACKER, owner);
    await mine(stakedGmxTracker.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const bonusGmxTracker = GMX_RewardTracker__factory.connect(GMX_DEPLOYED.GMX.STAKING.BONUS_GMX_TRACKER, owner);
    await mine(bonusGmxTracker.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const feeGmxTracker = GMX_RewardTracker__factory.connect(GMX_DEPLOYED.GMX.STAKING.FEE_GMX_TRACKER, owner);
    await mine(feeGmxTracker.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const feeGlpTracker = GMX_RewardTracker__factory.connect(GMX_DEPLOYED.GMX.STAKING.FEE_GLP_TRACKER, owner);
    await mine(feeGlpTracker.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const stakedGlpTracker = GMX_RewardTracker__factory.connect(GMX_DEPLOYED.GMX.STAKING.STAKED_GLP_TRACKER, owner);
    await mine(stakedGlpTracker.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const stakedGmxDistributor = GMX_RewardDistributor__factory.connect(GMX_DEPLOYED.GMX.STAKING.STAKED_GMX_DISTRIBUTOR, owner);
    await mine(stakedGmxDistributor.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(stakedGmxDistributor.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const feeGmxDistributor = GMX_RewardDistributor__factory.connect(GMX_DEPLOYED.GMX.STAKING.FEE_GMX_DISTRIBUTOR, owner);
    await mine(feeGmxDistributor.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(feeGmxDistributor.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const feeGlpDistributor = GMX_RewardDistributor__factory.connect(GMX_DEPLOYED.GMX.STAKING.FEE_GLP_DISTRIBUTOR, owner);
    await mine(feeGlpDistributor.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(feeGlpDistributor.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const stakedGlpDistributor = GMX_RewardDistributor__factory.connect(GMX_DEPLOYED.GMX.STAKING.STAKED_GLP_DISTRIBUTOR, owner);
    await mine(stakedGlpDistributor.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(stakedGlpDistributor.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const bonusGmxDistributor = GMX_BonusDistributor__factory.connect(GMX_DEPLOYED.GMX.STAKING.BONUS_GMX_DISTRIBUTOR, owner);
    await mine(bonusGmxDistributor.setAdmin(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(bonusGmxDistributor.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    const gmxVester = GMX_Vester__factory.connect(GMX_DEPLOYED.GMX.STAKING.GMX_ESGMX_VESTER, owner);
    await mine(gmxVester.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const glpVester = GMX_Vester__factory.connect(GMX_DEPLOYED.GMX.STAKING.GLP_ESGMX_VESTER, owner);
    await mine(glpVester.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const gmxRewardRouter = GMX_RewardRouterV2__factory.connect(GMX_DEPLOYED.GMX.STAKING.GMX_REWARD_ROUTER, owner);
    await mine(gmxRewardRouter.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    const glpRewardRouter = GMX_RewardRouterV2__factory.connect(GMX_DEPLOYED.GMX.STAKING.GLP_REWARD_ROUTER, owner);
    await mine(glpRewardRouter.setGov(GOV_DEPLOYED.ORIGAMI.MULTISIG));
}

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const GMX_DEPLOYED = gmxDeployedContracts(network.name);
    const GOV_DEPLOYED = govDeployedContracts();
       
    await updateGmxCore(GMX_DEPLOYED, GOV_DEPLOYED, owner);

    const gmxEarnAccount = OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner);
    const glpPrimaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner);
    const glpSecondaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner);
    const gmxManager = OrigamiGmxManager__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner);
    const glpManager = OrigamiGmxManager__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner);
    const gmxRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner);
    const glpRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner);
    const oGMX = OrigamiInvestment__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.oGMX, owner);
    const oGLP = OrigamiInvestment__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.oGLP, owner);
    const ovGMX = OrigamiInvestmentVault__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.ovGMX, owner);
    const ovGLP = OrigamiInvestmentVault__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.ovGLP, owner);
    const tokenPrices = TokenPrices__factory.connect(GMX_DEPLOYED.ORIGAMI.TOKEN_PRICES, owner);

    // Propose governance change to the timelock
    await mine(oGMX.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGLP.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGMX.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGLP.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxEarnAccount.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpPrimaryEarnAccount.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpSecondaryEarnAccount.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxManager.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpManager.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxRewardsAggr.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpRewardsAggr.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    // Transfer ownership to the multisig
    await mine(tokenPrices.transferOwnership(GOV_DEPLOYED.ORIGAMI.MULTISIG));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
