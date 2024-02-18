import { ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish } from "ethers";
import { expect } from "chai";
import { 
    mineForwardSeconds,
    impersonateSigner, 
    ZERO_ADDRESS, 
    recoverToken, 
    shouldRevertNotGov,
    forkMainnet, 
    deployUupsProxy, 
    shouldRevertNotOperator, 
    expectApproxEqRelPred, 
    tolerance, 
    expectApproxEqRel,
    ZERO_SLIPPAGE,
    ZERO_DEADLINE,
    applySlippage
} from "../../helpers";
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory, 
    MintableToken, DummyMintableToken__factory,
    IOrigamiGmxManager,
} from "../../../typechain";
import { 
    addDefaultGlpLiquidity, connectToGmx, deployGmx, 
    GmxContracts, updateDistributionTime } from "./gmx-helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { GmxVaultType } from "../../../scripts/deploys/helpers";
import { getSigners } from "../../signers";

// 0.001% max relative delta for time based reward checks - ie from BigNumber order of operations -> rounding
const MAX_REL_DELTA = tolerance(0.001);
const MIN_USDG = 1;

describe("Origami GMX Manager", async () => {
    let owner: Signer;
    let feeCollector: Signer;
    let alan: Signer;
    let bob: Signer;
    let operator: Signer;
    let gov: Signer;
    let govAddr: string;

    let origamiGmxManager: OrigamiGmxManager;
    let origamiGlpManager: OrigamiGmxManager;
    let gmxEarnAccount: OrigamiGmxEarnAccount;
    let glpPrimaryEarnAccount: OrigamiGmxEarnAccount;
    let glpSecondaryEarnAccount: OrigamiGmxEarnAccount;
    let oGmxToken: MintableToken;
    let oGlpToken: MintableToken;

    let origamiGmxRewardsAggr: Signer;
    let origamiGlpRewardsAggr: Signer;

    let gmxContracts: GmxContracts;

    // GMX Reward rates
    const ethPerSecond = BigNumber.from("41335970000000"); // 0.00004133597 ETH per second
    const esGmxPerSecond = BigNumber.from("20667989410000000"); // 0.02066798941 esGmx per second
    const oneYear = 365 * 60 * 60 * 24;

    before( async () => {
        [owner, bob, alan, operator, feeCollector, origamiGmxRewardsAggr, origamiGlpRewardsAggr, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });

    describe("Local setup", async () => {

        async function setupOrigamiGmxManager() {
            gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

            oGmxToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "oGMX", "oGMX");
            oGlpToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "oGLP", "oGLP");

            // Setup the GMX Manager/Earn Account
            {
                gmxEarnAccount = await deployUupsProxy(
                    new OrigamiGmxEarnAccount__factory(gov), 
                    [gmxContracts.gmxRewardRouter.address],
                    govAddr,
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                    await gmxContracts.gmxRewardRouter.gmxVester(),
                    gmxContracts.stakedGlp.address,
                );
                origamiGmxManager = await new OrigamiGmxManager__factory(gov).deploy(
                    govAddr,
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                    oGmxToken.address,
                    oGlpToken.address,
                    feeCollector.getAddress(),
                    gmxEarnAccount.address,
                    ZERO_ADDRESS,
                );
                await gmxEarnAccount.addOperator(origamiGmxManager.address);
                await origamiGmxManager.addOperator(operator.getAddress());
                await oGmxToken.addMinter(origamiGmxManager.address);
            }

            // Setup the GLP Manager/Earn Account
            {
                glpPrimaryEarnAccount = await deployUupsProxy(
                    new OrigamiGmxEarnAccount__factory(gov), 
                    [gmxContracts.gmxRewardRouter.address],
                    govAddr,
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                    await gmxContracts.glpRewardRouter.glpVester(),
                    gmxContracts.stakedGlp.address,
                );
                glpSecondaryEarnAccount = await deployUupsProxy(
                    new OrigamiGmxEarnAccount__factory(gov), 
                    [gmxContracts.gmxRewardRouter.address],
                    govAddr,
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                    await gmxContracts.glpRewardRouter.glpVester(),
                    gmxContracts.stakedGlp.address,
                );
                origamiGlpManager = await new OrigamiGmxManager__factory(gov).deploy(
                    govAddr,
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                    oGmxToken.address,
                    oGlpToken.address,
                    feeCollector.getAddress(),
                    glpPrimaryEarnAccount.address,
                    glpSecondaryEarnAccount.address,
                );
                await glpPrimaryEarnAccount.addOperator(origamiGlpManager.address);
                await glpSecondaryEarnAccount.addOperator(origamiGlpManager.address);
                await origamiGlpManager.addOperator(operator.getAddress());
                await oGmxToken.addMinter(origamiGlpManager.address);
            }

            // Manual signers as the rewards aggregators
            await origamiGmxManager.setRewardsAggregators(origamiGmxRewardsAggr.getAddress(), origamiGlpRewardsAggr.getAddress());
            await origamiGlpManager.setRewardsAggregators(origamiGmxRewardsAggr.getAddress(), origamiGlpRewardsAggr.getAddress());

            // Allow gov to mint for staking purposes.
            await oGmxToken.addMinter(gov.getAddress());
            await oGlpToken.addMinter(gov.getAddress());

            return {
                gmxContracts,
                oGmxToken,
                oGlpToken,
                gmxEarnAccount,
                origamiGmxManager,
                glpPrimaryEarnAccount,
                glpSecondaryEarnAccount,
                origamiGlpManager
            };
        }

        beforeEach(async () => {
            ({
                gmxContracts,
                oGmxToken,
                oGlpToken,
                gmxEarnAccount,
                origamiGmxManager,
                glpPrimaryEarnAccount,
                glpSecondaryEarnAccount,
                origamiGlpManager
            } = await loadFixture(setupOrigamiGmxManager));
        });

        describe("Admin", async () => {
            it("Construction", async () => {           
                expect(await origamiGmxManager.glpManager()).eq(await gmxContracts.glpRewardRouter.glpManager());
                expect(await origamiGmxManager.gmxToken()).eq(gmxContracts.gmxToken.address);
                expect(await origamiGmxManager.glpToken()).eq(gmxContracts.glpToken.address);
                expect(await origamiGmxManager.wrappedNativeToken()).eq(gmxContracts.wrappedNativeToken.address);
                expect(await origamiGmxManager.oGmxToken()).eq(oGmxToken.address);
                expect(await origamiGmxManager.oGlpToken()).eq(oGlpToken.address);
                expect(await origamiGmxManager.gmxVault()).eq(gmxContracts.vault.address);

                expect(await origamiGmxManager.rewardTokensList()).deep.eq([gmxContracts.wrappedNativeToken.address, oGmxToken.address, oGlpToken.address]);
                expect(await origamiGmxManager.feeCollector()).eq(await feeCollector.getAddress());

                expect((await origamiGmxManager.oGmxRewardsFeeRate()).denominator).eq(100);
                expect((await origamiGmxManager.sellFeeRate()).denominator).eq(100);
                expect((await origamiGmxManager.esGmxVestingRate()).denominator).eq(100);

                expect(await origamiGmxManager.primaryEarnAccount()).eq(gmxEarnAccount.address);
                expect(await origamiGmxManager.secondaryEarnAccount()).eq(ZERO_ADDRESS);
                expect(await origamiGlpManager.primaryEarnAccount()).eq(glpPrimaryEarnAccount.address);
                expect(await origamiGlpManager.secondaryEarnAccount()).eq(glpSecondaryEarnAccount.address);
                expect(await origamiGmxManager.gmxRewardsAggregator()).eq(await origamiGmxRewardsAggr.getAddress());
                expect(await origamiGmxManager.glpRewardsAggregator()).eq(await origamiGlpRewardsAggr.getAddress());
            });

            it("admin", async () => {
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setOGmxRewardsFeeRate(0, 0));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setEsGmxVestingRate(0, 0));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setSellFeeRate(0, 0));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setFeeCollector(ZERO_ADDRESS));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setPrimaryEarnAccount(ZERO_ADDRESS));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setSecondaryEarnAccount(ZERO_ADDRESS));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).setRewardsAggregators(ZERO_ADDRESS, ZERO_ADDRESS));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).addOperator(await operator.getAddress()));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).removeOperator(await operator.getAddress()));
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(alan).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10));
                const paused = {
                    glpInvestmentsPaused: true,
                    gmxInvestmentsPaused: true,
                    glpExitsPaused: false,
                    gmxExitsPaused: false,
                };

                await expect(origamiGmxManager.connect(alan).setPaused(paused))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(await alan.getAddress());
                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(alan).setPauser(alan.getAddress(), true));

                await shouldRevertNotGov(origamiGmxManager, origamiGmxManager.connect(owner).initGmxContracts(
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                ));

                const investGmxQuote = await origamiGmxManager.investOGmxQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                const exitGmxQuote = await origamiGmxManager.exitOGmxQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).investOGmx(investGmxQuote.quoteData),
                    origamiGmxManager, alan
                );
                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).exitOGmx(exitGmxQuote.quoteData, ZERO_ADDRESS),
                    origamiGmxManager, alan
                );

                const investGlpQuote = await origamiGmxManager.investOGlpQuote(100, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                const exitGlpQuote = await origamiGmxManager.exitOGlpQuote(100, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).investOGlp(gmxContracts.bnbToken.address, investGlpQuote.quoteData),
                    origamiGmxManager, alan
                );
                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).exitOGlp(gmxContracts.bnbToken.address, exitGlpQuote.quoteData, ZERO_ADDRESS),
                    origamiGmxManager, alan
                );

                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).applyGmx(0),
                    origamiGmxManager, alan
                );
                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).harvestRewards(),
                    origamiGmxManager, alan
                );
                await shouldRevertNotOperator(
                    origamiGmxManager.connect(alan).harvestSecondaryRewards(),
                    origamiGmxManager, alan
                );

                // Happy Paths
                await origamiGmxManager.connect(gov).setOGmxRewardsFeeRate(100, 100);
                await origamiGmxManager.connect(gov).setEsGmxVestingRate(100, 100);
                await origamiGmxManager.connect(gov).setSellFeeRate(100, 100);
                await origamiGmxManager.connect(gov).setFeeCollector(feeCollector.getAddress());
                await origamiGmxManager.connect(gov).setPrimaryEarnAccount(gmxEarnAccount.address);
                await origamiGmxManager.connect(gov).setSecondaryEarnAccount(gmxEarnAccount.address);
                await origamiGmxManager.connect(gov).setRewardsAggregators(origamiGmxRewardsAggr.getAddress(), origamiGlpRewardsAggr.getAddress());
                await expect(origamiGmxManager.recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10))
                    .to.revertedWith("ERC20: transfer amount exceeds balance");

                await expect(origamiGmxManager.connect(operator).applyGmx(0))
                    .to.be.revertedWithCustomError(origamiGmxManager, "ExpectedNonZero");
                await origamiGmxManager.connect(operator).harvestRewards();
                await origamiGmxManager.connect(operator).harvestSecondaryRewards();
                    
                await expect(origamiGmxManager.connect(operator).investOGmx(investGmxQuote.quoteData))
                    .to.revertedWith("BaseToken: transfer amount exceeds balance");
                await expect(origamiGmxManager.connect(operator).exitOGmx(exitGmxQuote.quoteData, ZERO_ADDRESS))
                    .to.revertedWith("ERC20: transfer amount exceeds balance");
                await expect(origamiGmxManager.connect(operator).investOGlp(gmxContracts.bnbToken.address, investGlpQuote.quoteData))
                    .to.revertedWith("ERC20: transfer amount exceeds balance");
                await expect(origamiGmxManager.connect(operator).exitOGlp(gmxContracts.bnbToken.address, exitGlpQuote.quoteData, ZERO_ADDRESS))
                    .to.revertedWith("ERC20: transfer amount exceeds balance");
                await origamiGmxManager.connect(gov).removeOperator(operator.getAddress());

                await origamiGmxManager.setPauser(alan.getAddress(), true);
                await origamiGmxManager.connect(alan).setPaused(paused);
                await origamiGmxManager.connect(gov).initGmxContracts(
                    gmxContracts.gmxRewardRouter.address, 
                    gmxContracts.glpRewardRouter.address, 
                );
            });

            it("gov can set pauser", async () => {
                const paused: IOrigamiGmxManager.PausedStruct = {
                    glpInvestmentsPaused: true,
                    gmxInvestmentsPaused: true,
                    glpExitsPaused: true,
                    gmxExitsPaused: true,
                };

                await expect(origamiGmxManager.connect(alan).setPaused(paused))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(await alan.getAddress());

                await expect(origamiGmxManager.setPauser(alan.getAddress(), true))
                    .to.emit(origamiGmxManager, "PauserSet")
                    .withArgs(await alan.getAddress(), true);
                await origamiGmxManager.connect(alan).setPaused(paused);
                expect(await origamiGmxManager.connect(alan).pausers(alan.getAddress())).eq(true);

                await expect(origamiGmxManager.setPauser(alan.getAddress(), false))
                    .to.emit(origamiGmxManager, "PauserSet")
                    .withArgs(await alan.getAddress(), false);
                expect(await origamiGmxManager.connect(alan).pausers(alan.getAddress())).eq(false);

                await expect(origamiGmxManager.connect(alan).setPaused(paused))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(await alan.getAddress());
            });

            it("pause/unpause", async () => {
                await origamiGmxManager.setPauser(govAddr, true);
                await origamiGlpManager.setPauser(govAddr, true);

                const paused: IOrigamiGmxManager.PausedStruct = {
                    glpInvestmentsPaused: true,
                    gmxInvestmentsPaused: true,
                    glpExitsPaused: true,
                    gmxExitsPaused: true,
                };
                await expect(origamiGmxManager.setPaused(paused))
                    .to.emit(origamiGmxManager, "PausedSet")
                    .withArgs([true,true,true,true]);
                await expect(origamiGlpManager.setPaused(paused))
                    .to.emit(origamiGlpManager, "PausedSet")
                    .withArgs([true,true,true,true]);

                const checkPaused = (actual: IOrigamiGmxManager.PausedStructOutput, expected: IOrigamiGmxManager.PausedStruct) => {
                    expect(actual.glpInvestmentsPaused).eq(expected.glpInvestmentsPaused);
                    expect(actual.gmxInvestmentsPaused).eq(expected.gmxInvestmentsPaused);
                    expect(actual.glpExitsPaused).eq(expected.glpExitsPaused);
                    expect(actual.gmxExitsPaused).eq(expected.gmxExitsPaused);
                }
                checkPaused(await origamiGlpManager.paused(), paused);
                checkPaused(await origamiGmxManager.paused(), paused);

                const investGmxQuote = await origamiGmxManager.investOGmxQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                const exitGmxQuote = await origamiGmxManager.exitOGmxQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                const investGlpQuote = await origamiGmxManager.investOGlpQuote(100, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                const exitGlpQuote = await origamiGmxManager.exitOGlpQuote(100, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

                await expect(origamiGmxManager.connect(operator).investOGmx(investGmxQuote.quoteData))
                    .to.revertedWithCustomError(origamiGmxManager, "IsPaused");
                await expect(origamiGmxManager.connect(operator).exitOGmx(exitGmxQuote.quoteData, ZERO_ADDRESS))
                    .to.revertedWithCustomError(origamiGmxManager, "IsPaused");
                await expect(origamiGlpManager.connect(operator).investOGlp(gmxContracts.bnbToken.address, investGlpQuote.quoteData))
                    .to.revertedWithCustomError(origamiGmxManager, "IsPaused");
                await expect(origamiGlpManager.connect(operator).exitOGlp(gmxContracts.bnbToken.address, exitGlpQuote.quoteData, ZERO_ADDRESS))
                    .to.revertedWithCustomError(origamiGmxManager, "IsPaused");

                const unpaused: IOrigamiGmxManager.PausedStruct = {
                    glpInvestmentsPaused: false,
                    gmxInvestmentsPaused: false,
                    glpExitsPaused: false,
                    gmxExitsPaused: false,
                };
                await expect(origamiGmxManager.setPaused(unpaused))
                    .to.emit(origamiGmxManager, "PausedSet")
                    .withArgs([false,false,false,false]);
                await expect(origamiGlpManager.setPaused(unpaused))
                    .to.emit(origamiGlpManager, "PausedSet")
                    .withArgs([false,false,false,false]);
                checkPaused(await origamiGlpManager.paused(), unpaused);
                checkPaused(await origamiGmxManager.paused(), unpaused);

                await expect(origamiGmxManager.connect(operator).investOGmx(investGmxQuote.quoteData))
                    .to.revertedWith("BaseToken: transfer amount exceeds balance");
                await expect(origamiGmxManager.connect(operator).exitOGmx(exitGmxQuote.quoteData, ZERO_ADDRESS))
                    .to.revertedWith("RewardTracker: _amount exceeds stakedAmount");
                await expect(origamiGlpManager.connect(operator).investOGlp(gmxContracts.bnbToken.address, investGlpQuote.quoteData))
                    .to.revertedWith("ERC20: transfer amount exceeds balance");
                await expect(origamiGlpManager.connect(operator).exitOGlp(gmxContracts.bnbToken.address, exitGlpQuote.quoteData, ZERO_ADDRESS))
                    .to.revertedWith("RewardTracker: _amount exceeds stakedAmount");
            });

            it("should add operator", async() => {
                // addOperator() test covered by operators.ts
            });

            it("should remove operator", async() => {
                // removeOperator() test covered by operators.ts
            });

            it("Should setOGmxRewardsFeeRate()", async () => {
                await expect(origamiGmxManager.setOGmxRewardsFeeRate(80, 100))
                    .to.emit(origamiGmxManager, "OGmxRewardsFeeRateSet")
                    .withArgs(80, 100);
                const [numerator, denominator] = await origamiGmxManager.oGmxRewardsFeeRate();
                expect(numerator.toNumber()).to.eq(80);
                expect(denominator.toNumber()).to.eq(100);
            });

            it("Should setEsGmxVestingRate()", async () => {
                await expect(origamiGmxManager.setEsGmxVestingRate(80, 100))
                    .to.emit(origamiGmxManager, "EsGmxVestingRateSet")
                    .withArgs(80, 100);
                const [numerator, denominator] = await origamiGmxManager.esGmxVestingRate();
                expect(numerator.toNumber()).to.eq(80);
                expect(denominator.toNumber()).to.eq(100);
            });

            it("Should setSellFeeRate()", async () => {
                await expect(origamiGmxManager.setSellFeeRate(80, 100))
                    .to.emit(origamiGmxManager, "SellFeeRateSet")
                    .withArgs(80, 100);
                const [numerator, denominator] = await origamiGmxManager.sellFeeRate();
                expect(numerator.toNumber()).to.eq(80);
                expect(denominator.toNumber()).to.eq(100);
            });

            it("Should setFeeCollector()", async () => {
                await expect(origamiGmxManager.setFeeCollector(ZERO_ADDRESS))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(ZERO_ADDRESS);
                const feeCollectorAddr = await bob.getAddress();
                await expect(origamiGmxManager.setFeeCollector(feeCollectorAddr))
                    .to.emit(origamiGmxManager, "FeeCollectorSet")
                    .withArgs(feeCollectorAddr);
                expect(await origamiGmxManager.feeCollector()).eq(feeCollectorAddr);
            });

            it("Should setPrimaryEarnAccount()", async () => {
                await expect(origamiGmxManager.setPrimaryEarnAccount(ZERO_ADDRESS))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(ZERO_ADDRESS);
                await expect(origamiGmxManager.setPrimaryEarnAccount(gmxEarnAccount.address))
                    .to.emit(origamiGmxManager, "PrimaryEarnAccountSet")
                    .withArgs(gmxEarnAccount.address);
                expect(await origamiGmxManager.primaryEarnAccount()).eq(gmxEarnAccount.address);
            });

            it("Should setSecondaryEarnAccount()", async () => {
                await expect(origamiGmxManager.setSecondaryEarnAccount(ZERO_ADDRESS))
                    .to.not.be.reverted;
                await expect(origamiGmxManager.setSecondaryEarnAccount(gmxEarnAccount.address))
                    .to.emit(origamiGmxManager, "SecondaryEarnAccountSet")
                    .withArgs(gmxEarnAccount.address);
                expect(await origamiGmxManager.secondaryEarnAccount()).eq(gmxEarnAccount.address);
            });

            it("Should setRewardsAggregators()", async () => {
                await expect(origamiGmxManager.setRewardsAggregators(ZERO_ADDRESS, origamiGlpRewardsAggr.getAddress()))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(ZERO_ADDRESS);
                await expect(origamiGmxManager.setRewardsAggregators(origamiGmxRewardsAggr.getAddress(), ZERO_ADDRESS))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidAddress")
                    .withArgs(ZERO_ADDRESS);
                await expect(origamiGmxManager.setRewardsAggregators(origamiGmxRewardsAggr.getAddress(), origamiGlpRewardsAggr.getAddress()))
                    .to.emit(origamiGmxManager, "RewardsAggregatorsSet")
                    .withArgs(await origamiGmxRewardsAggr.getAddress(), await origamiGlpRewardsAggr.getAddress());
                expect(await origamiGmxManager.gmxRewardsAggregator()).eq(await origamiGmxRewardsAggr.getAddress());
                expect(await origamiGmxManager.glpRewardsAggregator()).eq(await origamiGlpRewardsAggr.getAddress());
            });

            it("gov can recover tokens", async () => {
                const amount = 50;
                await gmxContracts.bnbToken.mint(origamiGmxManager.address, amount);
                await recoverToken(gmxContracts.bnbToken, amount, origamiGmxManager, owner);   
            });

        });

        describe("applyGmx", async () => {
            it("should applyGmx() by staking", async () => {
                await expect(origamiGmxManager.connect(operator).applyGmx(0))
                    .to.be.revertedWithCustomError(origamiGmxManager, "ExpectedNonZero");

                // No tokens
                const amount = ethers.utils.parseEther("250");
                await expect(origamiGmxManager.connect(operator).applyGmx(amount))
                    .to.be.revertedWith("BaseToken: transfer amount exceeds balance");
                
                // Applying the GMX stakes the GMX in the gmxEarnAccount
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await expect(origamiGmxManager.connect(operator).applyGmx(amount))
                    .to.emit(gmxContracts.gmxRewardRouter, "StakeGmx")
                    .withArgs(gmxEarnAccount.address, gmxContracts.gmxToken.address, amount);

                // The origamiGmxManager and gmxEarnAccount doesn't have the GMX
                expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
                expect(await gmxContracts.gmxToken.balanceOf(gmxEarnAccount.address)).eq(0);
                
                // The earn account has the staked GMX
                expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(amount);
            });
        });

        describe("Rewards", async () => {
            it("harvestableRewards", async () => {
                // Nothing staked -> nothing earnt
                let rewardRatesGlp = await origamiGmxManager.harvestableRewards(GmxVaultType.GLP);
                let rewardRatesGmx = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                expect(rewardRatesGlp).deep.eq([0, 0, 0]);
                expect(rewardRatesGmx).deep.eq([0, 0, 0]);

                // Origami applies some GMX, it has 100% so gets the full reward rate
                const amount = ethers.utils.parseEther("250");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);

                // Origami gets 100% of the rewards for the day
                await mineForwardSeconds(86400);
                rewardRatesGlp = await origamiGmxManager.harvestableRewards(GmxVaultType.GLP);
                rewardRatesGmx = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                expect(rewardRatesGlp).deep.eq([0, 0, 0]);
                expect(rewardRatesGmx).deep.eq([ethPerSecond.mul(86400), esGmxPerSecond.mul(86400), 0]);

                // With fees - get 70% (2 extra seconds from these two mine's)
                await origamiGmxManager.setOGmxRewardsFeeRate(30, 100);
                rewardRatesGlp = await origamiGmxManager.harvestableRewards(GmxVaultType.GLP);
                rewardRatesGmx = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                expect(rewardRatesGlp).deep.eq([0, 0, 0]);
                expect(rewardRatesGmx).deep.eq([
                    ethPerSecond.mul(86401),
                    esGmxPerSecond.mul(86401).mul(70).div(100),
                    0,
                ]);
            });
        
            it("harvestRewards - GMX - no vesting", async () => {
                // Nothing staked -> nothing earnt
                await expect(origamiGmxManager.connect(operator).harvestRewards())
                    .to.emit(gmxEarnAccount, "RewardsHarvested")
                    .withArgs(0, 0, 0, 0, 0, 0);
                
                // Origami applies some GMX, it has 100% so gets the full reward rate
                const amount = ethers.utils.parseEther("250");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await updateDistributionTime(gmxContracts);
                await origamiGmxManager.connect(operator).applyGmx(amount);

                // No fees
                let expectedEsGmx;
                let expectedEth;
                let oGmxFees;
                let oGmxRewards;
                let ethFees;
                let ethRewards;
                {
                    // Origami gets 100% of the rewards for the day, and matches harvestableRewards()
                    await mineForwardSeconds(86400);
                    let rewardRates = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                    expectedEth = ethPerSecond.mul(86401);
                    expectedEsGmx = esGmxPerSecond.mul(86401);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), 0, // ETH from GMX, 0 from GLP
                            expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA), 0,  // oGMX, 0 from GLP
                            0,  // GMX vested
                            0,  // esGMX deposited into vesting
                        );

                    // The harvestableRewards also match this amount
                    expectApproxEqRel(ethPerSecond.mul(86400), rewardRates[0], MAX_REL_DELTA);
                    expectApproxEqRel(esGmxPerSecond.mul(86400), rewardRates[1], MAX_REL_DELTA);
                    expect(rewardRates[2]).eq(0);

                    // The oGMX gets minted
                    oGmxFees = await oGmxToken.balanceOf(feeCollector.getAddress());
                    oGmxRewards = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxFees).eq(0);
                    expect(oGmxRewards).gte(expectedEsGmx);

                    // The ETH/AVAX gets transferred
                    ethFees = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    ethRewards = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethFees).eq(0);
                    expect(ethRewards).gte(expectedEth);
                }

                // With fees
                {
                    await origamiGmxManager.setOGmxRewardsFeeRate(30, 100);

                    // Origami gets 100% of the rewards for the day, and matches harvestableRewards()
                    await mineForwardSeconds(86400);
                    let rewardRates = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);

                    // The expected bonus is based off the new total esGMX held
                    expectedEth = ethPerSecond.mul(86402);
                    expectedEsGmx = esGmxPerSecond.mul(86402);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), 0, // ETH from GMX, 0 from GLP
                            expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA), 0,  // oGMX, 0 from GLP
                            0, // GMX vested
                            0, // esGMX deposited into vesting
                        );

                    // The harvestableRewards also match this amount
                    expectApproxEqRel(ethPerSecond.mul(86401), rewardRates[0], MAX_REL_DELTA);
                    expectApproxEqRel(esGmxPerSecond.mul(86401).mul(70).div(100), rewardRates[1], MAX_REL_DELTA);
                    expect(rewardRates[2]).eq(0);

                    // The oGMX gets minted
                    const oGmxFees2 = await oGmxToken.balanceOf(feeCollector.getAddress());
                    const oGmxRewards2 = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxRewards2).gte(oGmxRewards.add(expectedEsGmx.mul(70).div(100)));
                    expect(oGmxFees2).gte(oGmxFees.add(expectedEsGmx.mul(30).div(100)).sub(1)); // slight rounding diff

                    // The ETH/AVAX gets transferred
                    const ethFees2 = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    const ethRewards2 = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethRewards2).gte(ethRewards.add(expectedEth.mul(90).div(100)).sub(1)); // slight rounding diff
                    expect(ethFees2).gte(ethFees);
                }
            });

            it("harvestRewards - GMX - no vesting - 100% fees", async () => {
                // Nothing staked -> nothing earnt
                await expect(origamiGmxManager.connect(operator).harvestRewards())
                    .to.emit(gmxEarnAccount, "RewardsHarvested")
                    .withArgs(0, 0, 0, 0, 0, 0);
                
                await origamiGmxManager.setOGmxRewardsFeeRate(100, 100);

                // Origami applies some GMX, it has 100% so gets the full reward rate
                const amount = ethers.utils.parseEther("250");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await updateDistributionTime(gmxContracts);
                await origamiGmxManager.connect(operator).applyGmx(amount);

                {
                    await mineForwardSeconds(86400);
                    const harvestableRewards = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                    const expectedEth = ethPerSecond.mul(86401);
                    const expectedEsGmx = esGmxPerSecond.mul(86401);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), 0, // ETH for GMX, 0 for GLP
                            expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA), 0,  // oGMX for GMX, 0 for GLP
                            0, // GMX vested
                            0, // esGMX deposited into vesting
                        );

                    // The harvestableRewards are 100% fees - so nothing here
                    expect(harvestableRewards).deep.eq([ethPerSecond.mul(86400), 0, 0]);

                    // The oGMX gets minted
                    const oGmxFees = await oGmxToken.balanceOf(feeCollector.getAddress());
                    const oGmxRewards = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxFees).gte(expectedEsGmx);
                    expect(oGmxRewards).eq(0);

                    // The ETH/AVAX gets transferred
                    const ethFees = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    const ethRewards = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethFees).eq(0);
                    expect(ethRewards).gte(expectedEth);
                }
            });

            it("harvestRewards - GMX - with vesting", async () => {
                await origamiGmxManager.setEsGmxVestingRate(30, 100);
                            
                // Origami applies some GMX, it has 100% so gets the full reward rate
                const amount = ethers.utils.parseEther("250");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await updateDistributionTime(gmxContracts);
                await origamiGmxManager.connect(operator).applyGmx(amount);

                // First time
                let expectedEsGmx;
                let expectedEth;
                let oGmxFees;
                let oGmxRewards;
                let ethFees;
                let ethRewards;
                {
                    // Origami gets 100% of the rewards for the day, and matches harvestableRewards()
                    await mineForwardSeconds(86400);
                    let rewardRates = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                    expectedEth = ethPerSecond.mul(86401);
                    expectedEsGmx = esGmxPerSecond.mul(86401);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), 0, // ETH for GMX, 0 for GLP
                            expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA), 0,  // oGMX for GMX, 0 for GLP
                            0,  // GMX vested
                            expectApproxEqRelPred(expectedEsGmx.mul(30).div(100), MAX_REL_DELTA), // esGMX deposited into vesting
                        );

                    // The harvestableRewards also match this amount
                    expectApproxEqRel(ethPerSecond.mul(86400), rewardRates[0], MAX_REL_DELTA);
                    expectApproxEqRel(esGmxPerSecond.mul(86400), rewardRates[1], MAX_REL_DELTA);
                    expect(rewardRates[2]).eq(0);

                    // The oGMX gets minted
                    oGmxFees = await oGmxToken.balanceOf(feeCollector.getAddress());
                    oGmxRewards = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxFees).eq(0);
                    expect(oGmxRewards).gte(expectedEsGmx);

                    // The ETH/AVAX gets transferred
                    ethFees = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    ethRewards = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethFees).eq(0);
                    expect(ethRewards).gte(expectedEth);
                }

                // Second time - now the vested GMX is ready to be applied too
                {
                    // Origami gets 100% of the rewards for the day, and matches harvestableRewards()
                    await mineForwardSeconds(86400);
                    let rewardRates = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);

                    expectedEth = ethPerSecond.mul(86401);
                    expectedEsGmx = esGmxPerSecond.mul(86401);
                    const expectedVestedGmx = expectedEsGmx.mul(30).div(100).mul(86401).div(oneYear);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), 0, // ETH for GMX, 0 for GLP
                            expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA), 0,  // oGMX for GMX, 0 for GLP
                            expectApproxEqRelPred(expectedVestedGmx, MAX_REL_DELTA),  // GMX vested
                            expectApproxEqRelPred(expectedEsGmx.mul(30).div(100), MAX_REL_DELTA), // esGMX deposited into vesting
                        );

                    // The harvestableRewards also match this amount
                    expectApproxEqRel(ethPerSecond.mul(86400), rewardRates[0], MAX_REL_DELTA);
                    expectApproxEqRel(esGmxPerSecond.mul(86400), rewardRates[1], MAX_REL_DELTA);
                    expect(rewardRates[2]).eq(0);

                    // The oGMX gets minted
                    const oGmxFees2 = await oGmxToken.balanceOf(feeCollector.getAddress());
                    const oGmxRewards2 = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxRewards2).gte(oGmxRewards.add(expectedEsGmx).sub(1)); // Slight rounding diff
                    expect(oGmxFees2).eq(0);

                    // The ETH/AVAX gets transferred
                    const ethFees2 = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    const ethRewards2 = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethRewards2).gte(ethRewards.add(expectedEth).sub(1)); // Slight rounding diff
                    expect(ethFees2).eq(0);

                    // The earn account has now staked more vested GMX
                    expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).gte(amount.add(expectedVestedGmx));
                }
            });

            it("harvestRewards - GLP", async () => {
                const tokenAddr = gmxContracts.bnbToken.address;

                // Mint and buy some GLP straight into the earn account
                const amount = ethers.utils.parseEther("100");
                await gmxContracts.bnbToken.mint(gmxEarnAccount.address, amount);
                const quote = await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await gmxEarnAccount.addOperator(operator.getAddress());
                await updateDistributionTime(gmxContracts);
                await gmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.quoteData.minInvestmentAmount);
                
                // No fees
                let expectedEsGmx;
                let expectedEth;
                let oGmxFees;
                let oGmxRewardsGlp;
                let oGmxRewardsGmx;
                let ethFees;
                let ethRewardsGlp;
                let ethRewardsGmx;
                {
                    // Origami gets 100% of the rewards for the day, and matches harvestableRewards()
                    await mineForwardSeconds(86400);
                    let rewardRatesGlp = await origamiGmxManager.harvestableRewards(GmxVaultType.GLP);
                    let rewardRatesGmx = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);
                    expectedEth = ethPerSecond.mul(86401);
                    expectedEsGmx = esGmxPerSecond.mul(86401);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            0, expectApproxEqRelPred(expectedEth, MAX_REL_DELTA),  // ETH only from GLP
                            0, expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA),  // oGMX only from GLP
                            0,  // esGMX vesting
                            0   // vested GMX
                        );

                    // The harvestableRewards also match this amount
                    expectApproxEqRel(rewardRatesGlp[0], ethPerSecond.mul(86400), MAX_REL_DELTA);
                    expectApproxEqRel(rewardRatesGlp[1], esGmxPerSecond.mul(86400), MAX_REL_DELTA);
                    expect(rewardRatesGlp[2]).eq(0);
                    expect(rewardRatesGmx).deep.eq([0, 0, 0]); // No GMX rewards as no staked esGMX yet.

                    // The oGMX gets minted
                    oGmxFees = await oGmxToken.balanceOf(feeCollector.getAddress());
                    oGmxRewardsGlp = await oGmxToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    oGmxRewardsGmx = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxFees).eq(0);
                    expect(oGmxRewardsGlp).gte(expectedEsGmx.sub(1)); // Rounding
                    expect(oGmxRewardsGmx).eq(0);

                    // The ETH/AVAX gets transferred
                    ethFees = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    ethRewardsGlp = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    ethRewardsGmx = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethFees).eq(0);
                    expect(ethRewardsGlp).gte(expectedEth.sub(1)); // Rounding
                    expect(ethRewardsGmx).eq(0);
                }

                // And again - now has earnt a small amount of mult points from the staked esGMX
                // but also 2x the eth/esgmx rewards, only because the GMX & GLP reward pools are separate
                // but Origami has 100% of both.
                {
                    await mineForwardSeconds(86400);
                    let rewardRatesGlp = await origamiGmxManager.harvestableRewards(GmxVaultType.GLP);
                    let rewardRatesGmx = await origamiGmxManager.harvestableRewards(GmxVaultType.GMX);

                    expectedEth = ethPerSecond.mul(86401);
                    expectedEsGmx = esGmxPerSecond.mul(86401);
                    await expect(origamiGmxManager.connect(operator).harvestRewards())
                        .to.emit(gmxEarnAccount, "RewardsHarvested")
                        .withArgs(
                            expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), expectApproxEqRelPred(expectedEth, MAX_REL_DELTA), // ETH
                            expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA), expectApproxEqRelPred(expectedEsGmx, MAX_REL_DELTA),  // oGMX
                            0,  // esGMX vested
                            0   // vested GMX
                        );

                    // The harvestableRewards also match this amount - now in both GLP (original deposit) and also the esGMX rewards side
                    expectApproxEqRel(rewardRatesGlp[0], ethPerSecond.mul(86400), MAX_REL_DELTA);
                    expectApproxEqRel(rewardRatesGlp[1], esGmxPerSecond.mul(86400), MAX_REL_DELTA);
                    expect(rewardRatesGlp[2]).eq(0);
                    expectApproxEqRel(rewardRatesGmx[0], ethPerSecond.mul(86400), MAX_REL_DELTA);
                    expectApproxEqRel(rewardRatesGmx[1], esGmxPerSecond.mul(86400), MAX_REL_DELTA);
                    expect(rewardRatesGmx[2]).eq(0);

                    // The oGMX gets minted
                    const oGmxFees2 = await oGmxToken.balanceOf(feeCollector.getAddress());
                    const oGmxRewards2Glp = await oGmxToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    const oGmxRewards2Gmx = await oGmxToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(oGmxRewards2Glp).gte(oGmxRewardsGlp.add(expectedEsGmx).sub(1)); // Rounding
                    expect(oGmxRewards2Gmx).gte(oGmxRewardsGmx.add(expectedEsGmx).sub(1)); // Rounding
                    expect(oGmxFees2).eq(0);

                    // The ETH/AVAX gets transferred
                    const ethFees2 = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    const ethRewards2Glp = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    const ethRewards2Gmx = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsAggr.getAddress());
                    expect(ethRewards2Glp).gte(ethRewardsGlp.add(expectedEth).sub(1)); // Rounding
                    expect(ethRewards2Gmx).gte(ethRewardsGmx.add(expectedEth).sub(1)); // Rounding
                    expect(ethFees2).gte(0);
                }
            });

            it("harvestRewards - GLP - no vesting - 100% fees", async () => {
                await origamiGlpManager.setOGmxRewardsFeeRate(100, 100);

                const tokenAddr = gmxContracts.bnbToken.address;

                // Mint and buy some GLP straight into the earn account
                const amount = ethers.utils.parseEther("100");
                await gmxContracts.bnbToken.mint(glpPrimaryEarnAccount.address, amount);
                const quote = await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await glpPrimaryEarnAccount.addOperator(operator.getAddress());
                await updateDistributionTime(gmxContracts);
                await glpPrimaryEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.quoteData.minInvestmentAmount);

                {
                    await mineForwardSeconds(86400);
                    let harvestableRewardsGlp = await origamiGlpManager.harvestableRewards(GmxVaultType.GLP);
                    const expectedEth = ethPerSecond.mul(86400);
                    const expectedEsGmx = esGmxPerSecond.mul(86400);
                    await origamiGlpManager.connect(operator).harvestRewards();

                    // The harvestableRewards are 100% fees - so nothing here
                    expect(harvestableRewardsGlp).deep.eq([expectedEth.sub(1), 0, 0]);

                    // The oGMX gets minted
                    const oGmxFees = await oGmxToken.balanceOf(feeCollector.getAddress());
                    const oGmxRewards = await oGmxToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    expect(oGmxFees).gte(expectedEsGmx);
                    expect(oGmxRewards).eq(0);

                    // The ETH/AVAX gets transferred
                    const ethFees = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    const ethRewards = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    expect(ethFees).eq(0);
                    expectApproxEqRel(ethRewards, ethPerSecond.mul(86401), MAX_REL_DELTA);
                }
            });

            it("harvestSecondaryRewards - GLP - 50% fees", async () => {
                await origamiGlpManager.setOGmxRewardsFeeRate(50, 100);

                const tokenAddr = gmxContracts.bnbToken.address;

                // Mint and buy some GLP straight into the secondary earn account
                {
                    const amount = ethers.utils.parseEther("100");
                    await gmxContracts.bnbToken.mint(glpSecondaryEarnAccount.address, amount);
                    const quote = await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                    await glpSecondaryEarnAccount.addOperator(operator.getAddress());
                    await updateDistributionTime(gmxContracts);
                    await glpSecondaryEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.quoteData.minInvestmentAmount);
                }

                {
                    await mineForwardSeconds(86400);
                    let rewardRatesGlp = await origamiGlpManager.harvestableSecondaryRewards(GmxVaultType.GLP);
                    const expectedEth = ethPerSecond.mul(86400);
                    await origamiGlpManager.connect(operator).harvestSecondaryRewards();

                    // Only expeect ETH rewards, no oGMX rewards.
                    expectApproxEqRel(rewardRatesGlp[0], expectedEth, MAX_REL_DELTA);
                    expect(rewardRatesGlp[1]).eq(0);
                    expect(rewardRatesGlp[2]).eq(0);

                    // No oGMX is minted
                    const oGmxFees = await oGmxToken.balanceOf(feeCollector.getAddress());
                    const oGmxRewards = await oGmxToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    expect(oGmxFees).eq(0);
                    expect(oGmxRewards).eq(0);

                    // The ETH/AVAX gets transferred - 50% split
                    const ethFees = await gmxContracts.wrappedNativeToken.balanceOf(feeCollector.getAddress());
                    const ethRewards = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsAggr.getAddress());
                    expect(ethFees).eq(0);
                    expectApproxEqRel(ethRewards, ethPerSecond.mul(86401), MAX_REL_DELTA);
                }
            });

            it("Should get projectedRewardRates()", async () => {
                // The native token (ETH) and the esGmx amount that Origami is eligable for, minus fees

                // Origami has nothing staked -> 0
                let rewardRatesGlp = await origamiGmxManager.projectedRewardRates(GmxVaultType.GLP);
                let rewardRatesGmx = await origamiGmxManager.projectedRewardRates(GmxVaultType.GMX);
                expect(rewardRatesGlp).deep.eq([0, 0, 0]);
                expect(rewardRatesGmx).deep.eq([0, 0, 0]);

                // Origami applies some GMX, it has 100% so gets the full reward rate
                const amount = ethers.utils.parseEther("250");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);

                // No fees - get 100% (may get diluted by other non-Origami gmx's)
                rewardRatesGlp = await origamiGmxManager.projectedRewardRates(GmxVaultType.GLP);
                rewardRatesGmx = await origamiGmxManager.projectedRewardRates(GmxVaultType.GMX);
                expect(rewardRatesGlp).deep.eq([0, 0, 0]);
                expect(rewardRatesGmx).deep.eq([ethPerSecond, esGmxPerSecond, 0]);

                // With fees - get 70%
                await origamiGmxManager.setOGmxRewardsFeeRate(30, 100);
                rewardRatesGlp = await origamiGmxManager.projectedRewardRates(GmxVaultType.GLP);
                rewardRatesGmx = await origamiGmxManager.projectedRewardRates(GmxVaultType.GMX);
                expect(rewardRatesGlp).deep.eq([0, 0, 0]);
                expect(rewardRatesGmx).deep.eq([
                    ethPerSecond,
                    esGmxPerSecond.mul(70).div(100),
                    0,
                ]);
            });
        });

        describe("GLP Quotes - dummy vault", async () => {
            const basisPointsDivisor = 10000;

            async function checkBuyQuote(
                amount: BigNumber, price: BigNumberish, expectedFee: number
            ) {
                const expectedUsdg = amount.mul(price).mul((basisPointsDivisor-expectedFee)).div(basisPointsDivisor);
        
                // GLP the same as USDG since it hasn't appreciated (ie glpSupply == aumInUsdg)
                const expectedGlp = expectedUsdg;
                const glpResults = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, 100, ZERO_DEADLINE);
                expect(glpResults.investFeeBps).deep.eq([expectedFee]);
                expect(glpResults.quoteData.expectedInvestmentAmount).eq(expectedGlp);
                expect(glpResults.quoteData.minInvestmentAmount).eq(applySlippage(expectedGlp, 100));
                return glpResults;
            }
        
            async function checkSellQuote(
                amount: BigNumber, price: BigNumberish, expectedFee: number
            ) {
                const redemptionAmount = amount.div(price);
                const expectedUsdg = redemptionAmount.mul(basisPointsDivisor-expectedFee).div(basisPointsDivisor);
                const expectedGlp = expectedUsdg;

                // GLP the same as USDG since it hasn't appreciated (ie glpSupply == aumInUsdg)
                const glpResults = await origamiGmxManager.exitOGlpQuote(amount, gmxContracts.bnbToken.address, 100, ZERO_DEADLINE);

                // Nothing to sell if there's no supply yet
                if ((await gmxContracts.glpToken.totalSupply()).eq(0)) {
                    expect(glpResults.exitFeeBps).deep.eq([0, 0]);
                    expect(glpResults.quoteData.expectedToTokenAmount).eq(0);
                    expect(glpResults.quoteData.minToTokenAmount).eq(0);
                } else {
                    expect(glpResults.exitFeeBps).deep.eq([0, expectedFee]);
                    expect(glpResults.quoteData.expectedToTokenAmount).eq(expectedGlp);
                    expect(glpResults.quoteData.minToTokenAmount).eq(applySlippage(expectedGlp, 100));
                }
        
                return glpResults;
            }

            it("Should get accepted tokens", async () => {
                const tokens = await origamiGmxManager.acceptedGlpTokens();
                expect(tokens).deep.eq(
                    [
                        gmxContracts.daiToken.address,
                        gmxContracts.btcToken.address,
                        gmxContracts.wrappedNativeToken.address,
                        gmxContracts.bnbToken.address,
                        ZERO_ADDRESS, 
                        gmxContracts.stakedGlp.address,
                    ]
                );
            });

            it("Buy Glp Quote - non-accepted token", async () => {
                const randomAddress = ethers.Wallet.createRandom().address;
                await addDefaultGlpLiquidity(bob, gmxContracts);
                await expect(origamiGmxManager.investOGlpQuote(BigNumber.from(100), randomAddress, ZERO_SLIPPAGE, ZERO_DEADLINE))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidToken")
                    .withArgs(randomAddress);
                await expect(origamiGmxManager.exitOGlpQuote(BigNumber.from(100), randomAddress, ZERO_SLIPPAGE, ZERO_DEADLINE))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidToken")
                    .withArgs(randomAddress);
            });

            it("Buy Glp Quote - empty GMX vault", async () => {
                const price = 300;
                await expect(checkBuyQuote(BigNumber.from(0), price, 0))
                    .to.revertedWithCustomError(origamiGmxManager, "ExpectedNonZero");
                
                const amount = ethers.utils.parseEther("30");
                const expectedFee = 25;
                await checkBuyQuote(amount, price, expectedFee);
            });

            it("Buy Glp Quote - some volume in GMX vault", async () => {
                await addDefaultGlpLiquidity(bob, gmxContracts);
                
                const price = 300;
                await expect(checkBuyQuote(BigNumber.from(0), price, 0))
                    .to.revertedWithCustomError(origamiGmxManager, "ExpectedNonZero");

                const amount = ethers.utils.parseEther("30000");
                const expectedFee = 56; // Algorithm for dynamic fees in GMX_VaultUtils::getFeeBasisPoints()
                await checkBuyQuote(amount, price, expectedFee);
            });

            it("Buy Glp Quote - fixed fees", async () => {
                // Setup the fees in the glp vault to be non-dynamic
                await gmxContracts.vault.setFees(
                    50, // _taxBasisPoints
                    10, // _stableTaxBasisPoints
                    25, // _mintBurnFeeBasisPoints
                    30, // _swapFeeBasisPoints
                    4, // _stableSwapFeeBasisPoints
                    10, // _marginFeeBasisPoints
                    ethers.utils.parseUnits("5", 30), // _liquidationFeeUsd
                    0, // _minProfitTime
                    false // _hasDynamicFees
                );
                await addDefaultGlpLiquidity(bob, gmxContracts);
                
                const price = 300;
                const amount = ethers.utils.parseEther("30000");
                const expectedFee = 25; // The fixed 25bps
                await checkBuyQuote(amount, price, expectedFee);
            });

            it("Buy Glp Quote - large volume", async () => {
                await addDefaultGlpLiquidity(bob, gmxContracts);
                
                const price = 300;
                const amount = ethers.utils.parseEther("300000");
                const expectedFee = 75; // Max fees - 25 + 50
                await checkBuyQuote(amount, price, expectedFee);
            });

            it("Sell Glp Quote - empty GMX vault", async () => {           
                const price = 300;
                const amount = ethers.utils.parseEther("30");
                const expectedFee = 25;
                await checkSellQuote(amount, price, expectedFee);
            });

            it("Sell Glp Quote - some volume in GMX vault", async () => {
                await addDefaultGlpLiquidity(bob, gmxContracts);
                
                const price = 300;                
                const amount = ethers.utils.parseEther("30000");
                const expectedFee = 15; // Algorithm for dynamic fees in GMX_VaultUtils::getFeeBasisPoints()
                await checkSellQuote(amount, price, expectedFee);
            });
        });
    });

    describe.skip("GLP Quotes - forked Arbi Mainnet (SLOW!!)", async () => {
        before(async () => {
            forkMainnet(47930000, process.env.ARBITRUM_RPC_URL);
            gmxContracts = await connectToGmx(owner);

            oGmxToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "oGMX", "oGMX");
            oGlpToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "oGLP", "oGLP");

            const gmxEarnAccount = await deployUupsProxy(
                new OrigamiGmxEarnAccount__factory(gov), 
                [gmxContracts.gmxRewardRouter.address],
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                await gmxContracts.glpRewardRouter.gmxVester(),
                gmxContracts.stakedGlp.address,
            );

            origamiGmxManager = await new OrigamiGmxManager__factory(gov).deploy(
                govAddr, 
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                oGmxToken.address,
                oGlpToken.address,
                feeCollector.getAddress(),
                gmxEarnAccount.address,
                ZERO_ADDRESS,
            );
        });

        it("Buy/Sell GLP Quotes should match actual buy and sell amounts", async () => {           
            const amount = ethers.utils.parseEther("30000");
            const glpManagerAddr = await gmxContracts.glpRewardRouter.glpManager();

            // Transfer some LINK (used as a proxy to BNB) to Bob
            // and approve the spend
            const largeLinkHolder = await impersonateSigner("0x1714400FF23dB4aF24F9fd64e7039e6597f18C2b");
            await gov.sendTransaction({
                to: await largeLinkHolder.getAddress(),
                value: ethers.utils.parseEther("0.5")
            });
            await gmxContracts.bnbToken.connect(largeLinkHolder).transfer(bob.getAddress(), amount);
            await gmxContracts.bnbToken.connect(bob).approve(glpManagerAddr, amount);
            expect(await gmxContracts.bnbToken.balanceOf(bob.getAddress())).eq(amount);

            // Get a quote to buy GLP
            const buyQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

            // Now actually perform a buy using the real contracts and use the 
            // quote amounts as the min amounts.
            // We should receive that exact amount back.
            await expect(gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                gmxContracts.bnbToken.address, amount, MIN_USDG, buyQuote.quoteData.minInvestmentAmount
            )).emit(gmxContracts.glpRewardRouter, "StakeGlp").withArgs(await bob.getAddress(), buyQuote.quoteData.expectedInvestmentAmount);

            // Alan has a staked GLP balance
            const stakedGlpBal = await gmxContracts.stakedGlpTracker.balanceOf(bob.getAddress());
            expect(stakedGlpBal).eq(buyQuote.quoteData.expectedInvestmentAmount);

            // Wait until after the GMX cooldown
            await mineForwardSeconds(15*60);

            // Now get a quote to sell
            const sellQuote = await origamiGmxManager.exitOGlpQuote(stakedGlpBal, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await gmxContracts.glpToken.connect(bob).approve(glpManagerAddr, amount);

            // And perform the sell using the quote as the min amounts.
            await expect(gmxContracts.glpRewardRouter.connect(bob).unstakeAndRedeemGlp(
                gmxContracts.bnbToken.address, stakedGlpBal, sellQuote.quoteData.minToTokenAmount, bob.getAddress(),
            )).emit(gmxContracts.glpRewardRouter, "UnstakeGlp").withArgs(await bob.getAddress(), stakedGlpBal);

            // Alan receives the correct BNB back, matching the quote
            expect(await gmxContracts.bnbToken.balanceOf(bob.getAddress())).eq(sellQuote.quoteData.expectedToTokenAmount);
        });
    });
});
