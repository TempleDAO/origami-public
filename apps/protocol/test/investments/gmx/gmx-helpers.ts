
import { BigNumber, BigNumberish, ethers, Signer } from "ethers";
import { 
    GMX_Timelock, GMX_Timelock__factory,
    GMX_GmxTimelock__factory,
    GMX_Token, GMX_Token__factory,
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
    GMX_TokenManager__factory,
    GMX_GLP,
    GMX_StakedGlp__factory,
    GMX_StakedGlp,
    GMX_GlpManager,
    GMX_IFastPriceFeed__factory,
    GMX_Vester,
} from "../../../typechain";
import { ZERO_ADDRESS, impersonateSigner, mineForwardSeconds } from "../../helpers";

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
    const vaultUtils = await new GMX_VaultUtils__factory(owner).deploy(vault.address);
    await vault.setVaultUtils(vaultUtils.address);
    return vaultUtils;
}

async function initVault(vault: GMX_Vault, router: GMX_Router, usdg: GMX_USDG, priceFeed: GMX_VaultPriceFeed, owner: Signer) {
    await vault.initialize(
      router.address, // router
      usdg.address, // usdg
      priceFeed.address, // priceFeed
      toUsd(5), // liquidationFeeUsd
      600, // fundingRateFactor
      600 // stableFundingRateFactor
    );
  
    const vaultUtils = await initVaultUtils(vault, owner);
    const vaultErrorController = await initVaultErrors(vault, owner);
  
    return { 
        vault,
        vaultUtils,
        vaultErrorController
    };
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
    const vaultErrorController = await new GMX_VaultErrorController__factory(owner).deploy();

    await vault.setErrorController(vaultErrorController.address);
    await vaultErrorController.setErrors(vault.address, errors);
    return vaultErrorController;
}

export interface GmxContracts {
    gmxRewardRouter: GMX_RewardRouterV2,
    glpRewardRouter: GMX_RewardRouterV2,
    stakedGmxTracker: GMX_RewardTracker,
    bonusGmxTracker: GMX_RewardTracker,
    feeGmxTracker: GMX_RewardTracker,
    stakedGlpTracker: GMX_RewardTracker,
    feeGlpTracker: GMX_RewardTracker,

    wrappedNativeToken: GMX_Token,
    gmxToken: GMX_GMX,
    glpToken: GMX_GLP,
    esGmxToken: GMX_EsGMX,
    multiplierPointsToken: GMX_MintableBaseToken,
    timelock: GMX_Timelock,

    stakedGmxDistributor: GMX_RewardDistributor,
    bonusGmxDistributor: GMX_BonusDistributor,
    feeGmxDistributor: GMX_RewardDistributor,
    feeGlpDistributor: GMX_RewardDistributor,
    stakedGlpDistributor: GMX_RewardDistributor,

    bnbToken: GMX_Token,
    btcToken: GMX_Token,
    daiToken: GMX_Token,
    vault: GMX_Vault,

    stakedGlp: GMX_StakedGlp,
    glpManager: GMX_GlpManager,

    gmxVester: GMX_Vester,
    glpVester: GMX_Vester,
}

// Setup copied from GMX's test suite.
// https://github.com/gmx-io/gmx-contracts/blob/master/test/staking/RewardRouterV2.js#L58
export async function deployGmx(
    owner: Signer,
    esGmxPerSecondForGmx: BigNumber,
    esGmxPerSecondForGlp: BigNumber,
    ethPerSecondForGmx: BigNumber,
    ethPerSecondForGlp: BigNumber,
): Promise<GmxContracts> {   
    const bnb = await new GMX_Token__factory(owner).deploy();
    const bnbPriceFeed = await new GMX_PriceFeed__factory(owner).deploy();
    const weth = await new GMX_Token__factory(owner).deploy();
    const wethPriceFeed = await new GMX_PriceFeed__factory(owner).deploy();
    const btc = await new GMX_Token__factory(owner).deploy();
    const btcPriceFeed = await new GMX_PriceFeed__factory(owner).deploy();
    const dai = await new GMX_Token__factory(owner).deploy();
    const daiPriceFeed = await new GMX_PriceFeed__factory(owner).deploy();
    
    const vault = await new GMX_Vault__factory(owner).deploy();
    const usdg = await new GMX_USDG__factory(owner).deploy(vault.address);
    const router = await new GMX_Router__factory(owner).deploy(vault.address, usdg.address, bnb.address);
    const vaultPriceFeed = await new GMX_VaultPriceFeed__factory(owner).deploy();
    const glp = await new GMX_GLP__factory(owner).deploy();

    await initVault(vault, router, usdg, vaultPriceFeed, owner);
    const glpManager = await new GMX_GlpManager__factory(owner).deploy(
        vault.address, usdg.address, glp.address, ethers.constants.AddressZero, 15 * 60);

    const gmxRewardRouter = await new GMX_RewardRouterV2__factory(owner).deploy();
    const glpRewardRouter = await new GMX_RewardRouterV2__factory(owner).deploy();

    const timelock = await new GMX_Timelock__factory(owner).deploy(
        await owner.getAddress(), // _admin
        10, // _buffer
        await owner.getAddress(), // _tokenManager
        await owner.getAddress(), // _mintReceiver
        glpManager.address, // _glpManager
        gmxRewardRouter.address, // _rewardRouter
        expandDecimals(1000000, 18), // _maxTokenSupply
        10, // marginFeeBasisPoints
        100 // maxMarginFeeBasisPoints
    );
    await usdg.addVault(glpManager.address);

    await vaultPriceFeed.setTokenConfig(bnb.address, bnbPriceFeed.address, 8, false);
    await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8, false);
    await vaultPriceFeed.setTokenConfig(weth.address, wethPriceFeed.address, 8, false);
    await vaultPriceFeed.setTokenConfig(dai.address, daiPriceFeed.address, 8, false);
    
    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    await vault.setTokenConfig(
        dai.address, // _token
        18, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps
        0, // _maxUsdgAmount
        true, // _isStable
        false // _isShortable
    );

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    await vault.setTokenConfig(
        btc.address, // _token
        8, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps
        0, // _maxUsdgAmount
        false, // _isStable
        true // _isShortable
    );

    await wethPriceFeed.setLatestAnswer(toChainlinkPrice(2000))
    await vault.setTokenConfig(
        weth.address, // _token
        18, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps
        0, // _maxUsdgAmount
        false, // _isStable
        true // _isShortable
    );

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    await vault.setTokenConfig(
        bnb.address, // _token
        18, // _tokenDecimals
        10000, // _tokenWeight
        75, // _minProfitBps,
        0, // _maxUsdgAmount
        false, // _isStable
        true // _isShortable
    );

    await glp.setInPrivateTransferMode(true);
    await glp.setMinter(glpManager.address, true);
    await glpManager.setInPrivateMode(true);

    const gmx = await new GMX_GMX__factory(owner).deploy();
    const esGmx = await new GMX_EsGMX__factory(owner).deploy();
    const bnGmx = await new GMX_MintableBaseToken__factory(owner).deploy("Bonus GMX", "bnGMX", 0);

    // GMX
    const stakedGmxTracker = await new GMX_RewardTracker__factory(owner).deploy("Staked GMX", "sGMX");
    const stakedGmxDistributor = await new GMX_RewardDistributor__factory(owner).deploy(esGmx.address, stakedGmxTracker.address);
    await stakedGmxTracker.initialize([gmx.address, esGmx.address], stakedGmxDistributor.address);
    await stakedGmxDistributor.updateLastDistributionTime();

    const bonusGmxTracker = await new GMX_RewardTracker__factory(owner).deploy("Staked + Bonus GMX", "sbGMX");
    const bonusGmxDistributor = await new GMX_BonusDistributor__factory(owner).deploy(bnGmx.address, bonusGmxTracker.address);
    await bonusGmxTracker.initialize([stakedGmxTracker.address], bonusGmxDistributor.address);
    await bonusGmxDistributor.updateLastDistributionTime();

    const feeGmxTracker = await new GMX_RewardTracker__factory(owner).deploy("Staked + Bonus + Fee GMX", "sbfGMX");
    const feeGmxDistributor = await new GMX_RewardDistributor__factory(owner).deploy(weth.address, feeGmxTracker.address);
    await feeGmxTracker.initialize([bonusGmxTracker.address, bnGmx.address], feeGmxDistributor.address);
    await feeGmxDistributor.updateLastDistributionTime();

    // GLP
    const feeGlpTracker = await new GMX_RewardTracker__factory(owner).deploy("Fee GLP", "fGLP");
    const feeGlpDistributor = await new GMX_RewardDistributor__factory(owner).deploy(weth.address, feeGlpTracker.address);
    await feeGlpTracker.initialize([glp.address], feeGlpDistributor.address);
    await feeGlpDistributor.updateLastDistributionTime();

    const stakedGlpTracker = await new GMX_RewardTracker__factory(owner).deploy("Fee + Staked GLP", "fsGLP");
    const stakedGlpDistributor = await new GMX_RewardDistributor__factory(owner).deploy(esGmx.address, stakedGlpTracker.address);
    await stakedGlpTracker.initialize([feeGlpTracker.address], stakedGlpDistributor.address);
    await stakedGlpDistributor.updateLastDistributionTime();

    const stakedGlp = await new GMX_StakedGlp__factory(owner).deploy(glp.address, glpManager.address, stakedGlpTracker.address, feeGlpTracker.address);
    const vestingDuration = 365 * 24 * 60 * 60;
    
    const gmxVester = await new GMX_Vester__factory(owner).deploy(
        "Vested GMX", // _name
        "vGMX", // _symbol
        vestingDuration, // _vestingDuration
        esGmx.address, // _esToken
        feeGmxTracker.address, // _pairToken
        gmx.address, // _claimableToken
        stakedGmxTracker.address, // _rewardTracker
    );

    const glpVester = await new GMX_Vester__factory(owner).deploy(
        "Vested GLP", // _name
        "vGLP", // _symbol
        vestingDuration, // _vestingDuration
        esGmx.address, // _esToken
        stakedGlpTracker.address, // _pairToken
        gmx.address, // _claimableToken
        stakedGlpTracker.address, // _rewardTracker
    );

    await stakedGmxTracker.setInPrivateTransferMode(true);
    await stakedGmxTracker.setInPrivateStakingMode(true);
    await bonusGmxTracker.setInPrivateTransferMode(true);
    await bonusGmxTracker.setInPrivateStakingMode(true);
    await bonusGmxTracker.setInPrivateClaimingMode(true);
    await feeGmxTracker.setInPrivateTransferMode(true);
    await feeGmxTracker.setInPrivateStakingMode(true);
    
    await feeGlpTracker.setInPrivateTransferMode(true);
    await feeGlpTracker.setInPrivateStakingMode(true);
    await stakedGlpTracker.setInPrivateTransferMode(true);
    await stakedGlpTracker.setInPrivateStakingMode(true);

    await esGmx.setInPrivateTransferMode(true);

    await gmxRewardRouter.initialize(
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
    );

    await glpRewardRouter.initialize(
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
      );
    
    // allow bonusGmxTracker to stake stakedGmxTracker
    await stakedGmxTracker.setHandler(bonusGmxTracker.address, true);
    
    // allow bonusGmxTracker to stake feeGmxTracker
    await bonusGmxTracker.setHandler(feeGmxTracker.address, true);
    await bonusGmxDistributor.setBonusMultiplier(10000);

    // allow feeGmxTracker to stake bnGmx
    await bnGmx.setHandler(feeGmxTracker.address, true);

    // allow stakedGlpTracker to stake feeGlpTracker
    await feeGlpTracker.setHandler(stakedGlpTracker.address, true);

    // allow stakedGlp to transfer staked GLP
    await stakedGlpTracker.setHandler(stakedGlp.address, true);
    await feeGlpTracker.setHandler(stakedGlp.address, true);

    // allow feeGlpTracker to stake glp
    await glp.setHandler(feeGlpTracker.address, true);

    // mint esGmx for distributors
    await esGmx.setMinter(await owner.getAddress(), true);
    await esGmx.mint(stakedGmxDistributor.address, expandDecimals(50000, 18));
    await stakedGmxDistributor.setTokensPerInterval(esGmxPerSecondForGmx);

    await esGmx.mint(stakedGlpDistributor.address, expandDecimals(50000, 18));
    await stakedGlpDistributor.setTokensPerInterval(esGmxPerSecondForGlp);

    // mint bnGmx for distributor
    await bnGmx.setMinter(await owner.getAddress(), true);
    await bnGmx.mint(bonusGmxDistributor.address, expandDecimals(1500, 18));

    await esGmx.setHandler(await owner.getAddress(), true);
    await gmxVester.setHandler(await owner.getAddress(), true);

    await esGmx.setHandler(gmxRewardRouter.address, true);
    await esGmx.setHandler(stakedGmxDistributor.address, true);
    await esGmx.setHandler(stakedGlpDistributor.address, true);
    await esGmx.setHandler(stakedGmxTracker.address, true);
    await esGmx.setHandler(stakedGlpTracker.address, true);
    await esGmx.setHandler(gmxVester.address, true);
    await esGmx.setHandler(glpVester.address, true);

    await glpManager.setHandler(glpRewardRouter.address, true);
    await stakedGmxTracker.setHandler(gmxRewardRouter.address, true);
    await bonusGmxTracker.setHandler(gmxRewardRouter.address, true);
    await feeGmxTracker.setHandler(gmxRewardRouter.address, true);
    await feeGlpTracker.setHandler(gmxRewardRouter.address, true);
    await feeGlpTracker.setHandler(glpRewardRouter.address, true);
    await stakedGlpTracker.setHandler(gmxRewardRouter.address, true);
    await stakedGlpTracker.setHandler(glpRewardRouter.address, true);

    await esGmx.setHandler(gmxRewardRouter.address, true);
    await bnGmx.setMinter(gmxRewardRouter.address, true);
    await esGmx.setMinter(gmxVester.address, true);
    await esGmx.setMinter(glpVester.address, true);

    await gmxVester.setHandler(gmxRewardRouter.address, true);
    await glpVester.setHandler(gmxRewardRouter.address, true);

    await feeGmxTracker.setHandler(gmxVester.address, true);
    await stakedGlpTracker.setHandler(glpVester.address, true);

    // Mint GMX to the vester contracts 
    await gmx.setMinter(await owner.getAddress(), true);
    await gmx.mint(gmxVester.address, expandDecimals(10000, 18));
    await gmx.mint(glpVester.address, expandDecimals(10000, 18));

    await glpManager.setGov(timelock.address);
    await stakedGmxTracker.setGov(timelock.address);
    await bonusGmxTracker.setGov(timelock.address);
    await feeGmxTracker.setGov(timelock.address);
    await feeGlpTracker.setGov(timelock.address);
    await feeGmxDistributor.setGov(timelock.address);
    await feeGlpDistributor.setGov(timelock.address);
    await stakedGlpTracker.setGov(timelock.address);
    await stakedGmxDistributor.setGov(timelock.address);
    await stakedGlpDistributor.setGov(timelock.address);
    await esGmx.setGov(timelock.address);
    await bnGmx.setGov(timelock.address);
    await gmxVester.setGov(timelock.address);
    await glpVester.setGov(timelock.address);

    await setEthDistribution(feeGmxTracker, feeGlpTracker, weth, owner, ethPerSecondForGmx, ethPerSecondForGlp);

    // Setup the fees in the glp vault
    await vault.setFees(
        50, // _taxBasisPoints
        10, // _stableTaxBasisPoints
        25, // _mintBurnFeeBasisPoints
        30, // _swapFeeBasisPoints
        4, // _stableSwapFeeBasisPoints
        10, // _marginFeeBasisPoints
        ethers.utils.parseUnits("5", 30), // _liquidationFeeUsd
        0, // _minProfitTime
        true // _hasDynamicFees
    );

    return {
        gmxRewardRouter,
        glpRewardRouter,
        stakedGmxTracker,
        bonusGmxTracker,
        feeGmxTracker,
        stakedGlpTracker,
        feeGlpTracker,

        wrappedNativeToken: weth,
        glpToken: glp,
        gmxToken: gmx,
        esGmxToken: esGmx,
        multiplierPointsToken: bnGmx,
        timelock,

        stakedGmxDistributor,
        bonusGmxDistributor,
        feeGmxDistributor,
        feeGlpDistributor,
        stakedGlpDistributor,

        bnbToken: bnb,
        btcToken: btc,
        daiToken: dai,
        vault,
        stakedGlp,
        glpManager,

        gmxVester,
        glpVester,
    }
}

// The 'last distribution time' for the first stake uses this timestamp
// As the first rewards starting point.
// So reset it so it's closest to 'now'.
export async function updateDistributionTime(gmxContracts: GmxContracts) {
    await gmxContracts.stakedGlpDistributor.updateLastDistributionTime();
    await gmxContracts.feeGlpDistributor.updateLastDistributionTime();
    await gmxContracts.stakedGmxDistributor.updateLastDistributionTime();
    await gmxContracts.bonusGmxDistributor.updateLastDistributionTime();
    await gmxContracts.feeGmxDistributor.updateLastDistributionTime();
}

async function setEthDistribution(
    feeGmxTracker: GMX_RewardTracker, feeGlpTracker: GMX_RewardTracker, 
    wethToken: GMX_Token, owner: Signer, 
    ethPerSecondForGmx: BigNumber, ethPerSecondForGlp: BigNumber
) {
    const ethGmxDistributorAddr = await feeGmxTracker.distributor();
    await wethToken.mint(ethGmxDistributorAddr, ethers.utils.parseEther("1000"));
    const ethGmxDistributor = GMX_RewardDistributor__factory.connect(ethGmxDistributorAddr, owner);
    await ethGmxDistributor.setTokensPerInterval(ethPerSecondForGmx);

    const ethGlpDistributorAddr = await feeGlpTracker.distributor();
    await wethToken.mint(ethGlpDistributorAddr, ethers.utils.parseEther("1000"));
    const ethGlpDistributor = GMX_RewardDistributor__factory.connect(ethGlpDistributorAddr, owner);
    await ethGlpDistributor.setTokensPerInterval(ethPerSecondForGlp);
}

// Setup the GLP pool with roughtly equal liquidity across BNB/DAI/BTC
export async function addDefaultGlpLiquidity(signer: Signer, gmxContracts: GmxContracts) {
    const glpManager = await gmxContracts.glpRewardRouter.glpManager();

    const addLiquidity = async (token: GMX_Token, amount: BigNumber) => {
        await token.mint(signer.getAddress(), amount);
        await token.connect(signer).approve(glpManager, amount);
        await gmxContracts.glpRewardRouter.connect(signer).mintAndStakeGlp(
            token.address,
            amount,
            0,
            0,
        );
    }

    // Roughly equally weighted pool
    await addLiquidity(gmxContracts.bnbToken, ethers.utils.parseEther("43333"));    // price = 300
    await addLiquidity(gmxContracts.daiToken, ethers.utils.parseEther("10000000")); // price = 1
    await addLiquidity(gmxContracts.btcToken, ethers.utils.parseUnits("167", 8));   // price = 60,000 & 8dp's
    await addLiquidity(gmxContracts.wrappedNativeToken, ethers.utils.parseEther("5000"));     // price = 200
}

// Arbitrum Mainnet RewardRouter Address
const gmxRewardRouterAddress = "0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1";
const glpRewardRouterAddress = "0xB95DB5B167D75e6d04227CfFFA61069348d271F5";
const stakedGlpAddress = "0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE";

async function impersonateAndFund(owner: Signer, address: string): Promise<Signer> {
    const signer = await impersonateSigner(address);
    await owner.sendTransaction({
        to: await signer.getAddress(),
        value: ethers.utils.parseEther("0.1")
    });
    return signer;
}

export async function connectToGmx(owner: Signer): Promise<GmxContracts> {
    const gmxRewardRouter = GMX_RewardRouterV2__factory.connect(gmxRewardRouterAddress, owner);
    const glpRewardRouter = GMX_RewardRouterV2__factory.connect(glpRewardRouterAddress, owner);
    const stakedGmxTracker = GMX_RewardTracker__factory.connect(await gmxRewardRouter.stakedGmxTracker(), owner);
    const bonusGmxTracker = GMX_RewardTracker__factory.connect(await gmxRewardRouter.bonusGmxTracker(), owner);
    const feeGmxTracker = GMX_RewardTracker__factory.connect(await gmxRewardRouter.feeGmxTracker(), owner);
    const feeGlpTracker = GMX_RewardTracker__factory.connect(await glpRewardRouter.feeGlpTracker(), owner);
    const stakedGlpTracker = GMX_RewardTracker__factory.connect(await glpRewardRouter.stakedGlpTracker(), owner);
    const stakedGlp = GMX_StakedGlp__factory.connect(stakedGlpAddress, owner);

    const wethToken = GMX_Token__factory.connect(await gmxRewardRouter.weth(), owner);
    const gmxToken = GMX_GMX__factory.connect(await gmxRewardRouter.gmx(), owner);
    const glpToken = GMX_GLP__factory.connect(await glpRewardRouter.glp(), owner);
    const esGmxToken = GMX_EsGMX__factory.connect(await gmxRewardRouter.esGmx(), owner);
    const multiplierPointsToken = GMX_MintableBaseToken__factory.connect(await gmxRewardRouter.bnGmx(), owner);

    // Update the gov of contracts to be 'owner', such that it can mint/etc.
    // A bit painful as we need to use the timelock to do it.
    const ownerAddr = await owner.getAddress();

    // Can set the gov of the reward router directly (no timelock)
    const gmxRewardRouterMsig = await impersonateAndFund(owner, await gmxRewardRouter.gov());
    await gmxRewardRouter.connect(gmxRewardRouterMsig).setGov(ownerAddr);

    // Timelock used for mainnet admin settings updates
    // 'Signal' -> wait x days -> 'Set'
    let timelock = GMX_Timelock__factory.connect(await stakedGmxTracker.gov(), owner);
    const timelockMsig = await impersonateSigner(await timelock.admin());
    await owner.sendTransaction({
        to: await timelockMsig.getAddress(),
        value: ethers.utils.parseEther("0.1")
    });

    timelock = timelock.connect(timelockMsig);
    
    const glpManager = GMX_GlpManager__factory.connect(await glpRewardRouter.glpManager(), owner);
    const vault = GMX_Vault__factory.connect(await glpManager.vault(), owner);
    const vaultPriceFeed = GMX_VaultPriceFeed__factory.connect(await vault.priceFeed(), owner);
    const secondaryPriceFeed = GMX_IFastPriceFeed__factory.connect(await vaultPriceFeed.secondaryPriceFeed(), owner);

    let secondaryPriceFeedTimelock = GMX_Timelock__factory.connect(await secondaryPriceFeed.gov(), owner);
    secondaryPriceFeedTimelock = secondaryPriceFeedTimelock.connect(timelockMsig);
    
    // GMX token has it's own timelock contract
    let gmxTokenTimelock = GMX_GmxTimelock__factory.connect(await gmxToken.gov(), owner);
    const gmxTokenTimelockMsig = await impersonateAndFund(owner, await gmxTokenTimelock.admin());
    gmxTokenTimelock = gmxTokenTimelock.connect(gmxTokenTimelockMsig);

    // Update the gov of everything to be owner
    {
        await timelock.signalSetGov(stakedGmxTracker.address, ownerAddr);
        await timelock.signalSetGov(stakedGlpTracker.address, ownerAddr);
        await timelock.signalSetGov(bonusGmxTracker.address, ownerAddr);
        await timelock.signalSetGov(feeGmxTracker.address, ownerAddr);
        await timelock.signalSetGov(feeGlpTracker.address, ownerAddr);
        await timelock.signalSetGov(esGmxToken.address, ownerAddr);
        await timelock.signalSetGov(multiplierPointsToken.address, ownerAddr);
        await secondaryPriceFeedTimelock.signalSetGov(secondaryPriceFeed.address, ownerAddr);
    }

    // The GMX Token is different - need to go through the TokenManager, and have 6 signers sign for it first.
    {
        const tokenManager = GMX_TokenManager__factory.connect(await gmxTokenTimelock.tokenManager(), owner);
        await tokenManager.connect(gmxRewardRouterMsig).signalSetGov(gmxTokenTimelock.address, gmxToken.address, ownerAddr);
        const tokenSigners = [
            "0x45e48668F090a3eD1C7961421c60Df4E66f693BD",
            "0xD7941C4Ca57a511F21853Bbc7FBF8149d5eCb398",
            "0x881690382102106b00a99E3dB86056D0fC71eee6",
            "0x2E5d207a4C0F7e7C52F6622DCC6EB44bC0fE1A13",
            "0x6091646D0354b03DD1e9697D33A7341d8C93a6F5",
            "0xd6D5a4070C7CFE0b42bE83934Cc21104AbeF1AD5",
        ]
        for (let idx=0; idx < tokenSigners.length; idx++) {
            const signer = await impersonateAndFund(owner, tokenSigners[idx]);
            await tokenManager.connect(signer).signSetGov(gmxTokenTimelock.address, gmxToken.address, ownerAddr, await tokenManager.actionsNonce());
        }
        await tokenManager.connect(gmxRewardRouterMsig).setGov(gmxTokenTimelock.address, gmxToken.address, ownerAddr, await tokenManager.actionsNonce());
    }

    // Can now wait for a period, and then set the gov
    let timelockWaitPeriod = await timelock.buffer();
    {
        
        await mineForwardSeconds(timelockWaitPeriod.add(1).toNumber());
        await timelock.setGov(stakedGmxTracker.address, ownerAddr);
        await timelock.setGov(stakedGlpTracker.address, ownerAddr);
        await timelock.setGov(bonusGmxTracker.address, ownerAddr);
        await timelock.setGov(feeGmxTracker.address, ownerAddr);
        await timelock.setGov(feeGlpTracker.address, ownerAddr);
        await timelock.setGov(esGmxToken.address, ownerAddr);
        await timelock.setGov(multiplierPointsToken.address, ownerAddr);
        await secondaryPriceFeedTimelock.setGov(secondaryPriceFeed.address, ownerAddr);
    }

    // Gotta wait more time for the gmx timelock
    {
        timelockWaitPeriod = (await gmxTokenTimelock.longBuffer()).sub(timelockWaitPeriod);
        await mineForwardSeconds(timelockWaitPeriod.add(1).toNumber());
        await gmxTokenTimelock.setGov(gmxToken.address, ownerAddr);
    }
    
    const stakedGmxDistributor = GMX_RewardDistributor__factory.connect(await stakedGmxTracker.distributor(), owner);
    const bonusGmxDistributor = GMX_BonusDistributor__factory.connect(await bonusGmxTracker.distributor(), owner);
    const feeGmxDistributor = GMX_RewardDistributor__factory.connect(await feeGmxTracker.distributor(), owner);
    const feeGlpDistributor = GMX_RewardDistributor__factory.connect(await feeGlpTracker.distributor(), owner);
    const stakedGlpDistributor = GMX_RewardDistributor__factory.connect(await stakedGlpTracker.distributor(), owner);

    // Arbit mainnet addresses
    const btc = GMX_Token__factory.connect("0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f", owner);  // Arbi WBTC
    const bnb = GMX_Token__factory.connect("0xf97f4df75117a78c1a5a0dbb814af92458539fb4", owner);  // Arbi LINK
    const dai = GMX_Token__factory.connect("0xda10009cbd5d07dd0cecc66161fc93d7c9000da1", owner);  // Arbi DAI

    const gmxVester = GMX_Vester__factory.connect(await gmxRewardRouter.gmxVester(), owner);
    const glpVester = GMX_Vester__factory.connect(await gmxRewardRouter.glpVester(), owner);

    // Phew - all done.
    return {
        gmxRewardRouter,
        glpRewardRouter,
        stakedGmxTracker,
        bonusGmxTracker,
        feeGmxTracker,
        stakedGlpTracker,
        feeGlpTracker,

        wrappedNativeToken: wethToken,
        gmxToken,
        glpToken,
        esGmxToken,
        multiplierPointsToken,
        timelock,

        stakedGmxDistributor,
        bonusGmxDistributor,
        feeGmxDistributor,
        feeGlpDistributor,
        stakedGlpDistributor,

        bnbToken: bnb,
        btcToken: btc,
        daiToken: dai,
        vault,
        stakedGlp,
        glpManager,

        gmxVester,
        glpVester,
    }
}
