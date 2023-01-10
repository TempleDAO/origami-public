import '@nomiclabs/hardhat-ethers';
import { Signer } from 'ethers';
import { ethers } from 'hardhat';
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
import { getDeployedContracts, GmxDeployedContracts } from './contract-addresses';

async function updateGmxCore(DEPLOYED: GmxDeployedContracts, owner: Signer) {
    // GMX.LIQUIDITY_POOL
    const bnbPriceFeed = GMX_PriceFeed__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.BNB_PRICE_FEED, owner);
    await mine(bnbPriceFeed.setAdmin(DEPLOYED.ORIGAMI.MULTISIG, true));
    const wethPriceFeed = GMX_PriceFeed__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.WETH_PRICE_FEED, owner);
    await mine(wethPriceFeed.setAdmin(DEPLOYED.ORIGAMI.MULTISIG, true));
    const btcPriceFeed = GMX_PriceFeed__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.BTC_PRICE_FEED, owner);
    await mine(btcPriceFeed.setAdmin(DEPLOYED.ORIGAMI.MULTISIG, true));
    const daiPriceFeed = GMX_PriceFeed__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.DAI_PRICE_FEED, owner);
    await mine(daiPriceFeed.setAdmin(DEPLOYED.ORIGAMI.MULTISIG, true));

    // GMX.TOKENS
    const glp = GMX_GLP__factory.connect(DEPLOYED.GMX.TOKENS.GLP_TOKEN, owner);
    await mine(glp.setMinter(DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(glp.addAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glp.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const gmx = GMX_GMX__factory.connect(DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner);
    await mine(gmx.setMinter(DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(gmx.addAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmx.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const esGmx = GMX_EsGMX__factory.connect(DEPLOYED.GMX.TOKENS.ESGMX_TOKEN, owner);
    await mine(esGmx.setMinter(DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(esGmx.addAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(esGmx.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const bnGmx = GMX_MintableBaseToken__factory.connect(DEPLOYED.GMX.TOKENS.BNGMX_TOKEN, owner);
    await mine(bnGmx.setMinter(DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(bnGmx.addAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(bnGmx.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    // GMX.CORE
    const vault = GMX_Vault__factory.connect(DEPLOYED.GMX.CORE.VAULT, owner);
    await mine(vault.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const vaultPriceFeed = GMX_VaultPriceFeed__factory.connect(DEPLOYED.GMX.CORE.VAULT_PRICE_FEED, owner);
    await mine(vaultPriceFeed.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const vaultUtils = GMX_VaultUtils__factory.connect(DEPLOYED.GMX.CORE.VAULT_UTILS, owner);
    await mine(vaultUtils.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const vaultErrorController = GMX_VaultErrorController__factory.connect(DEPLOYED.GMX.CORE.VAULT_ERROR_CONTROLLER, owner);
    await mine(vaultErrorController.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const usdg = GMX_USDG__factory.connect(DEPLOYED.GMX.CORE.USDG_TOKEN, owner);
    await mine(usdg.addAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(usdg.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const router = GMX_Router__factory.connect(DEPLOYED.GMX.CORE.ROUTER, owner);
    await mine(router.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const glpManager = GMX_GlpManager__factory.connect(DEPLOYED.GMX.CORE.GLP_MANAGER, owner);
    await mine(glpManager.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    // GMX.STAKING
    const stakedGmxTracker = GMX_RewardTracker__factory.connect(DEPLOYED.GMX.STAKING.STAKED_GMX_TRACKER, owner);
    await mine(stakedGmxTracker.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const bonusGmxTracker = GMX_RewardTracker__factory.connect(DEPLOYED.GMX.STAKING.BONUS_GMX_TRACKER, owner);
    await mine(bonusGmxTracker.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const feeGmxTracker = GMX_RewardTracker__factory.connect(DEPLOYED.GMX.STAKING.FEE_GMX_TRACKER, owner);
    await mine(feeGmxTracker.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const feeGlpTracker = GMX_RewardTracker__factory.connect(DEPLOYED.GMX.STAKING.FEE_GLP_TRACKER, owner);
    await mine(feeGlpTracker.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const stakedGlpTracker = GMX_RewardTracker__factory.connect(DEPLOYED.GMX.STAKING.STAKED_GLP_TRACKER, owner);
    await mine(stakedGlpTracker.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const stakedGmxDistributor = GMX_RewardDistributor__factory.connect(DEPLOYED.GMX.STAKING.STAKED_GMX_DISTRIBUTOR, owner);
    await mine(stakedGmxDistributor.setAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(stakedGmxDistributor.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const feeGmxDistributor = GMX_RewardDistributor__factory.connect(DEPLOYED.GMX.STAKING.FEE_GMX_DISTRIBUTOR, owner);
    await mine(feeGmxDistributor.setAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(feeGmxDistributor.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const feeGlpDistributor = GMX_RewardDistributor__factory.connect(DEPLOYED.GMX.STAKING.FEE_GLP_DISTRIBUTOR, owner);
    await mine(feeGlpDistributor.setAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(feeGlpDistributor.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const stakedGlpDistributor = GMX_RewardDistributor__factory.connect(DEPLOYED.GMX.STAKING.STAKED_GLP_DISTRIBUTOR, owner);
    await mine(stakedGlpDistributor.setAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(stakedGlpDistributor.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const bonusGmxDistributor = GMX_BonusDistributor__factory.connect(DEPLOYED.GMX.STAKING.BONUS_GMX_DISTRIBUTOR, owner);
    await mine(bonusGmxDistributor.setAdmin(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(bonusGmxDistributor.setGov(DEPLOYED.ORIGAMI.MULTISIG));

    const gmxVester = GMX_Vester__factory.connect(DEPLOYED.GMX.STAKING.GMX_ESGMX_VESTER, owner);
    await mine(gmxVester.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const glpVester = GMX_Vester__factory.connect(DEPLOYED.GMX.STAKING.GLP_ESGMX_VESTER, owner);
    await mine(glpVester.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const gmxRewardRouter = GMX_RewardRouterV2__factory.connect(DEPLOYED.GMX.STAKING.GMX_REWARD_ROUTER, owner);
    await mine(gmxRewardRouter.setGov(DEPLOYED.ORIGAMI.MULTISIG));
    const glpRewardRouter = GMX_RewardRouterV2__factory.connect(DEPLOYED.GMX.STAKING.GLP_REWARD_ROUTER, owner);
    await mine(glpRewardRouter.setGov(DEPLOYED.ORIGAMI.MULTISIG));
}

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const DEPLOYED = getDeployedContracts();
       
    await updateGmxCore(DEPLOYED, owner);

    const gmxEarnAccount = OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner);
    const glpPrimaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner);
    const glpSecondaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner);
    const gmxManager = OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner);
    const glpManager = OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner);
    const gmxRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner);
    const glpRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner);
    const oGMX = OrigamiInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGMX, owner);
    const oGLP = OrigamiInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGLP, owner);
    const ovGMX = OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGMX, owner);
    const ovGLP = OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGLP, owner);
    const tokenPrices = TokenPrices__factory.connect(DEPLOYED.ORIGAMI.TOKEN_PRICES, owner);

    // Transfer ownership to the multisig
    // First grant the msig the admin role (so it can then add/remove minters), and remove admin from the old owner.
    const gmxAdminRole = await oGMX.getRoleAdmin(await oGMX.CAN_MINT());
    await mine(oGMX.grantRole(gmxAdminRole, DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGMX.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGMX.revokeRole(gmxAdminRole, await owner.getAddress()));

    const glpAdminRole = await oGLP.getRoleAdmin(await oGLP.CAN_MINT());
    await mine(oGLP.grantRole(glpAdminRole, DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGLP.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGLP.revokeRole(glpAdminRole, await owner.getAddress()));

    await mine(ovGMX.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGLP.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));

    // And the rest of the ownership.
    await mine(gmxEarnAccount.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpPrimaryEarnAccount.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpSecondaryEarnAccount.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxManager.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpManager.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxRewardsAggr.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpRewardsAggr.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(tokenPrices.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
