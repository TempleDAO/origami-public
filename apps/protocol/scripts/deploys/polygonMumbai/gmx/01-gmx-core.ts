import '@nomiclabs/hardhat-ethers';
import { BigNumber, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { 
    GMX_Timelock, GMX_Timelock__factory,
    GMX_NamedToken, GMX_NamedToken__factory,
    GMX_PriceFeed__factory,
    GMX_Vault, GMX_Vault__factory,
    GMX_USDG, GMX_USDG__factory,
    GMX_Router, GMX_Router__factory,
    GMX_VaultPriceFeed, GMX_VaultPriceFeed__factory,
    GMX_GLP__factory,
    GMX_GlpManager__factory,
    GMX_GMX, GMX_GMX__factory,
    GMX_EsGMX, GMX_EsGMX__factory,
    GMX_MintableBaseToken, GMX_MintableBaseToken__factory,
    GMX_RewardTracker, GMX_RewardTracker__factory,
    GMX_RewardDistributor, GMX_RewardDistributor__factory,
    GMX_BonusDistributor, GMX_BonusDistributor__factory,
    GMX_Vester__factory,
    GMX_RewardRouterV2, GMX_RewardRouterV2__factory,
    GMX_VaultUtils__factory, 
    GMX_VaultErrorController__factory,
    GMX_GLP,
    GMX_StakedGlp__factory,
    GMX_StakedGlp,
    GMX_PriceFeed,
    GMX_GlpManager,
    GMX_Vester,
    GMX_VaultErrorController
} from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  mine,
} from '../../helpers';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';
import { ZERO_ADDRESS } from '../../helpers';

// GMX Reward rates
// 4000 * $2000 = 8MM (19% APR of the seeded $43.14MM GLP liquidity)
const gmxEthPerSecond = ethers.utils.parseEther("4000").div(365*86400);
// 114,557 * $43.14 = 4.942MM (11% of the seeded $43.14MM GLP liquidity)
const gmxEsGmxPerSecond = ethers.utils.parseEther("114557").div(365*86400);

// 5000 * $2000 = 10MM (22% APR of the seeded $45MM GLP liquidity)
const glpEthPerSecond = ethers.utils.parseEther("5000").div(365*86400);
// 81,131 * $43.14 = 3.5MM (7.7% of the seeded $45MM GLP liquidity)
const glpEsGmxPerSecond = ethers.utils.parseEther("81131").div(365*86400);

function bigNumberify(n: number) {
    return BigNumber.from(n);
}

function toChainlinkPrice(value: number) {
    return parseInt((value * Math.pow(10, 8)).toString());
}

function expandDecimals(n: number, decimals: number): BigNumber {
    return bigNumberify(n).mul(bigNumberify(10).pow(decimals));
}

function toUsd(value: number) {
    const normalizedValue = parseInt((value * Math.pow(10, 10)).toString());
    return BigNumber.from(normalizedValue).mul(BigNumber.from(10).pow(20));
}

async function initVaultUtils(vault: GMX_Vault, owner: Signer) {
    const vaultUtilsFactory = new GMX_VaultUtils__factory(owner);
    const vaultUtils = await deployAndMine('vaultUtils', vaultUtilsFactory, vaultUtilsFactory.deploy, vault.address);
    await mine(vault.setVaultUtils(vaultUtils.address));
    return vaultUtils;
}

const errors: string[] = [
    "Vault: zero error",
    "Vault: already initialized",
    "Vault: invalid _maxLeverage",
    "Vault: invalid _taxBasisPoints",
    "Vault: invalid _stableTaxBasisPoints",
    "Vault: invalid _mintBurnFeeBasisPoints",
    "Vault: invalid _swapFeeBasisPoints",
    "Vault: invalid _stableSwapFeeBasisPoints",
    "Vault: invalid _marginFeeBasisPoints",
    "Vault: invalid _liquidationFeeUsd",
    "Vault: invalid _fundingInterval",
    "Vault: invalid _fundingRateFactor",
    "Vault: invalid _stableFundingRateFactor",
    "Vault: token not whitelisted",
    "Vault: _token not whitelisted",
    "Vault: invalid tokenAmount",
    "Vault: _token not whitelisted",
    "Vault: invalid tokenAmount",
    "Vault: invalid usdgAmount",
    "Vault: _token not whitelisted",
    "Vault: invalid usdgAmount",
    "Vault: invalid redemptionAmount",
    "Vault: invalid amountOut",
    "Vault: swaps not enabled",
    "Vault: _tokenIn not whitelisted",
    "Vault: _tokenOut not whitelisted",
    "Vault: invalid tokens",
    "Vault: invalid amountIn",
    "Vault: leverage not enabled",
    "Vault: insufficient collateral for fees",
    "Vault: invalid position.size",
    "Vault: empty position",
    "Vault: position size exceeded",
    "Vault: position collateral exceeded",
    "Vault: invalid liquidator",
    "Vault: empty position",
    "Vault: position cannot be liquidated",
    "Vault: invalid position",
    "Vault: invalid _averagePrice",
    "Vault: collateral should be withdrawn",
    "Vault: _size must be more than _collateral",
    "Vault: invalid msg.sender",
    "Vault: mismatched tokens",
    "Vault: _collateralToken not whitelisted",
    "Vault: _collateralToken must not be a stableToken",
    "Vault: _collateralToken not whitelisted",
    "Vault: _collateralToken must be a stableToken",
    "Vault: _indexToken must not be a stableToken",
    "Vault: _indexToken not shortable",
    "Vault: invalid increase",
    "Vault: reserve exceeds pool",
    "Vault: max USDG exceeded",
    "Vault: reserve exceeds pool",
    "Vault: forbidden",
    "Vault: forbidden",
    "Vault: maxGasPrice exceeded"
];

async function initVaultErrors(vault: GMX_Vault, owner: Signer) {
    const vaultErrorControllerFactory = new GMX_VaultErrorController__factory(owner);
    const vaultErrorController = await deployAndMine('vaultErrorController', vaultErrorControllerFactory, vaultErrorControllerFactory.deploy) as GMX_VaultErrorController;

    await mine(vault.setErrorController(vaultErrorController.address));
    await mine(vaultErrorController.setErrors(vault.address, errors));
    return vaultErrorController;
}

async function initVault(vault: GMX_Vault, router: GMX_Router, usdg: GMX_USDG, priceFeed: GMX_VaultPriceFeed, owner: Signer) {
    await mine(vault.initialize(
      router.address, // router
      usdg.address, // usdg
      priceFeed.address, // priceFeed
      toUsd(5), // liquidationFeeUsd
      600, // fundingRateFactor
      600 // stableFundingRateFactor
    ));
  
    const vaultUtils = await initVaultUtils(vault, owner);
    const vaultErrorController = await initVaultErrors(vault, owner);
  
    return { 
        vault,
        vaultUtils,
        vaultErrorController
    };
}

async function setEthDistribution(
    feeGmxDistributor: GMX_RewardDistributor,
    feeGlpDistributor: GMX_RewardDistributor,
    wethToken: GMX_NamedToken,
    gmxEthPerSecond: BigNumber,
    glpEthPerSecond: BigNumber
) {
    await mine(wethToken.mint(feeGmxDistributor.address, ethers.utils.parseEther("10000000")));
    await mine(feeGmxDistributor.setTokensPerInterval(gmxEthPerSecond));

    await mine(wethToken.mint(feeGlpDistributor.address, ethers.utils.parseEther("10000000")));
    await mine(feeGlpDistributor.setTokensPerInterval(glpEthPerSecond));
}

// Setup the GLP pool with roughtly equal liquidity across BNB/DAI/BTC
export async function addDefaultGlpLiquidity(
    glpManager: GMX_GlpManager,
    signer: Signer,
    glpRewardRouter: GMX_RewardRouterV2,
    bnb: GMX_NamedToken,
    dai: GMX_NamedToken,
    btc: GMX_NamedToken,
    weth: GMX_NamedToken
) {
    const addLiquidity = async (token: GMX_NamedToken, amount: BigNumber) => {
        await mine(token.mint(signer.getAddress(), amount));
        await mine(token.connect(signer).approve(glpManager.address, amount));
        await mine(glpRewardRouter.connect(signer).mintAndStakeGlp(
            token.address,
            amount,
            0,
            0,
        ));
    }

    // Roughly equally weighted pool
    await addLiquidity(bnb, ethers.utils.parseEther("43333"));    // price = 300
    await addLiquidity(dai, ethers.utils.parseEther("10000000")); // price = 1
    await addLiquidity(btc, ethers.utils.parseUnits("167", 8));   // price = 60,000 & 8dp's
    await addLiquidity(weth, ethers.utils.parseEther("5000"));     // price = 200
}

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const GOV_DEPLOYED = govDeployedContracts();

    const tokenFactory = new GMX_NamedToken__factory(owner);
    const bnb = await deployAndMine('bnb', tokenFactory, tokenFactory.deploy, "BNB", "BNB") as GMX_NamedToken;
    const weth = await deployAndMine('weth', tokenFactory, tokenFactory.deploy, "WETH", "WETH") as GMX_NamedToken;
    const btc = await deployAndMine('btc', tokenFactory, tokenFactory.deploy, "Bitcoin", "BTC") as GMX_NamedToken;
    const dai = await deployAndMine('dai', tokenFactory, tokenFactory.deploy, "Dai", "DAI") as GMX_NamedToken;

    const priceFeedFactory = new GMX_PriceFeed__factory(owner);
    const bnbPriceFeed = await deployAndMine('bnbPriceFeed', priceFeedFactory, priceFeedFactory.deploy) as GMX_PriceFeed;
    const wethPriceFeed = await deployAndMine('wethPriceFeed', priceFeedFactory, priceFeedFactory.deploy) as GMX_PriceFeed;
    const btcPriceFeed = await deployAndMine('btcPriceFeed', priceFeedFactory, priceFeedFactory.deploy) as GMX_PriceFeed;
    const daiPriceFeed = await deployAndMine('daiPriceFeed', priceFeedFactory, priceFeedFactory.deploy) as GMX_PriceFeed;
    
    const vaultFactory = new GMX_Vault__factory(owner);
    const vault = await deployAndMine('vault', vaultFactory, vaultFactory.deploy) as GMX_Vault;
    
    const usdgFactory = new GMX_USDG__factory(owner);
    const usdg = await deployAndMine('usdg', usdgFactory, usdgFactory.deploy, vault.address) as GMX_USDG;
    
    const routerFactory = new GMX_Router__factory(owner);
    const router = await deployAndMine('router', routerFactory, routerFactory.deploy,
        vault.address, usdg.address, bnb.address
    ) as GMX_Router;

    const vaultPriceFeedFactory = new GMX_VaultPriceFeed__factory(owner);
    const vaultPriceFeed = await deployAndMine('vaultPriceFeed', vaultPriceFeedFactory, vaultPriceFeedFactory.deploy) as GMX_VaultPriceFeed;

    const glpFactory = new GMX_GLP__factory(owner);
    const glp = await deployAndMine('glp', glpFactory, glpFactory.deploy) as GMX_GLP;

    await initVault(vault, router, usdg, vaultPriceFeed, owner);

    const glpManagerFactory = new GMX_GlpManager__factory(owner);
    const glpManager = await deployAndMine('glpManager', glpManagerFactory, glpManagerFactory.deploy,
        vault.address, usdg.address, glp.address, ethers.constants.AddressZero, 15 * 60
    ) as GMX_GlpManager;
    await mine(usdg.addVault(glpManager.address));

    const rewardRouterV2 = new GMX_RewardRouterV2__factory(owner);
    const gmxRewardRouter = await deployAndMine('gmxRewardRouter', rewardRouterV2, rewardRouterV2.deploy) as GMX_RewardRouterV2;
    const glpRewardRouter = await deployAndMine('glpRewardRouter', rewardRouterV2, rewardRouterV2.deploy) as GMX_RewardRouterV2;

    const timelockFactory = new GMX_Timelock__factory(owner);
    const timelock = await deployAndMine('timelock', timelockFactory, timelockFactory.deploy,
        GOV_DEPLOYED.ORIGAMI.MULTISIG, // _admin
        10, // _buffer
        GOV_DEPLOYED.ORIGAMI.MULTISIG, // _tokenManager
        GOV_DEPLOYED.ORIGAMI.MULTISIG, // _mintReceiver
        glpManager.address, // _glpManager
        gmxRewardRouter.address, // _rewardRouter
        expandDecimals(100000000, 18), // _maxTokenSupply
        10, // marginFeeBasisPoints
        100 // maxMarginFeeBasisPoints
    ) as GMX_Timelock;

    await mine(vaultPriceFeed.setTokenConfig(bnb.address, bnbPriceFeed.address, 8, false));
    await mine(vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8, false));
    await mine(vaultPriceFeed.setTokenConfig(weth.address, wethPriceFeed.address, 8, false));
    await mine(vaultPriceFeed.setTokenConfig(dai.address, daiPriceFeed.address, 8, false));

    await mine(daiPriceFeed.setLatestAnswer(toChainlinkPrice(1)));
    await mine(vault.setTokenConfig(
        dai.address, // _token
        18, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps
        0, // _maxUsdgAmount
        true, // _isStable
        false // _isShortable
    ));

    await mine(btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000)));
    await mine(vault.setTokenConfig(
        btc.address, // _token
        8, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps
        0, // _maxUsdgAmount
        false, // _isStable
        true // _isShortable
    ));

    await mine(wethPriceFeed.setLatestAnswer(toChainlinkPrice(2000)));
    await mine(vault.setTokenConfig(
        weth.address, // _token
        18, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps
        0, // _maxUsdgAmount
        false, // _isStable
        true // _isShortable
    ));

    await mine(bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300)));
    await mine(vault.setTokenConfig(
        bnb.address, // _token
        18, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps,
        0, // _maxUsdgAmount
        false, // _isStable
        true // _isShortable
    ));

    await mine(glp.setInPrivateTransferMode(true));
    await mine(glp.setMinter(glpManager.address, true));
    await mine(glpManager.setInPrivateMode(true));

    const gmxFactory = new GMX_GMX__factory(owner); 
    const gmx = await deployAndMine('gmx', gmxFactory, gmxFactory.deploy) as GMX_GMX;

    const esGmxFactory = new GMX_EsGMX__factory(owner); 
    const esGmx = await deployAndMine('esGmx', esGmxFactory, esGmxFactory.deploy) as GMX_EsGMX;

    const bnGmxFactory = new GMX_MintableBaseToken__factory(owner);
    const bnGmx = await deployAndMine('bnGmx', bnGmxFactory, bnGmxFactory.deploy, 
        "Bonus GMX",
        "bnGMX",
        0
    ) as GMX_MintableBaseToken;

    const rewardTrackerFactory = new GMX_RewardTracker__factory(owner);
    const rewardDistributorFactory = new GMX_RewardDistributor__factory(owner);
    const bonusDistributorFactory = new GMX_BonusDistributor__factory(owner);

    // GMX
    const stakedGmxTracker = await deployAndMine('stakedGmxTracker', rewardTrackerFactory, rewardTrackerFactory.deploy,
        "Staked GMX",
        "sGMX"
    ) as GMX_RewardTracker;
    const stakedGmxDistributor = await deployAndMine('stakedGmxDistributor', rewardDistributorFactory, rewardDistributorFactory.deploy,
        esGmx.address,
        stakedGmxTracker.address
    ) as GMX_RewardDistributor;
    await mine(stakedGmxTracker.initialize([gmx.address, esGmx.address], stakedGmxDistributor.address));
    await mine(stakedGmxDistributor.updateLastDistributionTime());

    const bonusGmxTracker = await deployAndMine('bonusGmxTracker', rewardTrackerFactory, rewardTrackerFactory.deploy,
        "Staked + Bonus GMX",
        "sbGMX"
    ) as GMX_RewardTracker;
    const bonusGmxDistributor = await deployAndMine('bonusGmxDistributor', bonusDistributorFactory, bonusDistributorFactory.deploy,
        bnGmx.address,
        bonusGmxTracker.address
    ) as GMX_BonusDistributor;
    await mine(bonusGmxTracker.initialize([stakedGmxTracker.address], bonusGmxDistributor.address));
    await mine(bonusGmxDistributor.updateLastDistributionTime());

    const feeGmxTracker = await deployAndMine('feeGmxTracker', rewardTrackerFactory, rewardTrackerFactory.deploy,
        "Staked + Bonus + Fee GMX",
        "sbfGMX"
    ) as GMX_RewardTracker;
    const feeGmxDistributor = await deployAndMine('feeGmxDistributor', rewardDistributorFactory, rewardDistributorFactory.deploy,
        weth.address,
        feeGmxTracker.address
    ) as GMX_RewardDistributor;
    await mine(feeGmxTracker.initialize([bonusGmxTracker.address, bnGmx.address], feeGmxDistributor.address));
    await mine(feeGmxDistributor.updateLastDistributionTime());

    // GLP
    const feeGlpTracker = await deployAndMine('feeGlpTracker', rewardTrackerFactory, rewardTrackerFactory.deploy,
        "Fee GLP",
        "fGLP"
    ) as GMX_RewardTracker;
    const feeGlpDistributor = await deployAndMine('feeGlpDistributor', rewardDistributorFactory, rewardDistributorFactory.deploy,
        weth.address,
        feeGlpTracker.address
    ) as GMX_RewardDistributor;
    await mine(feeGlpTracker.initialize([glp.address], feeGlpDistributor.address));
    await mine(feeGlpDistributor.updateLastDistributionTime());

    const stakedGlpTracker = await deployAndMine('stakedGlpTracker', rewardTrackerFactory, rewardTrackerFactory.deploy,
        "Fee + Staked GLP",
        "fsGLP"
    ) as GMX_RewardTracker;
    const stakedGlpDistributor = await deployAndMine('stakedGlpDistributor', rewardDistributorFactory, rewardDistributorFactory.deploy,
        esGmx.address,
        stakedGlpTracker.address
    ) as GMX_RewardDistributor;
    await mine(stakedGlpTracker.initialize([feeGlpTracker.address], stakedGlpDistributor.address));
    await mine(stakedGlpDistributor.updateLastDistributionTime());

    // Staked GLP
    const stakedGlpFactory = new GMX_StakedGlp__factory(owner);
    const stakedGlp = await deployAndMine('stakedGlp', stakedGlpFactory, stakedGlpFactory.deploy, 
        glp.address, 
        glpManager.address, 
        stakedGlpTracker.address, 
        feeGlpTracker.address
    ) as GMX_StakedGlp;
    const vestingDuration = 365 * 24 * 60 * 60;

    const vesterFactory = new GMX_Vester__factory(owner);
    const gmxVester = await deployAndMine('gmxVester', vesterFactory, vesterFactory.deploy,
        "Vested GMX", // _name
        "vGMX", // _symbol
        vestingDuration, // _vestingDuration
        esGmx.address, // _esToken
        feeGmxTracker.address, // _pairToken
        gmx.address, // _claimableToken
        stakedGmxTracker.address, // _rewardTracker
    ) as GMX_Vester;

    const glpVester = await deployAndMine('glpVester', vesterFactory, vesterFactory.deploy,
        "Vested GLP", // _name
        "vGLP", // _symbol
        vestingDuration, // _vestingDuration
        esGmx.address, // _esToken
        stakedGlpTracker.address, // _pairToken
        gmx.address, // _claimableToken
        stakedGlpTracker.address, // _rewardTracker
    ) as GMX_Vester;

    await mine(stakedGmxTracker.setInPrivateTransferMode(true));
    await mine(stakedGmxTracker.setInPrivateStakingMode(true));
    await mine(bonusGmxTracker.setInPrivateTransferMode(true));
    await mine(bonusGmxTracker.setInPrivateStakingMode(true));
    await mine(bonusGmxTracker.setInPrivateClaimingMode(true));
    await mine(feeGmxTracker.setInPrivateTransferMode(true));
    await mine(feeGmxTracker.setInPrivateStakingMode(true));
    
    await mine(feeGlpTracker.setInPrivateTransferMode(true));
    await mine(feeGlpTracker.setInPrivateStakingMode(true));
    await mine(stakedGlpTracker.setInPrivateTransferMode(true));
    await mine(stakedGlpTracker.setInPrivateStakingMode(true));

    await mine(esGmx.setInPrivateTransferMode(true));

    await mine(gmxRewardRouter.initialize(
        weth.address,
        gmx.address,
        esGmx.address,
        bnGmx.address,
        glp.address,
        stakedGmxTracker.address,
        bonusGmxTracker.address,
        feeGmxTracker.address,
        feeGlpTracker.address,
        stakedGlpTracker.address,
        glpManager.address,
        gmxVester.address,
        glpVester.address
    ));

    await mine(glpRewardRouter.initialize(
        weth.address,
        ZERO_ADDRESS,
        ZERO_ADDRESS,
        ZERO_ADDRESS,
        glp.address,
        ZERO_ADDRESS,
        ZERO_ADDRESS,
        ZERO_ADDRESS,
        feeGlpTracker.address,
        stakedGlpTracker.address,
        glpManager.address,
        ZERO_ADDRESS,
        ZERO_ADDRESS
      ));

    // allow bonusGmxTracker to stake stakedGmxTracker
    await mine(stakedGmxTracker.setHandler(bonusGmxTracker.address, true));
    
    // allow bonusGmxTracker to stake feeGmxTracker
    await mine(bonusGmxTracker.setHandler(feeGmxTracker.address, true));
    await mine(bonusGmxDistributor.setBonusMultiplier(10000));

    // allow feeGmxTracker to stake bnGmx
    await mine(bnGmx.setHandler(feeGmxTracker.address, true));

    // allow stakedGlpTracker to stake feeGlpTracker
    await mine(feeGlpTracker.setHandler(stakedGlpTracker.address, true));

    // allow stakedGlp to transfer staked GLP
    await mine(stakedGlpTracker.setHandler(stakedGlp.address, true));
    await mine(feeGlpTracker.setHandler(stakedGlp.address, true));

    // allow feeGlpTracker to stake glp
    await mine(glp.setHandler(feeGlpTracker.address, true));

    // mint esGmx for distributors
    await mine(esGmx.setMinter(await owner.getAddress(), true));
    await mine(esGmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(esGmx.mint(stakedGmxDistributor.address, expandDecimals(10000000, 18)));
    await mine(stakedGmxDistributor.setTokensPerInterval(gmxEsGmxPerSecond));
    await mine(esGmx.mint(stakedGlpDistributor.address, expandDecimals(10000000, 18)));
    await mine(stakedGlpDistributor.setTokensPerInterval(glpEsGmxPerSecond));

    // mint bnGmx for distributor
    await mine(bnGmx.setMinter(await owner.getAddress(), true));
    await mine(bnGmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(bnGmx.mint(bonusGmxDistributor.address, expandDecimals(10000000, 18)));

    await mine(esGmx.setHandler(await owner.getAddress(), true));
    await mine(esGmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(gmxVester.setHandler(await owner.getAddress(), true));
    await mine(gmxVester.setHandler(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));

    await mine(esGmx.setHandler(gmxRewardRouter.address, true));
    await mine(esGmx.setHandler(stakedGmxDistributor.address, true));
    await mine(esGmx.setHandler(stakedGlpDistributor.address, true));
    await mine(esGmx.setHandler(stakedGmxTracker.address, true));
    await mine(esGmx.setHandler(stakedGlpTracker.address, true));
    await mine(esGmx.setHandler(gmxVester.address, true));
    await mine(esGmx.setHandler(glpVester.address, true));

    await mine(glpManager.setHandler(glpRewardRouter.address, true));
    await mine(stakedGmxTracker.setHandler(gmxRewardRouter.address, true));
    await mine(bonusGmxTracker.setHandler(gmxRewardRouter.address, true));
    await mine(feeGmxTracker.setHandler(gmxRewardRouter.address, true));
    await mine(feeGlpTracker.setHandler(gmxRewardRouter.address, true));
    await mine(feeGlpTracker.setHandler(glpRewardRouter.address, true));
    await mine(stakedGlpTracker.setHandler(gmxRewardRouter.address, true));
    await mine(stakedGlpTracker.setHandler(glpRewardRouter.address, true));

    await mine(esGmx.setHandler(gmxRewardRouter.address, true));
    await mine(bnGmx.setMinter(gmxRewardRouter.address, true));
    await mine(esGmx.setMinter(gmxVester.address, true));
    await mine(esGmx.setMinter(glpVester.address, true));

    await mine(gmxVester.setHandler(gmxRewardRouter.address, true));
    await mine(glpVester.setHandler(gmxRewardRouter.address, true));

    await mine(feeGmxTracker.setHandler(gmxVester.address, true));
    await mine(stakedGlpTracker.setHandler(glpVester.address, true));

    // Mint GMX to the vester contracts 
    await mine(gmx.setMinter(await owner.getAddress(), true));
    await mine(gmx.setMinter(GOV_DEPLOYED.ORIGAMI.MULTISIG, true));
    await mine(gmx.mint(gmxVester.address, expandDecimals(10000000, 18)));
    await mine(gmx.mint(glpVester.address, expandDecimals(10000000, 18)));

    await mine(glpManager.setGov(timelock.address));
    await mine(stakedGmxTracker.setGov(timelock.address));
    await mine(bonusGmxTracker.setGov(timelock.address));
    await mine(feeGmxTracker.setGov(timelock.address));
    await mine(feeGlpTracker.setGov(timelock.address));
    await mine(stakedGlpTracker.setGov(timelock.address));
    await mine(stakedGmxDistributor.setGov(timelock.address));
    await mine(stakedGlpDistributor.setGov(timelock.address));
    await mine(esGmx.setGov(timelock.address));
    await mine(bnGmx.setGov(timelock.address));
    await mine(gmxVester.setGov(timelock.address));
    await mine(glpVester.setGov(timelock.address));

    await setEthDistribution(feeGmxDistributor, feeGlpDistributor, weth, gmxEthPerSecond, glpEthPerSecond);

    // Setup the fees in the glp vault
    await mine(vault.setFees(
        50, // _taxBasisPoints
        10, // _stableTaxBasisPoints
        25, // _mintBurnFeeBasisPoints
        30, // _swapFeeBasisPoints
        4, // _stableSwapFeeBasisPoints
        10, // _marginFeeBasisPoints
        ethers.utils.parseUnits("5", 30), // _liquidationFeeUsd
        0, // _minProfitTime
        true // _hasDynamicFees
    ));

    await mine(feeGmxDistributor.setTokensPerInterval(BigNumber.from('413359700000')));
    await mine(stakedGmxDistributor.setTokensPerInterval(BigNumber.from('206679894000000')));
    await mine(feeGlpDistributor.setTokensPerInterval(BigNumber.from('41335970000000')));
    await mine(stakedGlpDistributor.setTokensPerInterval(BigNumber.from('20667989410000000')));

    // Stake some GMX to seed the pool
    {
        const amount = ethers.utils.parseEther("1000000");
        await mine(gmx.mint(owner.getAddress(), amount));
        await mine(gmx.approve(stakedGmxTracker.address, amount));
        await mine(gmxRewardRouter.stakeGmx(amount));
    }

    // Seed and stake some tokens for GLP
    await addDefaultGlpLiquidity(
        glpManager,
        owner,
        glpRewardRouter,
        bnb,
        dai,
        btc,
        weth
    );

  // Ownership transferred to the msig in 99-post-deploy.ts
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
