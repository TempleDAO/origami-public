import { ethers, upgrades } from "hardhat";
import { Signer, BigNumber, BigNumberish, ContractTransaction } from "ethers";
import { expect } from "chai";
import { 
    blockTimestamp,
    BN_ZERO,
    deployUupsProxy,
    expectApproxEqRel,
    mineForwardSeconds, 
    setExplicitAccess, 
    shouldRevertInvalidAccess, 
    tolerance, 
    upgradeUupsProxy, 
    upgradeUupsProxyAndCall, 
    ZERO_ADDRESS,
    ZERO_DEADLINE,
    ZERO_SLIPPAGE, 
} from "../../helpers";
import { 
    IGmxVester, IGmxVester__factory, GMX_Vester__factory,
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory, 
    OrigamiGmxManager, OrigamiGmxManager__factory,
    DummyOrigamiGmxEarnAccount__factory,
} from "../../../../typechain";
import { GmxContracts, deployGmx, updateDistributionTime } from "./gmx-helpers";
import { Result } from "ethers/lib/utils";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { GmxVaultType } from "../../../../scripts/deploys/helpers";
import { getSigners } from "../../signers";

// 0.001% max relative delta for time based reward checks - ie from BigNumber order of operations -> rounding
const MAX_REL_DELTA = tolerance(0.001);
const MIN_USDG = 1; // The final GLP output is checked - don't need to check for USDG too.

describe("Origami GMX Earn Account", async () => {
    let owner: Signer;
    let alan: Signer;
    let bob: Signer;
    let operator: Signer;
    let gov: Signer;
    let govAddr: string;
    let origamiGmxEarnAccount: OrigamiGmxEarnAccount;
    let gmxContracts: GmxContracts;
    let esGmxVester: IGmxVester;
    let origamiGmxManager: OrigamiGmxManager;

    // GMX Reward rates
    const ethPerSecond = BigNumber.from("41335970000000"); // 0.00004133597 ETH per second
    const esGmxPerSecond = BigNumber.from("20667989410000000"); // 0.02066798941 esGmx per second

    before( async () => {
        [owner, alan, bob, operator, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });
    
    async function setup() {
        const startTs = await blockTimestamp();
        gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

        // Mint some GMX to owner
        const gmxAmount = ethers.utils.parseEther("10000");
        await gmxContracts.gmxToken.mint(await owner.getAddress(), gmxAmount);
        expect(await gmxContracts.gmxToken.balanceOf(await owner.getAddress())).eq(gmxAmount);

        esGmxVester = IGmxVester__factory.connect(await gmxContracts.gmxRewardRouter.gmxVester(), gov);
        origamiGmxEarnAccount = await deployUupsProxy(
            new OrigamiGmxEarnAccount__factory(gov), 
            [gmxContracts.gmxRewardRouter.address],
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            esGmxVester.address,
            gmxContracts.stakedGlp.address,
        );
        await setExplicitAccess(
            origamiGmxEarnAccount,
            await operator.getAddress(),
            [
                "stakeGmx", "unstakeGmx", "stakeEsGmx", "unstakeEsGmx",
                "mintAndStakeGlp", "unstakeAndRedeemGlp", "harvestRewards",
                "transferStakedGlp", "transferStakedGlpOrPause", "handleRewards",
                "depositIntoEsGmxVesting", "withdrawFromEsGmxVesting"],
            true
        );

        origamiGmxManager = await new OrigamiGmxManager__factory(gov).deploy(
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            origamiGmxEarnAccount.address,
            ZERO_ADDRESS, // No secondary account required for this test.
        );
        
        // Ensure the starting timestamp is always consistent (1000 seconds) so the known rewards are locked in.
        // Sometimes `yarn coverage` vs `yarn test` has an extra second or two within the deploy steps.
        const elapsedSecs = (await blockTimestamp()) - startTs;
        await mineForwardSeconds(1000 - elapsedSecs);

        return {
            gmxContracts,
            esGmxVester,
            origamiGmxEarnAccount,
            origamiGmxManager,
        }
    }

    beforeEach(async () => {
        ({
            gmxContracts,
            esGmxVester,
            origamiGmxEarnAccount,
            origamiGmxManager,
        } = await loadFixture(setup));
    });

    describe("Common Admin", async () => {
        it("admin tests", async () => {
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(owner).initGmxContracts(
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                esGmxVester.address,
                gmxContracts.stakedGlp.address)
            );

            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).stakeGmx(0));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).unstakeGmx(0));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).stakeEsGmx(0));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).unstakeEsGmx(0));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).mintAndStakeGlp(0, ZERO_ADDRESS, 0, 0));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).unstakeAndRedeemGlp(0, ZERO_ADDRESS, 0, ZERO_ADDRESS));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).harvestRewards(10_000));

            const handleRewardsParams = {
                shouldClaimGmx: true,
                shouldStakeGmx: true, 
                shouldClaimEsGmx: true, 
                shouldStakeEsGmx: true, 
                shouldStakeMultiplierPoints: true, 
                shouldClaimWeth: true
            };
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).handleRewards(handleRewardsParams));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).depositIntoEsGmxVesting(ZERO_ADDRESS, 0));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).withdrawFromEsGmxVesting(ZERO_ADDRESS));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).transferStakedGlp(0, ZERO_ADDRESS));
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, origamiGmxEarnAccount.connect(alan).transferStakedGlpOrPause(0, ZERO_ADDRESS));
            
            // Happy Paths
            await setExplicitAccess(
                origamiGmxEarnAccount,
                await alan.getAddress(),
                [
                    "stakeGmx", "unstakeGmx", "stakeEsGmx", "unstakeEsGmx",
                    "mintAndStakeGlp", "unstakeAndRedeemGlp", "harvestRewards",
                    "transferStakedGlp", "transferStakedGlpOrPause", "handleRewards",
                    "depositIntoEsGmxVesting", "withdrawFromEsGmxVesting"],
                true
            );
            
            await expect(origamiGmxEarnAccount.connect(alan).stakeGmx(0))
                .to.be.revertedWith("RewardRouter: invalid _amount");
            await expect(origamiGmxEarnAccount.connect(alan).unstakeGmx(0))
                .to.be.revertedWith("RewardRouter: invalid _amount");
            await expect(origamiGmxEarnAccount.connect(alan).stakeEsGmx(0))
                .to.be.revertedWith("RewardRouter: invalid _amount");
            await expect(origamiGmxEarnAccount.connect(alan).unstakeEsGmx(0))
                .to.be.revertedWith("RewardRouter: invalid _amount");
            await expect(origamiGmxEarnAccount.connect(alan).mintAndStakeGlp(0, gmxContracts.bnbToken.address, 0, 0))
                .to.be.revertedWith("RewardRouter: invalid _amount");
            await expect(origamiGmxEarnAccount.connect(alan).unstakeAndRedeemGlp(0, gmxContracts.bnbToken.address, 0, ZERO_ADDRESS))
                .to.be.revertedWith("RewardRouter: invalid _glpAmount");
            await origamiGmxEarnAccount.connect(alan).harvestRewards(10_000);
            await expect(origamiGmxEarnAccount.connect(alan).transferStakedGlp(0, ZERO_ADDRESS))
                .to.be.revertedWith("StakedGlp: transfer to the zero address");
            await expect(origamiGmxEarnAccount.connect(alan).transferStakedGlpOrPause(0, ZERO_ADDRESS))
                .to.be.revertedWith("StakedGlp: transfer to the zero address");

            await origamiGmxEarnAccount.connect(alan).handleRewards(handleRewardsParams);
            await expect(origamiGmxEarnAccount.connect(alan).depositIntoEsGmxVesting(gmxContracts.gmxRewardRouter.gmxVester(), 0))
                .to.be.revertedWith("Vester: invalid _amount");
            await expect(origamiGmxEarnAccount.connect(alan).withdrawFromEsGmxVesting(gmxContracts.gmxRewardRouter.gmxVester()))
                .to.be.revertedWith("Vester: vested amount is zero");

            await origamiGmxEarnAccount.connect(gov).initGmxContracts(
                gmxContracts.gmxRewardRouter.address, 
                gmxContracts.glpRewardRouter.address, 
                esGmxVester.address, 
                gmxContracts.stakedGlp.address
            );
        });

        it("constructor", async () => {
            expect(await origamiGmxEarnAccount.gmxRewardRouter()).eq(gmxContracts.gmxRewardRouter.address); 
            expect(await origamiGmxEarnAccount.glpRewardRouter()).eq(gmxContracts.glpRewardRouter.address); 
            expect(await origamiGmxEarnAccount.gmxToken()).eq(gmxContracts.gmxToken.address); 
            expect(await origamiGmxEarnAccount.esGmxToken()).eq(gmxContracts.esGmxToken.address); 
            expect(await origamiGmxEarnAccount.wrappedNativeToken()).eq(gmxContracts.wrappedNativeToken.address); 
            expect(await origamiGmxEarnAccount.bnGmxAddr()).eq(gmxContracts.multiplierPointsToken.address); 
            expect(await origamiGmxEarnAccount.stakedGmxTracker()).eq(gmxContracts.stakedGmxTracker.address); 
            expect(await origamiGmxEarnAccount.feeGmxTracker()).eq(gmxContracts.feeGmxTracker.address); 
            expect(await origamiGmxEarnAccount.esGmxVester()).eq(esGmxVester.address); 
            expect(await origamiGmxEarnAccount.stakedGlp()).eq(gmxContracts.stakedGlp.address);
            expect(await origamiGmxEarnAccount.glpInvestmentsPaused()).eq(false);
            expect(await origamiGmxEarnAccount.glpLastTransferredAt()).eq(0);

            // These are immutable vars - so check they're set on the underlying too
            const underlyingImplAddress = await upgrades.erc1967.getImplementationAddress(origamiGmxEarnAccount.address);
            const underlyingImpl = OrigamiGmxEarnAccount__factory.connect(underlyingImplAddress, gov);
            expect(await underlyingImpl.gmxToken()).eq(gmxContracts.gmxToken.address); 
            expect(await underlyingImpl.esGmxToken()).eq(gmxContracts.esGmxToken.address); 
            expect(await underlyingImpl.wrappedNativeToken()).eq(gmxContracts.wrappedNativeToken.address); 

            // Whereas a non-immutable is zero on the underlying.
            expect(await underlyingImpl.bnGmxAddr()).eq(ZERO_ADDRESS);
        });
    });

    async function checkTrackerBalances(
        gmxEarnAccount: string, 
        expectedEth: BigNumberish,
        expectedGmx: BigNumberish, 
        expectedEsGmx: BigNumberish,
        expectedStakedGlp: BigNumberish, 
        expectedStakedGmx: BigNumberish, 
        expectedStakedEsGmx: BigNumberish,
    ) {
        // Check unstaked amounts
        const ethBal = await gmxContracts.wrappedNativeToken.balanceOf(gmxEarnAccount);
        const gmxBal = await gmxContracts.gmxToken.balanceOf(gmxEarnAccount);
        const esGmxBal = await gmxContracts.esGmxToken.balanceOf(gmxEarnAccount);
        expect(ethBal).eq(expectedEth);
        expect(gmxBal).eq(expectedGmx);
        expect(esGmxBal).eq(expectedEsGmx);

        // Check staked amounts per token (using depositBalances() which splits by staking token)
        const stakedGlp = await gmxContracts.feeGlpTracker.depositBalances(gmxEarnAccount, gmxContracts.glpToken.address);
        const stakedGmx = await gmxContracts.stakedGmxTracker.depositBalances(gmxEarnAccount, gmxContracts.gmxToken.address);
        const stakedEsGmx = await gmxContracts.stakedGmxTracker.depositBalances(gmxEarnAccount, gmxContracts.esGmxToken.address);

        expect(stakedGlp).eq(expectedStakedGlp);
        expect(stakedGmx).eq(expectedStakedGmx);
        expect(stakedEsGmx).eq(expectedStakedEsGmx);

        // Internal deposit amounts of GMX
        const expectedStakedGmxPlusEsGmx = BigNumber.from(expectedStakedGmx).add(BigNumber.from(expectedStakedEsGmx));

        // The stakedGmxTracker tracks both GMX and esGMX. stakedAmounts() equals the sum of both
        const totalGmxTrackerStaked = await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount);
        expect(totalGmxTrackerStaked).eq(expectedStakedGmxPlusEsGmx);
    }

    describe("Staking GMX", async () => {
        it("should stake GMX", async () => {
            const stakeAmount = 1000;

            // Not enough GMX
            await expect(origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount))
                .to.be.revertedWith("BaseToken: transfer amount exceeds balance");

            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, stakeAmount, 0, 0, 0, 0);
            await expect(origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount))
                .to.emit(gmxContracts.gmxRewardRouter, "StakeGmx")
                .withArgs(origamiGmxEarnAccount.address, gmxContracts.gmxToken.address, stakeAmount);

            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount, 0);

            // Stake some more
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);
            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount*2, 0);
        });

        it("should unstake GMX", async () => {
            const stakeAmount = 1000;

            // No staked balance
            await expect(origamiGmxEarnAccount.connect(operator).unstakeGmx(stakeAmount))
                .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount");

            // Stake some GMX
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);
            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount, 0);

            // Unstake some
            const unstakeAmount = 200;
            await expect(origamiGmxEarnAccount.connect(operator).unstakeGmx(unstakeAmount))
                .to.emit(gmxContracts.gmxRewardRouter, "UnstakeGmx")
                .withArgs(origamiGmxEarnAccount.address, gmxContracts.gmxToken.address, unstakeAmount);
            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount-unstakeAmount, 0);
            await checkTrackerBalances(await operator.getAddress(), 0, unstakeAmount, 0, 0, 0, 0);

            // And the rest...
            await origamiGmxEarnAccount.connect(operator).unstakeGmx(unstakeAmount);
            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount-unstakeAmount*2, 0);
            await checkTrackerBalances(await operator.getAddress(), 0, unstakeAmount*2, 0, 0, 0, 0);
        });
    });

    describe("Buying and staking GLP", async () => {
        it("should buy & stake GLP", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;

            const amount = ethers.utils.parseEther("100");
            await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, amount);

            const quote = (await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;

            // 1 more than the GLP quote amount fails
            await expect(origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.expectedInvestmentAmount.add(1)))
                .to.be.revertedWith("GlpManager: insufficient GLP output");

            // Successfully bought with zero slippage and exact amounts
            await expect(origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.expectedInvestmentAmount))
                .to.emit(gmxContracts.glpRewardRouter, "StakeGlp")
                .withArgs(origamiGmxEarnAccount.address, quote.expectedInvestmentAmount);

            // No BNB, but it has staked GLP
            expect(await gmxContracts.bnbToken.balanceOf(origamiGmxEarnAccount.address)).eq(0);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(quote.expectedInvestmentAmount);
        });

        it("should transfer staked GLP", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const amount = ethers.utils.parseEther("100");

            let glpAmount;
            {
                await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, amount);
                const quote = (await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
                await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.expectedInvestmentAmount);

                // No BNB, but it has staked GLP
                expect(await gmxContracts.bnbToken.balanceOf(origamiGmxEarnAccount.address)).eq(0);
                expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(quote.expectedInvestmentAmount);
                glpAmount = quote.expectedInvestmentAmount;
            }

            await expect(origamiGmxEarnAccount.connect(operator).transferStakedGlp(glpAmount, alan.getAddress()))
                .to.be.revertedWith("StakedGlp: cooldown duration not yet passed");
            await mineForwardSeconds(15*60);

            await expect(origamiGmxEarnAccount.connect(operator).transferStakedGlp(glpAmount, alan.getAddress()))
                .to.emit(origamiGmxEarnAccount, "StakedGlpTransferred")
                .withArgs(await alan.getAddress(), glpAmount);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(0);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress())).eq(glpAmount);
        });

        it("should transfer staked GLP in cooldown", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const amount = ethers.utils.parseEther("100");

            let glpAmount;
            let now;
            {
                await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, amount);
                const quote = (await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
                await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.expectedInvestmentAmount);
                now = await blockTimestamp();

                // No BNB, but it has staked GLP
                expect(await gmxContracts.bnbToken.balanceOf(origamiGmxEarnAccount.address)).eq(0);
                expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(quote.expectedInvestmentAmount);
                glpAmount = quote.expectedInvestmentAmount;
            }

            const expiry = await origamiGmxEarnAccount.glpInvestmentCooldownExpiry();
            expectApproxEqRel(expiry, BigNumber.from(now+15*60), MAX_REL_DELTA);

            const transfer1Amount = glpAmount.div(2);
            const transfer2Amount = glpAmount.sub(transfer1Amount);

            // Doesn't transfer, but does pause glp deposits.
            await expect(origamiGmxEarnAccount.connect(operator).transferStakedGlpOrPause(transfer1Amount, alan.getAddress()))
                .to.emit(origamiGmxEarnAccount, "SetGlpInvestmentsPaused")
                .withArgs(true);
            expect(await origamiGmxEarnAccount.glpInvestmentsPaused()).eq(true);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(glpAmount);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress())).eq(0);

            // And calling again is effectively a no-op
            await expect(origamiGmxEarnAccount.connect(operator).transferStakedGlpOrPause(transfer1Amount, alan.getAddress()))
                .to.not.emit(origamiGmxEarnAccount, "SetGlpInvestmentsPaused");
            expect(await origamiGmxEarnAccount.glpInvestmentsPaused()).eq(true);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(glpAmount);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress())).eq(0);

            // Can't mintAndStake GLP now - it's paused.
            await expect(origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, 0, 0))
                .to.revertedWithCustomError(origamiGmxEarnAccount, "GlpInvestmentsPaused");

            // Sleep off the cooldown.
            await mineForwardSeconds(15*60);

            // Can now transfer
            await expect(origamiGmxEarnAccount.connect(operator).transferStakedGlpOrPause(transfer1Amount, alan.getAddress()))
                .to.emit(origamiGmxEarnAccount, "SetGlpInvestmentsPaused")
                .withArgs(false)
                .to.emit(origamiGmxEarnAccount, "StakedGlpTransferred")
                .withArgs(await alan.getAddress(), transfer1Amount);
            expect(await origamiGmxEarnAccount.glpInvestmentsPaused()).eq(false);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(glpAmount.sub(transfer1Amount));
            expect(await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress())).eq(transfer1Amount);

            // And again when still clear of cooldown - this time no unpaused event
            await expect(origamiGmxEarnAccount.connect(operator).transferStakedGlpOrPause(transfer2Amount, alan.getAddress()))
                .to.emit(origamiGmxEarnAccount, "StakedGlpTransferred")
                .withArgs(await alan.getAddress(), transfer2Amount)
                .to.not.emit(origamiGmxEarnAccount, "SetGlpInvestmentsPaused");
            expect(await origamiGmxEarnAccount.glpInvestmentsPaused()).eq(false);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(0);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress())).eq(glpAmount);
        });

        it("should unstake & sell GLP", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const stakeAmount = ethers.utils.parseEther("100");

            // No staked balance
            await expect(origamiGmxEarnAccount.connect(operator).unstakeAndRedeemGlp(stakeAmount, tokenAddr, 0, alan.getAddress()))
                .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount");

            await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, stakeAmount);
            const buyQuote = (await origamiGmxManager.investOGlpQuote(stakeAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(stakeAmount, tokenAddr, MIN_USDG, buyQuote.expectedInvestmentAmount);

            // Can't immediately sell because of the GMX cooldown (15mins)
            const unstakeAmount = ethers.utils.parseEther("200");
            await expect(origamiGmxEarnAccount.connect(operator).unstakeAndRedeemGlp(unstakeAmount, tokenAddr, 0, alan.getAddress()))
                    .to.be.revertedWith("GlpManager: cooldown duration not yet passed");

            await mineForwardSeconds(15*60);

            // Unstake some
            const sellQuote = (await origamiGmxManager.exitOGlpQuote(unstakeAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await expect(origamiGmxEarnAccount.connect(operator).unstakeAndRedeemGlp(unstakeAmount, tokenAddr, sellQuote.expectedToTokenAmount, alan.getAddress()))
                .to.emit(gmxContracts.glpRewardRouter, "UnstakeGlp")
                .withArgs(origamiGmxEarnAccount.address, unstakeAmount);

            // Alan got the BNB
            expect(await gmxContracts.bnbToken.balanceOf(await alan.getAddress())).eq(sellQuote.expectedToTokenAmount);
            // Staked amount of GLP has dropped
            const expectedRemainingStaked = buyQuote.expectedInvestmentAmount.sub(unstakeAmount);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(expectedRemainingStaked);

            // And the rest...
            const sellQuote2 = (await origamiGmxManager.exitOGlpQuote(expectedRemainingStaked, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await expect(origamiGmxEarnAccount.connect(operator).unstakeAndRedeemGlp(expectedRemainingStaked, tokenAddr, sellQuote2.expectedToTokenAmount, alan.getAddress()))
                .to.emit(gmxContracts.glpRewardRouter, "UnstakeGlp")
                .withArgs(origamiGmxEarnAccount.address, expectedRemainingStaked);

            // Now no staked GLP is left
            expect(await gmxContracts.bnbToken.balanceOf(await alan.getAddress())).eq(sellQuote.expectedToTokenAmount.add(sellQuote2.expectedToTokenAmount));
            expect(await gmxContracts.stakedGlpTracker.balanceOf(origamiGmxEarnAccount.address)).eq(0);
        });

        it("should unstake & sell GLP with slippage", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const stakeAmount = ethers.utils.parseEther("100");
            
            await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, stakeAmount);
            const buyQuote = (await origamiGmxManager.investOGlpQuote(stakeAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(stakeAmount, tokenAddr, MIN_USDG, buyQuote.expectedInvestmentAmount);

            await mineForwardSeconds(15*60);

            const unstakeAmount = ethers.utils.parseEther("200");
            const sellQuote = (await origamiGmxManager.exitOGlpQuote(unstakeAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;

            // Min amount expected is too high
            await expect(origamiGmxEarnAccount.connect(operator).unstakeAndRedeemGlp(unstakeAmount, tokenAddr, sellQuote.expectedToTokenAmount.add(1), alan.getAddress()))
                .to.revertedWith("GlpManager: insufficient output");

            // Slippage is now applied.
            await expect(origamiGmxEarnAccount.connect(operator).unstakeAndRedeemGlp(unstakeAmount, tokenAddr, sellQuote.expectedToTokenAmount, alan.getAddress()))
                .to.emit(gmxContracts.glpRewardRouter, "UnstakeGlp")
                .withArgs(origamiGmxEarnAccount.address, unstakeAmount);
        });
    });

    describe("Harvesting Rewards", async () => {
        async function getMatchingEventArgs(tx: ContractTransaction, eventName: string): Promise<Result> {
            const receipt = await tx.wait();
            if (!receipt.events) {
                throw new ReferenceError("No events");
            }

            for (let i=0; i < receipt.events.length; i++) {
                if (receipt.events[i].event === eventName) {
                    const events = receipt.events[i];
                    if (!events.args) {
                        throw new ReferenceError(`No args on event: ${eventName}`);
                    }
                    return events.args;
                }
            }

            throw new ReferenceError(`No matching events with name: ${eventName}`);
        }

        interface HarvestableRewardsResult {
            wrappedNativeAmount: BigNumber,
            esGmxAmount: BigNumber,
        }

        function checkRewardEvents(
            eventArgs: Result, 
            elapsedSecs: number,
            epsilonSecs: number,
            harvestableRewardsGlp: HarvestableRewardsResult,
            harvestableRewardsGmx: HarvestableRewardsResult,
            stakedGlp: BigNumber,
            stakedGmxAndEsGmx: BigNumber,
            esGmxVestingRate: number,
            esGmxBeingVested: BigNumberish,
        ) {
            const one_year = 365*60*60*24;

            // Check what we havested matches what harvestableRewards shows
            // The actual rewards harvested will be a couple of seconds more worth of rewards
            // since the block time incremented.
            {
                const harvestableEpsilonSecs = 5;

                // ETH from GLP
                expect(eventArgs.wrappedNativeFromGlp).gte(harvestableRewardsGlp.wrappedNativeAmount);
                expect(eventArgs.wrappedNativeFromGlp).lte(harvestableRewardsGlp.wrappedNativeAmount.add(ethPerSecond.mul(harvestableEpsilonSecs)));

                // ETH from GMX
                expect(eventArgs.wrappedNativeFromGmx).gte(harvestableRewardsGmx.wrappedNativeAmount);
                expect(eventArgs.wrappedNativeFromGmx).lte(harvestableRewardsGmx.wrappedNativeAmount.add(ethPerSecond.mul(harvestableEpsilonSecs)));

                // esGMX from GLP
                expect(eventArgs.esGmxFromGlp).gte(harvestableRewardsGlp.esGmxAmount);
                expect(eventArgs.esGmxFromGlp).lte(harvestableRewardsGlp.esGmxAmount.add(esGmxPerSecond.mul(harvestableEpsilonSecs)));

                // esGMX from GMX
                expect(eventArgs.esGmxFromGmx).gte(harvestableRewardsGmx.esGmxAmount);
                expect(eventArgs.esGmxFromGmx).lte(harvestableRewardsGmx.esGmxAmount.add(esGmxPerSecond.mul(harvestableEpsilonSecs)));
            }

            // ETH claimed
            {
                let multiplier = stakedGlp.gt(0) ? 1 : 0;
                expect(eventArgs.wrappedNativeFromGlp).gte(ethPerSecond.mul(elapsedSecs).mul(multiplier));
                expect(eventArgs.wrappedNativeFromGlp).lte(ethPerSecond.mul(elapsedSecs+epsilonSecs).mul(multiplier));

                multiplier = stakedGmxAndEsGmx.gt(0) ? 1 : 0;
                expect(eventArgs.wrappedNativeFromGmx).gte(ethPerSecond.mul(elapsedSecs).mul(multiplier));
                expect(eventArgs.wrappedNativeFromGmx).lte(ethPerSecond.mul(elapsedSecs+epsilonSecs).mul(multiplier));
            }

            // esGMX rewards
            {
                let multiplier = stakedGlp.gt(0) && stakedGmxAndEsGmx.gt(0) ? 2 : 1;

                // A percentage is set to vest into GMX (over 1 year):
                const esGmxVestingPerSecond = esGmxPerSecond.mul(esGmxVestingRate).div(10_000);
                expect(eventArgs.esGmxVesting).gte(esGmxVestingPerSecond.mul(elapsedSecs).mul(multiplier));
                expect(eventArgs.esGmxVesting).lte(esGmxVestingPerSecond.mul(elapsedSecs+epsilonSecs).mul(multiplier));
            }

            // Any GMX that have vested (over 1 year)
            {
                const beingVestedAsBN = BigNumber.from(esGmxBeingVested);
                expect(eventArgs.vestedGmx).gte(beingVestedAsBN.mul(elapsedSecs).div(one_year));
                expect(eventArgs.vestedGmx).lte(beingVestedAsBN.mul(elapsedSecs+epsilonSecs).div(one_year));
            }
        }

        async function testHarvestRewards(
            useGlp: boolean, 
            requestedEsGmxVestingRate: number,
            estimatedEsGmxVestingRate1: number,
            estimatedEsGmxVestingRate2: number
        ) {
            // Nothing claimed as nothing is staked
            await origamiGmxEarnAccount.connect(operator).harvestRewards(requestedEsGmxVestingRate);
            await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, 0, 0);
            await checkTrackerBalances(await operator.getAddress(), 0, 0, 0, 0, 0, 0);

            // Refresh the GMX rewards distribution time so we get a better idea on how much has accrued
            await updateDistributionTime(gmxContracts);

            const stakeAmount = ethers.utils.parseEther("250");

            let expectedStakedGmxAmount = BN_ZERO;
            let expectedStakedGlpAmount = BN_ZERO;
            if (useGlp) {
                await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, stakeAmount);
                const origamiGmxManager = await new OrigamiGmxManager__factory(gov).deploy(
                    govAddr,
                    gmxContracts.gmxRewardRouter.address,
                    gmxContracts.glpRewardRouter.address,
                    ZERO_ADDRESS,
                    ZERO_ADDRESS,
                    ZERO_ADDRESS,
                    origamiGmxEarnAccount.address,
                    ZERO_ADDRESS,
                );
                const quote = (await origamiGmxManager.investOGlpQuote(stakeAmount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
                await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(
                    stakeAmount, gmxContracts.bnbToken.address, MIN_USDG, quote.expectedInvestmentAmount
                );
                expectedStakedGlpAmount = quote.expectedInvestmentAmount;
            } else {
                await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
                await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);
                expectedStakedGmxAmount = stakeAmount;
            }

            // Accrue some rewards over a day
            const elapsedSecs = 86400;
            await mineForwardSeconds(elapsedSecs);
            await checkTrackerBalances(
                origamiGmxEarnAccount.address, 0, 0, 0, 
                expectedStakedGlpAmount, expectedStakedGmxAmount,
                0
            );
            await checkTrackerBalances(await operator.getAddress(), 0, 0, 0, 0, 0, 0);

            const harvestableRewardsGlp = await origamiGmxEarnAccount.harvestableRewards(GmxVaultType.GLP);
            const harvestableRewardsGmx = await origamiGmxEarnAccount.harvestableRewards(GmxVaultType.GMX);

            // Harvest rewards
            // Ethers messes up the gas estimation on this one for some reason - so need to specify manually.
            const tx = await origamiGmxEarnAccount.connect(operator).harvestRewards(requestedEsGmxVestingRate);
            const eventArgs = await getMatchingEventArgs(tx, "RewardsHarvested");

            // Actual elapsed time since we staked is 1 day ++
            // For the first GMX stake, the clock for rewards starts when updateLastDistributionTime() was called
            // So add an error of 10 seconds to the expected rewards.
            // The multiplier points get earnt on total of staked GMX and esGMX tokens
            checkRewardEvents(
                eventArgs, elapsedSecs, 10, harvestableRewardsGlp, harvestableRewardsGmx,
                expectedStakedGlpAmount, expectedStakedGmxAmount, 
                estimatedEsGmxVestingRate1, 0
            );
            
            const totalEth: BigNumber = eventArgs.wrappedNativeFromGmx.add(eventArgs.wrappedNativeFromGlp);
            const reinvestedEsGmx: BigNumber = eventArgs.esGmxFromGmx.add(eventArgs.esGmxFromGlp).sub(eventArgs.esGmxVesting);
            await checkTrackerBalances(
                origamiGmxEarnAccount.address, 0, 0, 0, 
                expectedStakedGlpAmount, expectedStakedGmxAmount, 
                reinvestedEsGmx);
            await checkTrackerBalances(await operator.getAddress(), totalEth, 0, 0, 0, 0, 0);

            // By default, the multiplier points rewards started accruing right after
            // updateDistributionTime() was first set above, even though there may not 
            // been any multiplier points stakers earning that yield.
            // If there wasn't anyone staking GMX, then reset the clock to start accruing from now.
            if (expectedStakedGmxAmount.eq(0)) {
                await gmxContracts.bonusGmxDistributor.updateLastDistributionTime();
            }

            // Harvest one more time after one more day
            await mineForwardSeconds(elapsedSecs);
            const harvestableRewardsGlp2 = await origamiGmxEarnAccount.harvestableRewards(GmxVaultType.GLP);
            const harvestableRewardsGmx2 = await origamiGmxEarnAccount.harvestableRewards(GmxVaultType.GMX);

            const tx2 = await origamiGmxEarnAccount.connect(operator).harvestRewards(requestedEsGmxVestingRate);
            const eventArgs2 = await getMatchingEventArgs(tx2, "RewardsHarvested");

            // The multiplier points are also now earnt on the esGMX that we've staked
            // And some of the esGMX previously deposited into the vesting contract has now vested into GMX
            const stakedGmxAndEsGmx = expectedStakedGmxAmount.add(reinvestedEsGmx);
            const esGmxBeingVested = eventArgs.esGmxVesting;
            checkRewardEvents(
                eventArgs2, elapsedSecs, 10, harvestableRewardsGlp2, harvestableRewardsGmx2,
                expectedStakedGlpAmount, stakedGmxAndEsGmx, 
                estimatedEsGmxVestingRate2, esGmxBeingVested
            );

            // The earn account has increased it's amount of staked esGMX and multiplier points again
            const reinvestedEsGmx2: BigNumber = eventArgs2.esGmxFromGmx.add(eventArgs2.esGmxFromGlp).sub(eventArgs2.esGmxVesting);
            await checkTrackerBalances(
                origamiGmxEarnAccount.address, 
                0, 0, 0,
                expectedStakedGlpAmount, expectedStakedGmxAmount, 
                reinvestedEsGmx.add(reinvestedEsGmx2),
            );

            // The Origami GMX Manager now has some extra ETH, and also some GMX from the vested esGMX
            const totalEth2: BigNumber = totalEth.add(eventArgs2.wrappedNativeFromGmx).add(eventArgs2.wrappedNativeFromGlp);
            await checkTrackerBalances(
                await operator.getAddress(), 
                totalEth2, 
                eventArgs2.vestedGmx, 
                0, 0, 0, 0);
        };

        it("should harvest rewards - GMX - no esGMX vesting", async () => {
            const esGmxVestingRate = 0;
            await testHarvestRewards(false, esGmxVestingRate, esGmxVestingRate, esGmxVestingRate);
        });

        it("should harvest rewards - GMX - 25% esGMX vesting", async () => {
            const esGmxVestingRate = 2_500;
            await testHarvestRewards(false, esGmxVestingRate, esGmxVestingRate, esGmxVestingRate);
        });

        it("should harvest rewards - GMX - 100% esGMX vesting", async () => {
            const esGmxVestingRate = 10_000;
            await testHarvestRewards(false, esGmxVestingRate, esGmxVestingRate, esGmxVestingRate);
        });

        it("should harvest rewards - GLP - no esGMX vesting", async () => {
            const esGmxVestingRate = 0;
            await testHarvestRewards(true, esGmxVestingRate, esGmxVestingRate, esGmxVestingRate);
        });

        it("should harvest rewards - GLP - 25% esGMX vesting", async () => {
            // While we request 25% to be vested, we may not have accumulated enough
            // rewards to allow this in the GMX protocol.
            // Instead it's first capped (at 0%) because we hadn't earnt any rewards yet
            // And then we can vest over 25%, so we get what we ask for.
            const requestedEsGmxVestingRate = 2_500;
            const estimatedEsGmxVestingRate1 = 0;
            const estimatedEsGmxVestingRate2 = 2_500;
            await testHarvestRewards(true, requestedEsGmxVestingRate, estimatedEsGmxVestingRate1, estimatedEsGmxVestingRate2);
        });

        it("should harvest rewards - GLP - 100% esGMX vesting", async () => {
            // While we request 25% to be vested, we may not have accumulated enough
            // rewards to allow this in the GMX protocol.
            // Instead it's first capped (at 0%) because we hadn't earnt any rewards yet
            // And then it's very very close to 50% of what we earnt
            const requestedEsGmxVestingRate = 10_000;
            const estimatedEsGmxVestingRate1 = 0;
            const estimatedEsGmxVestingRate2 = 5_000;
            await testHarvestRewards(true, requestedEsGmxVestingRate, estimatedEsGmxVestingRate1, estimatedEsGmxVestingRate2);
        });
    });

    describe("Checking Reward Rates", async () => {
        it("Should get GMX reward rates", async () => {
            const stakeAmount = ethers.utils.parseEther("250");

            // Origami buys GMX
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);
            let rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            let rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);

            // No GLP rewards
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(0);
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(0);

            // Rates == 100% of the GMX rewards
            expect(rewardRatesGmx.wrappedNativeTokensPerSec).eq(ethPerSecond);
            expect(rewardRatesGmx.esGmxTokensPerSec).eq(esGmxPerSecond);

            // Bob buys the same amount GMX directly (not via Origami)
            await gmxContracts.gmxToken.transfer(bob.getAddress(), stakeAmount);
            await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, stakeAmount);
            await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(stakeAmount);

            rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);

            // Still no GLP rewards
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(0);
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(0);

            // origami's GMX now has 50% of the total
            expect(rewardRatesGmx.wrappedNativeTokensPerSec).eq(ethPerSecond.div(2));
            expect(rewardRatesGmx.esGmxTokensPerSec).eq(esGmxPerSecond.div(2));
        });

        it("Should get GLP reward rates", async () => {
            const stakeAmount = ethers.utils.parseEther("250");

            // Origami buys GLP
            await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, stakeAmount);
            const origamiQuote = (await origamiGmxManager.investOGlpQuote(stakeAmount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(
                stakeAmount, gmxContracts.bnbToken.address, MIN_USDG, origamiQuote.expectedInvestmentAmount
            );
            let rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            let rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);

            // Rates == 100% of the GLP rewards
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(ethPerSecond);
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(esGmxPerSecond);

            // GMX rewards are 0
            expect(rewardRatesGmx.wrappedNativeTokensPerSec).eq(0);
            expect(rewardRatesGmx.esGmxTokensPerSec).eq(0);

            // Bob buys the same amount GLP directly (not via Origami)
            await gmxContracts.bnbToken.mint(bob.getAddress(), stakeAmount);
            await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), stakeAmount);
            const bobQuote = (await origamiGmxManager.investOGlpQuote(stakeAmount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                gmxContracts.bnbToken.address, stakeAmount, MIN_USDG, bobQuote.expectedInvestmentAmount
            );

            // Now Origami gets roughly 50% (slightly different GLP quotes)
            const precision = ethers.utils.parseEther("1");
            const expectedRatio = origamiQuote.expectedInvestmentAmount.mul(precision).div(origamiQuote.expectedInvestmentAmount.add(bobQuote.expectedInvestmentAmount));

            rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(ethPerSecond.mul(expectedRatio).div(precision));
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(esGmxPerSecond.mul(expectedRatio).div(precision));

            // GMX rewards are still 0
            expect(rewardRatesGmx.wrappedNativeTokensPerSec).eq(0);
            expect(rewardRatesGmx.esGmxTokensPerSec).eq(0);
        });

        it("Should get GMX + GLP reward rates", async () => {
            const stakeAmount = ethers.utils.parseEther("250");

            let origamiGlpQuote;
            {
                // Origami buys GMX
                await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
                await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);

                // Origami buys GLP
                await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, stakeAmount);
                origamiGlpQuote = (await origamiGmxManager.investOGlpQuote(stakeAmount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
                await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(
                    stakeAmount, gmxContracts.bnbToken.address, MIN_USDG, origamiGlpQuote.expectedInvestmentAmount
                );
            }

            let rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            let rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);

            // Rates == 2x the GMX rewards (same rewards for both GMX and GLP, but independent reward pools)
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(ethPerSecond);
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(esGmxPerSecond);
            expect(rewardRatesGmx.wrappedNativeTokensPerSec).eq(ethPerSecond);
            expect(rewardRatesGmx.esGmxTokensPerSec).eq(esGmxPerSecond);

            // Bob gets some oGLP
            let bobGlpQuote;
            {
                // Bob buys the same amount GMX directly (not via Origami)
                await gmxContracts.gmxToken.transfer(bob.getAddress(), stakeAmount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, stakeAmount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(stakeAmount);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), stakeAmount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), stakeAmount);
                bobGlpQuote = (await origamiGmxManager.investOGlpQuote(stakeAmount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, stakeAmount, MIN_USDG, bobGlpQuote.expectedInvestmentAmount
                );
            }

            // Now Origami gets roughly 50% (slightly different GLP quotes)
            const precision = ethers.utils.parseEther("1");
            const expectedRatio = origamiGlpQuote.expectedInvestmentAmount.mul(precision).div(origamiGlpQuote.expectedInvestmentAmount.add(bobGlpQuote.expectedInvestmentAmount));
            const expectedGlpEthPerSec = ethPerSecond.mul(expectedRatio).div(precision);
            const expectedGlpEsGmxPerSec = esGmxPerSecond.mul(expectedRatio).div(precision);

            const expectedGmxEthPerSec = ethPerSecond.div(2);
            const expectedGmxEsGmxPerSec = esGmxPerSecond.div(2);

            // 100% of the GMX 
            rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(expectedGlpEthPerSec);
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(expectedGlpEsGmxPerSec);

            expect(rewardRatesGmx.wrappedNativeTokensPerSec).eq(expectedGmxEthPerSec);
            expect(rewardRatesGmx.esGmxTokensPerSec).eq(expectedGmxEsGmxPerSec);

            // Harvest rewards such that we compound into staked esGMX
            await origamiGmxEarnAccount.connect(operator).harvestRewards(0);
            await mineForwardSeconds(86400);
            rewardRatesGlp = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GLP);
            rewardRatesGmx = await origamiGmxEarnAccount.rewardRates(GmxVaultType.GMX);

            // The GLP rewards stay the same
            expect(rewardRatesGlp.wrappedNativeTokensPerSec).eq(expectedGlpEthPerSec);
            expect(rewardRatesGlp.esGmxTokensPerSec).eq(expectedGlpEsGmxPerSec);

            // The GMX rewards have increased a touch
            expect(rewardRatesGmx.wrappedNativeTokensPerSec).gt(expectedGmxEthPerSec);
            expect(rewardRatesGmx.esGmxTokensPerSec).gt(expectedGmxEsGmxPerSec);
        });
    });

    describe("Checking Manual GMX calls", async () => {
        it("Should handleRewards()", async () => {
            // Origami stakes GMX
            const stakeAmount = ethers.utils.parseEther("250");
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);

            await mineForwardSeconds(86400);

            const stakedEsGmxBefore = await gmxContracts.stakedGmxTracker.depositBalances(
                origamiGmxEarnAccount.address, gmxContracts.esGmxToken.address
            );
            expect(stakedEsGmxBefore).eq(0);

            const positionsBefore = await origamiGmxEarnAccount.positions();
            const handleRewardsParams = {
                shouldClaimGmx: true,
                shouldStakeGmx: true, 
                shouldClaimEsGmx: true, 
                shouldStakeEsGmx: true, 
                shouldStakeMultiplierPoints: true, 
                shouldClaimWeth: true
            };
            await origamiGmxEarnAccount.connect(operator).handleRewards(handleRewardsParams);
            const positionsAfter = await origamiGmxEarnAccount.positions();

            expect(positionsAfter.gmxPositions.stakedEsGmx).gt(positionsBefore.gmxPositions.stakedEsGmx);
            expect(positionsAfter.gmxPositions.stakedMultiplierPoints).gt(positionsBefore.gmxPositions.stakedMultiplierPoints);
            expect(positionsAfter.gmxPositions.claimableNative).eq(0);
            expect(positionsAfter.gmxPositions.claimableEsGmx).eq(0);
            expect(positionsAfter.gmxPositions.claimableMultPoints).eq(0);
        });

        it("Should handleRewards()", async () => {
            // Origami stakes GMX
            const stakeAmount = ethers.utils.parseEther("250");
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);

            await mineForwardSeconds(86400);

            const handleRewardsParams = {
                shouldClaimGmx: false,
                shouldStakeGmx: false, 
                shouldClaimEsGmx: false, 
                shouldStakeEsGmx: false, 
                shouldStakeMultiplierPoints: false, 
                shouldClaimWeth: false
            };
            await origamiGmxEarnAccount.connect(operator).handleRewards(handleRewardsParams);
            const positionsAfter = await origamiGmxEarnAccount.positions();

            expect(positionsAfter.gmxPositions.stakedEsGmx).eq(0);
            expect(positionsAfter.gmxPositions.stakedMultiplierPoints).eq(0);
            expect(positionsAfter.gmxPositions.claimableNative).gt(0);
            expect(positionsAfter.gmxPositions.claimableEsGmx).gt(0);
            expect(positionsAfter.gmxPositions.claimableMultPoints).gt(0);
        });

        it("Should deposit and withdrawl in vesting", async () => {
            // Origami stakes GMX
            const stakeAmount = ethers.utils.parseEther("250");
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
            await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);

            await mineForwardSeconds(86400);

            // Claim the esGMX but don't stake
            const handleRewardsParams = {
                shouldClaimGmx: true,
                shouldStakeGmx: true, 
                shouldClaimEsGmx: true, 
                shouldStakeEsGmx: false, 
                shouldStakeMultiplierPoints: true, 
                shouldClaimWeth: true
            };
            await origamiGmxEarnAccount.connect(operator).handleRewards(handleRewardsParams);
            const esGmxBal = await gmxContracts.esGmxToken.balanceOf(origamiGmxEarnAccount.address);
            expect(esGmxBal).gt(0);

            // Deposit into vesting
            const vester = GMX_Vester__factory.connect(await gmxContracts.gmxRewardRouter.gmxVester(), gov);
            await origamiGmxEarnAccount.connect(operator).depositIntoEsGmxVesting(vester.address, esGmxBal);

            let vestedBal = await vester.getTotalVested(origamiGmxEarnAccount.address);
            expect(vestedBal).gt(0);

            // Withdraw from vesting
            await origamiGmxEarnAccount.connect(operator).withdrawFromEsGmxVesting(vester.address);
            vestedBal = await vester.getTotalVested(origamiGmxEarnAccount.address);
            expect(vestedBal).eq(0);
        });
         
    });

    describe("Positions", async () => {
        async function verifyPositions(
            unstakedGmx: BigNumber = BN_ZERO,
            stakedGmx: BigNumber = BN_ZERO,
            unstakedEsGmx: BigNumber = BN_ZERO,
            stakedEsGmx: BigNumber = BN_ZERO,
            stakedMultiplierPoints: BigNumber = BN_ZERO,
            claimableNativeFromGmx: BigNumber = BN_ZERO,
            claimableEsGmxFromGmx: BigNumber = BN_ZERO,
            claimableMultPointsFromGmx: BigNumber = BN_ZERO,
            vestingEsGmxFromGmx: BigNumber = BN_ZERO,
            claimableVestedGmxFromGmx: BigNumber = BN_ZERO,

            stakedGlp: BigNumber = BN_ZERO,
            claimableNativeFromGlp: BigNumber = BN_ZERO,
            claimableEsGmxFromGlp: BigNumber = BN_ZERO,
            vestingEsGmxFromGlp: BigNumber = BN_ZERO,
            claimableVestedGmxFromGlp: BigNumber = BN_ZERO,
        ) {
            const {gmxPositions, glpPositions} = await origamiGmxEarnAccount.positions();
            expect(gmxPositions.unstakedGmx).eq(unstakedGmx);
            expect(gmxPositions.stakedGmx).eq(stakedGmx);
            expect(gmxPositions.unstakedEsGmx).eq(unstakedEsGmx);
            expect(gmxPositions.stakedEsGmx).eq(stakedEsGmx);
            expect(gmxPositions.stakedMultiplierPoints).eq(stakedMultiplierPoints);
            expect(gmxPositions.claimableNative).eq(claimableNativeFromGmx);
            expect(gmxPositions.claimableEsGmx).eq(claimableEsGmxFromGmx);
            expect(gmxPositions.claimableMultPoints).eq(claimableMultPointsFromGmx);
            expect(gmxPositions.vestingEsGmx).eq(vestingEsGmxFromGmx);
            expect(gmxPositions.claimableVestedGmx).eq(claimableVestedGmxFromGmx);

            expect(glpPositions.stakedGlp).eq(stakedGlp);
            expect(glpPositions.claimableNative).eq(claimableNativeFromGlp);
            expect(glpPositions.claimableEsGmx).eq(claimableEsGmxFromGlp);
            expect(glpPositions.vestingEsGmx).eq(vestingEsGmxFromGlp);
            expect(glpPositions.claimableVestedGmx).eq(claimableVestedGmxFromGlp);
        }

        // NB: Not testing the underlying GMX calcs of what rewards we get (that's done elsewhere)
        // -- just that the position amounts match expectation. So pluming exact reward numbers in directly.
        it("gmx based positions", async () => {
            // Starts off empty
            await verifyPositions();

            // Origami stakes GMX and also has some on hand unstaked
            const amount = ethers.utils.parseEther("250");
            await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, amount.mul(2));
            await origamiGmxEarnAccount.connect(operator).stakeGmx(amount);
            let claimableMultPoints = ethers.utils.parseEther("0.007546930492135971");
            await verifyPositions(amount, amount, BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, claimableMultPoints);

            // claim + stake esGMX + mult points
            await mineForwardSeconds(86400);
            await origamiGmxEarnAccount.connect(operator).handleRewards({
                shouldClaimGmx: true,
                shouldStakeGmx: true,
                shouldClaimEsGmx: true,
                shouldStakeEsGmx: true,
                shouldStakeMultiplierPoints: true,
                shouldClaimWeth: true,
            });

            // staked esGMX and mult points have now increased after claiming+staking
            const expectedStakedEsGmx = ethers.utils.parseEther("1785.73495301341");
            const expectedStakedMultPoints = ethers.utils.parseEther("0.692486364789446981");
            await verifyPositions(amount, amount, BN_ZERO, expectedStakedEsGmx, expectedStakedMultPoints);

            // Unstake some esGMX
            const unstakedEsGmx = ethers.utils.parseEther("1000");
            await origamiGmxEarnAccount.connect(operator).unstakeEsGmx(unstakedEsGmx);
            const expectedStakedMultPoints2 = ethers.utils.parseEther("0.352353920610624382"); // mult points get burnt from unstaking esGMX
            let updatedStakedEsGMX = expectedStakedEsGmx.sub(unstakedEsGmx);
            let claimableNative = ethers.utils.parseEther("0.000041335969999999");
            let claimableEsGmx = ethers.utils.parseEther("0.020667989409999999");
            await verifyPositions(amount, amount, unstakedEsGmx, updatedStakedEsGMX, expectedStakedMultPoints2, claimableNative, claimableEsGmx);

            // Restake some esGMX
            const restakedEsGmx = ethers.utils.parseEther("500");
            await origamiGmxEarnAccount.connect(operator).stakeEsGmx(restakedEsGmx);
            let updatedUnstakedEsGmx = unstakedEsGmx.sub(restakedEsGmx);
            updatedStakedEsGMX = updatedStakedEsGMX.add(restakedEsGmx);
            claimableNative = ethers.utils.parseEther("0.000082671939999998");
            claimableEsGmx = ethers.utils.parseEther("0.041335978819999998");
            claimableMultPoints = ethers.utils.parseEther("0.000032842939910368");
            await verifyPositions(amount, amount, updatedUnstakedEsGmx, updatedStakedEsGMX, expectedStakedMultPoints2, claimableNative, claimableEsGmx, claimableMultPoints);

            // Deposit some esGMX into vesting
            const vestingEsGmx = ethers.utils.parseEther("125");
            await origamiGmxEarnAccount.connect(operator).depositIntoEsGmxVesting(gmxContracts.gmxVester.address, vestingEsGmx);
            updatedUnstakedEsGmx = updatedUnstakedEsGmx.sub(vestingEsGmx);
            claimableNative = ethers.utils.parseEther("0.000124007909999997");
            claimableEsGmx = ethers.utils.parseEther("0.062003968229999997");
            claimableMultPoints = ethers.utils.parseEther("0.000081540775812618");
            await verifyPositions(amount, amount, updatedUnstakedEsGmx, updatedStakedEsGMX, expectedStakedMultPoints2, claimableNative, claimableEsGmx, claimableMultPoints, vestingEsGmx);

            // Wait some time and we have claimable vested GMX from esGMX
            await mineForwardSeconds(86400);
            const expectedClaimableGmx = ethers.utils.parseEther("0.342465753424657534");
            claimableNative = ethers.utils.parseEther("3.571551815909999997");
            claimableEsGmx = ethers.utils.parseEther("1785.776288992229999997");
            claimableMultPoints = ethers.utils.parseEther("4.207574562730360563");
            await verifyPositions(amount, amount, updatedUnstakedEsGmx, updatedStakedEsGMX, expectedStakedMultPoints2, claimableNative, claimableEsGmx, claimableMultPoints, vestingEsGmx, expectedClaimableGmx);
        });

        it("glp based positions", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;

            // Origami buys and stakes GLP
            const amount = ethers.utils.parseEther("250");
            await gmxContracts.bnbToken.mint(origamiGmxEarnAccount.address, amount);
            const quote = (await origamiGmxManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            await origamiGmxEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, quote.expectedInvestmentAmount);
            await verifyPositions(
                BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO,
                BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, 
                quote.expectedInvestmentAmount);

            // claim + stake esGMX + mult points
            await mineForwardSeconds(86400);
            await origamiGmxEarnAccount.connect(operator).handleRewards({
                shouldClaimGmx: true,
                shouldStakeGmx: true,
                shouldClaimEsGmx: true,
                shouldStakeEsGmx: true,
                shouldStakeMultiplierPoints: true,
                shouldClaimWeth: true,
            });

            // staked esGMX and mult points have now increased after claiming+staking
            const expectedStakedEsGmx = ethers.utils.parseEther("1785.734953013409999999");
            const expectedStakedMultPoints = ethers.utils.parseEther("4.946388424358840807");
            await verifyPositions(
                BN_ZERO, BN_ZERO, BN_ZERO, expectedStakedEsGmx, expectedStakedMultPoints, 
                BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, BN_ZERO, 
                quote.expectedInvestmentAmount);

            // Unstake some esGMX
            const unstakedEsGmx = ethers.utils.parseEther("1000");
            await origamiGmxEarnAccount.connect(operator).unstakeEsGmx(unstakedEsGmx);
            const expectedStakedMultPoints2 = ethers.utils.parseEther("2.176467880692967311"); // mult points get burnt from unstaking esGMX
            let updatedStakedEsGMX = expectedStakedEsGmx.sub(unstakedEsGmx);
            let claimableNativeFromGmx = ethers.utils.parseEther("0.000041335969999999");
            let claimableEsGmxFromGmx = ethers.utils.parseEther("0.020667989409999999");
            let claimableNativeFromGlp = ethers.utils.parseEther("0.000041335969999999");
            let claimableEsGmxFromGlp = ethers.utils.parseEther("0.020667989409999999");
            await verifyPositions(
                BN_ZERO, BN_ZERO, unstakedEsGmx, updatedStakedEsGMX, expectedStakedMultPoints2,
                claimableNativeFromGmx, claimableEsGmxFromGmx, BN_ZERO, BN_ZERO, BN_ZERO, 
                quote.expectedInvestmentAmount, claimableNativeFromGlp, claimableEsGmxFromGlp);

            // Deposit some esGMX into GLP vesting
            const vestingEsGmx = ethers.utils.parseEther("125");
            claimableNativeFromGmx = ethers.utils.parseEther("0.000082671939999998");
            claimableEsGmxFromGmx = ethers.utils.parseEther("0.041335978819999998");
            claimableNativeFromGlp = ethers.utils.parseEther("0.000082671939999999");
            claimableEsGmxFromGlp = ethers.utils.parseEther("0.041335978819999999");
            let claimableMultPointsFromGmx = ethers.utils.parseEther("0.000024915491914427");
            await origamiGmxEarnAccount.connect(operator).depositIntoEsGmxVesting(gmxContracts.glpVester.address, vestingEsGmx);
            await verifyPositions(
                BN_ZERO, BN_ZERO, unstakedEsGmx.sub(vestingEsGmx), updatedStakedEsGMX, expectedStakedMultPoints2,
                claimableNativeFromGmx, claimableEsGmxFromGmx, claimableMultPointsFromGmx, BN_ZERO, BN_ZERO, 
                quote.expectedInvestmentAmount, claimableNativeFromGlp, claimableEsGmxFromGlp, vestingEsGmx, BN_ZERO);

            // Wait some time and we have claimable vested GMX from esGMX
            await mineForwardSeconds(86400);

            claimableNativeFromGmx = ethers.utils.parseEther("3.571510479939999998");
            claimableEsGmxFromGmx = ethers.utils.parseEther("1785.755621002819999998");
            claimableMultPointsFromGmx = ethers.utils.parseEther("2.152723416898517166");

            claimableNativeFromGlp = ethers.utils.parseEther("3.571510479939999999");
            claimableEsGmxFromGlp = ethers.utils.parseEther("1785.755621002819999999");
            const expectedClaimableGmx = ethers.utils.parseEther("0.342465753424657534");
            await verifyPositions(
                BN_ZERO, BN_ZERO, unstakedEsGmx.sub(vestingEsGmx), updatedStakedEsGMX, expectedStakedMultPoints2,
                claimableNativeFromGmx, claimableEsGmxFromGmx, claimableMultPointsFromGmx, BN_ZERO, BN_ZERO, 
                quote.expectedInvestmentAmount, claimableNativeFromGlp, claimableEsGmxFromGlp, vestingEsGmx, expectedClaimableGmx);
        });
    });

    describe("upgrade", async () => {
        it("should upgrade() - an existing var is the same", async () => {
            // Check a var before upgrade
            expect(await origamiGmxEarnAccount.gmxToken()).eq(gmxContracts.gmxToken.address);

            // Only governance can upgrade
            await expect(upgradeUupsProxy(origamiGmxEarnAccount.address, [gmxContracts.gmxRewardRouter.address], new DummyOrigamiGmxEarnAccount__factory(owner)))
                .to.revertedWithCustomError(origamiGmxEarnAccount, "InvalidAccess");

            // Gov upgrades the contract
            await upgradeUupsProxy(origamiGmxEarnAccount.address, [gmxContracts.gmxRewardRouter.address], new DummyOrigamiGmxEarnAccount__factory(gov));

            // The gov remains unchanged even though gov upgraded it
            expect(await origamiGmxEarnAccount.owner()).eq(await gov.getAddress());

            // Check the new contract storage after upgrading it.
            expect(await origamiGmxEarnAccount.gmxToken()).eq(gmxContracts.gmxToken.address);
        });

        it("should upgrade() with the call - the new storage var is set as expected", async () => {
            // Check a var before upgrade
            expect(await origamiGmxEarnAccount.gmxToken()).eq(gmxContracts.gmxToken.address);

            // Upgrade the contract and call the function
            await upgradeUupsProxyAndCall(origamiGmxEarnAccount.address, new DummyOrigamiGmxEarnAccount__factory(gov), [gmxContracts.gmxRewardRouter.address], {
                fn: "setNewAddr",
                args: [await alan.getAddress()]
            });

            // Get the new contract
            const newAcct = DummyOrigamiGmxEarnAccount__factory.connect(origamiGmxEarnAccount.address, gov);

            // The new contract addr is the same as the previous contract
            expect(newAcct.address).eq(origamiGmxEarnAccount.address);

            // Check the new contract storage after upgrading it.
            expect(await newAcct.gmxToken()).eq(gmxContracts.gmxToken.address);

            // The new storage var are set as expected.
            expect(await newAcct.newAddr()).eq(await alan.getAddress());

            // Check the ownership of authorizeUpgrade
            await shouldRevertInvalidAccess(origamiGmxEarnAccount, newAcct.connect(alan).authorizeUpgrade());
            await newAcct.authorizeUpgrade();
        });

        it("after upgrading, calling a method on the proxy definitely then calls the new contract", async () => {
            // Upgrade the contract and call the function
            await upgradeUupsProxyAndCall(origamiGmxEarnAccount.address, new DummyOrigamiGmxEarnAccount__factory(gov), [gmxContracts.gmxRewardRouter.address], {
                fn: "setNewAddr",
                args: [await alan.getAddress()]
            });

            // Get the new contract
            const newAcct = DummyOrigamiGmxEarnAccount__factory.connect(origamiGmxEarnAccount.address, gov);

            // Check the new contract storage
            expect(await newAcct.newAddr()).eq(await alan.getAddress());

            // Calling a method on the proxy definitely calls the new contract
            await newAcct.setNewAddr(await gov.getAddress());
            expect(await newAcct.newAddr()).eq(await gov.getAddress());
        });

        it("after upgrading, calling a method on the implementation contract directly doesn't affect the old contract", async () => {
            const stakeAmount = 1000;
            {
                await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
                await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);
                await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount, 0);
            }
            
            // Get the old implementation contract
            const oldUnderlyingImplAddress = await upgrades.erc1967.getImplementationAddress(origamiGmxEarnAccount.address);
            const oldUnderlyingImpl = OrigamiGmxEarnAccount__factory.connect(oldUnderlyingImplAddress, gov);
            
            // Upgrade the staking contract and call the function
            await upgradeUupsProxyAndCall(origamiGmxEarnAccount.address, new DummyOrigamiGmxEarnAccount__factory(gov), [gmxContracts.gmxRewardRouter.address], {
                fn: "setNewAddr",
                args: [await alan.getAddress()]
            });

            // Get the new staking and its implementation contract
            const newContract = DummyOrigamiGmxEarnAccount__factory.connect(origamiGmxEarnAccount.address, gov);

            const newUnderlyingImplAddress = await upgrades.erc1967.getImplementationAddress(origamiGmxEarnAccount.address);
            const newUnderlyingImpl = DummyOrigamiGmxEarnAccount__factory.connect(newUnderlyingImplAddress, gov);

            {
                expect(await newUnderlyingImpl.gmxToken()).eq(gmxContracts.gmxToken.address); 
                expect(await newUnderlyingImpl.esGmxToken()).eq(gmxContracts.esGmxToken.address); 
                expect(await newUnderlyingImpl.wrappedNativeToken()).eq(gmxContracts.wrappedNativeToken.address); 
                // Whereas a non-immutable is zero on the underlying.
                expect(await newUnderlyingImpl.bnGmxAddr()).eq(ZERO_ADDRESS);
            }

            // Calling a method on the old implementation contract directly affects nothing in the new contract
            // All tx to old implementation contract are reverted as all the storage vars are completely empty.
            await shouldRevertInvalidAccess(oldUnderlyingImpl, oldUnderlyingImpl.proposeNewOwner(await bob.getAddress()));
                        
            // Stake some more -- still works
            {
                await gmxContracts.gmxToken.transfer(origamiGmxEarnAccount.address, stakeAmount);
                await origamiGmxEarnAccount.connect(operator).stakeGmx(stakeAmount);
                await checkTrackerBalances(origamiGmxEarnAccount.address, 0, 0, 0, 0, stakeAmount*2, 0);
            }
            
            // Calling a method on the new implementation contract directly doesn't affect the contract
            const newAddr = await newContract.newAddr();
            await newUnderlyingImpl.setNewAddr(await gov.getAddress());

            expect(await newUnderlyingImpl.newAddr()).eq(await gov.getAddress());
            expect(await newContract.newAddr()).eq(newAddr);
            expect(await newUnderlyingImpl.newAddr()).not.eq(await newContract.newAddr());
        });
    });
});
