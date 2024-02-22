import { ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { expect } from "chai";
import { 
    mineForwardSeconds,
    ZERO_ADDRESS, 
    recoverToken, 
    deployUupsProxy, 
    shouldRevertInvalidAccess, 
    expectApproxEqRel, 
    tolerance,
    ZERO_SLIPPAGE,
    ZERO_DEADLINE,
    setExplicitAccess
} from "../../helpers";
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory, 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory, 
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory,
    TokenPrices, TokenPrices__factory, 
    DummyDex, DummyDex__factory, 
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory, 
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory, 
} from "../../../../typechain";
import {
    deployGmx, GmxContracts, updateDistributionTime } from "./gmx-helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { GmxVaultType, encodeGlpHarvestParams, encodeGmxHarvestParams } from "../../../../scripts/deploys/helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { getSigners } from "../../signers";

// 0.001% max relative delta for time based reward checks - ie from BigNumber order of operations -> rounding
const MAX_REL_DELTA = tolerance(0.001);
const MIN_USDG = 1;

describe("Origami GMX Rewards Aggregator", async () => {
    let owner: Signer;
    let feeCollector: Signer;
    let alan: Signer;
    let bob: Signer;
    let operator: Signer;
    let compoundingFeeCollector: Signer;
    let gov: Signer;
    let govAddr: string;

    let dex: DummyDex;
    
    let origamiGmxManager: OrigamiGmxManager;
    let origamiGlpManager: OrigamiGmxManager;
    let gmxEarnAccount: OrigamiGmxEarnAccount;
    let primaryGlpEarnAccount: OrigamiGmxEarnAccount;
    let secondaryGlpEarnAccount: OrigamiGmxEarnAccount;
    let oGmxToken: OrigamiGmxInvestment;
    let oGlpToken: OrigamiGlpInvestment;

    let ovGmxToken: OrigamiInvestmentVault;
    let ovGlpToken: OrigamiInvestmentVault;
    let tokenPrices: TokenPrices;

    let origamiGmxRewardsAggr: OrigamiGmxRewardsAggregator;
    let origamiGlpRewardsAggr: OrigamiGmxRewardsAggregator;

    let gmxContracts: GmxContracts;

    // GMX Reward rates
    const ethPerSecond = BigNumber.from("41335970000000"); // 0.00004133597 ETH per second
    const esGmxPerSecond = BigNumber.from("20667989410000000"); // 0.02066798941 esGmx per second
    const vestingDuration = 86400;

    before( async () => {
        [owner, bob, alan, operator, feeCollector, compoundingFeeCollector, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });

    async function setup() {
        gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

        oGmxToken =  await new OrigamiGmxInvestment__factory(gov).deploy(govAddr);
        oGlpToken = await new OrigamiGlpInvestment__factory(gov).deploy(
            govAddr,
            gmxContracts.wrappedNativeToken.address,
        );

        // Set up DEX
        {
            dex = await new DummyDex__factory(gov).deploy(
                gmxContracts.gmxToken.address,
                gmxContracts.wrappedNativeToken.address,
                ethers.utils.parseEther("1"), // Use a price of 1 ETH == 100 GMX
                ethers.utils.parseEther("100"),
            );
            await gmxContracts.gmxToken.mint(dex.address, ethers.utils.parseEther("100000"));
            await gmxContracts.wrappedNativeToken.mint(dex.address,  ethers.utils.parseEther("100000"));
        }
        
        // Setup ovTokens
        {
            tokenPrices = await new TokenPrices__factory(gov).deploy(30);
            ovGmxToken = await new OrigamiInvestmentVault__factory(gov).deploy(govAddr, "ovGmxToken", "ovGmxToken", oGmxToken.address, tokenPrices.address, 500, vestingDuration);
            ovGlpToken = await new OrigamiInvestmentVault__factory(gov).deploy(govAddr, "ovGlpToken", "ovGlpToken", oGlpToken.address, tokenPrices.address, 500, vestingDuration);
        }
        
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
            await oGmxToken.setOrigamiGmxManager(origamiGmxManager.address)

            await setExplicitAccess(
                gmxEarnAccount,
                origamiGmxManager.address,
                ["harvestRewards", "handleRewards", "unstakeGmx", "stakeGmx"],
                true
            );
            await setExplicitAccess(
                origamiGmxManager,
                await operator.getAddress(),
                ["applyGmx"],
                true
            );
            await setExplicitAccess(
                origamiGmxManager,
                oGmxToken.address,
                ["investOGmx", "exitOGmx"],
                true
            );

            await oGmxToken.addMinter(origamiGmxManager.address);
        }

        // Setup the GLP Manager/Earn Account
        {
            primaryGlpEarnAccount = await deployUupsProxy(
                new OrigamiGmxEarnAccount__factory(gov), 
                [gmxContracts.gmxRewardRouter.address],
                govAddr,
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                await gmxContracts.glpRewardRouter.glpVester(),
                gmxContracts.stakedGlp.address,
            );
            secondaryGlpEarnAccount = await deployUupsProxy(
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
                primaryGlpEarnAccount.address,
                secondaryGlpEarnAccount.address
            );
            await oGlpToken.setOrigamiGlpManager(origamiGlpManager.address);

            await setExplicitAccess(
                primaryGlpEarnAccount,
                origamiGlpManager.address,
                ["unstakeAndRedeemGlp", "harvestRewards"],
                true
            );

            await setExplicitAccess(
                primaryGlpEarnAccount,
                await operator.getAddress(),
                ["mintAndStakeGlp"],
                true
            );

            await setExplicitAccess(
                secondaryGlpEarnAccount,
                origamiGlpManager.address,
                ["handleRewards", "mintAndStakeGlp"],
                true
            );

            await setExplicitAccess(
                origamiGlpManager,
                oGlpToken.address,
                ["investOGlp", "exitOGlp"],
                true
            );

            await oGmxToken.addMinter(origamiGlpManager.address);
        }

        // Setup the rewards aggregators
        {
            origamiGmxRewardsAggr = await new OrigamiGmxRewardsAggregator__factory(gov).deploy(
                govAddr,
                GmxVaultType.GMX,
                origamiGmxManager.address,
                origamiGlpManager.address,
                ovGmxToken.address,
                gmxContracts.wrappedNativeToken.address,
                dex.address,
                await compoundingFeeCollector.getAddress()
            );
            
            await setExplicitAccess(
                origamiGmxManager,
                origamiGmxRewardsAggr.address,
                ["harvestRewards"],
                true
            );
            await setExplicitAccess(
                origamiGlpManager,
                origamiGmxRewardsAggr.address,
                ["harvestRewards"],
                true
            );

            origamiGlpRewardsAggr = await new OrigamiGmxRewardsAggregator__factory(gov).deploy(
                govAddr,
                GmxVaultType.GLP,
                origamiGmxManager.address,
                origamiGlpManager.address,
                ovGlpToken.address,
                gmxContracts.wrappedNativeToken.address,
                dex.address,
                await compoundingFeeCollector.getAddress()
            );

            await setExplicitAccess(
                origamiGlpManager,
                origamiGlpRewardsAggr.address,
                ["harvestRewards"],
                true
            );

            // GLP aggregator not required for GMX Manager
            await origamiGmxManager.setRewardsAggregators(origamiGmxRewardsAggr.address, origamiGlpRewardsAggr.address);
            await origamiGlpManager.setRewardsAggregators(origamiGmxRewardsAggr.address, origamiGlpRewardsAggr.address);

            // Required so the aggregator can compound
            await setExplicitAccess(
                ovGmxToken,
                origamiGmxRewardsAggr.address,
                ["addPendingReserves"],
                true
            );
            await setExplicitAccess(
                ovGlpToken,
                origamiGlpRewardsAggr.address,
                ["addPendingReserves"],
                true
            );

            await setExplicitAccess(
                origamiGmxRewardsAggr,
                await operator.getAddress(),
                ["harvestRewards"],
                true
            );
            await setExplicitAccess(
                origamiGlpRewardsAggr,
                await operator.getAddress(),
                ["harvestRewards"],
                true
            );
        }

        // Allow gov to mint for staking purposes.
        {
            await oGmxToken.addMinter(gov.getAddress());
            await oGlpToken.addMinter(gov.getAddress());
        }

        return {
            gmxContracts,
            oGmxToken,
            oGlpToken,
            gmxEarnAccount,
            origamiGmxManager,
            primaryGlpEarnAccount,
            secondaryGlpEarnAccount,
            origamiGlpManager,
            origamiGmxRewardsAggr,
            origamiGlpRewardsAggr,
            dex,
        };
    };

    beforeEach(async () => {
        ({
            gmxContracts,
            oGmxToken,
            oGlpToken,
            gmxEarnAccount,
            origamiGmxManager,
            primaryGlpEarnAccount,
            secondaryGlpEarnAccount,
            origamiGlpManager,
            origamiGmxRewardsAggr,
            origamiGlpRewardsAggr,
            dex,
        } = await loadFixture(setup));
    });

    describe("Admin", async () => {
        it("Construction", async () => {           
            expect(await origamiGmxRewardsAggr.gmxManager()).eq(origamiGmxManager.address);
            expect(await origamiGlpRewardsAggr.gmxManager()).eq(origamiGmxManager.address);
            expect(await origamiGmxRewardsAggr.vaultType()).eq(GmxVaultType.GMX);
            expect(await origamiGlpRewardsAggr.vaultType()).eq(GmxVaultType.GLP);

            expect(await origamiGmxRewardsAggr.glpManager()).eq(origamiGlpManager.address);
            expect(await origamiGlpRewardsAggr.glpManager()).eq(origamiGlpManager.address);

            expect(await origamiGmxRewardsAggr.rewardTokensList()).deep.eq([gmxContracts.wrappedNativeToken.address, oGmxToken.address, oGlpToken.address]);
            expect(await origamiGlpRewardsAggr.rewardTokensList()).deep.eq([gmxContracts.wrappedNativeToken.address, oGmxToken.address, oGlpToken.address]);

            expect(await origamiGmxRewardsAggr.ovToken()).eq(ovGmxToken.address);
            expect(await origamiGlpRewardsAggr.ovToken()).eq(ovGlpToken.address);

            expect(await origamiGmxRewardsAggr.performanceFeeCollector()).eq(await compoundingFeeCollector.getAddress());
            expect(await origamiGlpRewardsAggr.performanceFeeCollector()).eq(await compoundingFeeCollector.getAddress());
        });

        const dummyHarvestParams = async (): Promise<string> => {
            const amount = 1000000;
            const quote = await oGmxToken.investQuote(amount, gmxContracts.gmxToken.address, 100, ZERO_DEADLINE);
            const params: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct = {
                nativeToGmxSwapData: dex.interface.encodeFunctionData("swapToGMX", [amount]),
                oGmxInvestQuoteData: quote.quoteData,
                addToReserveAmountPct: 10_000, // 100%
            };
            return encodeGmxHarvestParams(params);
        }

        it("admin", async () => {
            await shouldRevertInvalidAccess(origamiGmxRewardsAggr, origamiGmxRewardsAggr.connect(owner).setOrigamiGmxManagers(
                GmxVaultType.GMX,
                origamiGmxManager.address, 
                origamiGlpManager.address
            ));
            await shouldRevertInvalidAccess(origamiGmxRewardsAggr, origamiGmxRewardsAggr.connect(owner).setPerformanceFeeCollector(await alan.getAddress()));
            await shouldRevertInvalidAccess(origamiGmxRewardsAggr, origamiGmxRewardsAggr.connect(alan).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10));

            const harvestParams = await dummyHarvestParams();
            await shouldRevertInvalidAccess(origamiGmxRewardsAggr, origamiGmxRewardsAggr.connect(alan).harvestRewards(harvestParams));

            // Happy Paths
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(harvestParams))
                .to.revertedWith("ERC20: transfer amount exceeds balance");

            await origamiGmxRewardsAggr.connect(gov).setOrigamiGmxManagers(
                GmxVaultType.GMX,
                origamiGmxManager.address, 
                origamiGlpManager.address
            );
            await origamiGmxRewardsAggr.connect(gov).setPerformanceFeeCollector(await alan.getAddress());
            await expect(origamiGmxRewardsAggr.recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10))
                .to.revertedWith("ERC20: transfer amount exceeds balance");
        });

        it("Should setOrigamiGmxManagers()", async () => {
            const bobAddr = await bob.getAddress();
            const alanAddr = await alan.getAddress();
            await expect(origamiGmxRewardsAggr.setOrigamiGmxManagers(
                GmxVaultType.GMX,
                bobAddr, 
                alanAddr
            ))
                .to.emit(origamiGmxRewardsAggr, "OrigamiGmxManagersSet")
                .withArgs(GmxVaultType.GMX, bobAddr, alanAddr);

            expect(await origamiGmxRewardsAggr.vaultType()).eq(GmxVaultType.GMX);
            expect(await origamiGmxRewardsAggr.gmxManager()).eq(bobAddr);
            expect(await origamiGmxRewardsAggr.glpManager()).eq(alanAddr);
        });

        it("Should setPerformanceFeeCollector()", async () => {
            await expect(origamiGmxRewardsAggr.setPerformanceFeeCollector(await alan.getAddress()))
                .to.emit(origamiGmxRewardsAggr, "PerformanceFeeCollectorSet")
                .withArgs(await alan.getAddress());
            expect(await origamiGmxRewardsAggr.performanceFeeCollector()).eq(await alan.getAddress());
        });

        it("gov can recover tokens", async () => {
            const amount = 50;
            await gmxContracts.bnbToken.mint(origamiGmxRewardsAggr.address, amount);
            await recoverToken(gmxContracts.bnbToken, amount, origamiGmxRewardsAggr, owner);   

            // Can't recover any of the reward/transient reward tokens
            await expect(origamiGmxRewardsAggr.recoverToken(gmxContracts.wrappedNativeToken.address, owner.getAddress(), 1))
                .to.be.revertedWithCustomError(origamiGmxRewardsAggr, "InvalidToken")
                .withArgs(gmxContracts.wrappedNativeToken.address);
            await expect(origamiGmxRewardsAggr.recoverToken(gmxContracts.gmxToken.address, owner.getAddress(), 1))
                .to.be.revertedWithCustomError(origamiGmxRewardsAggr, "InvalidToken")
                .withArgs(gmxContracts.gmxToken.address);
            await expect(origamiGmxRewardsAggr.recoverToken(oGmxToken.address, owner.getAddress(), 1))
                .to.be.revertedWithCustomError(origamiGmxRewardsAggr, "InvalidToken")
                .withArgs(oGmxToken.address);
            await expect(origamiGmxRewardsAggr.recoverToken(oGlpToken.address, owner.getAddress(), 1))
                .to.be.revertedWithCustomError(origamiGmxRewardsAggr, "InvalidToken")
                .withArgs(oGlpToken.address);
        });

    });
    
    async function getOrigamiStakedGmxRatios(precision: BigNumber) {
        const stakedGmxFromGmxEarnAccount = await gmxContracts.stakedGmxTracker.depositBalances(gmxEarnAccount.address, gmxContracts.gmxToken.address);
        const stakedGmxFromGlpEarnAccount = await gmxContracts.stakedGmxTracker.depositBalances(primaryGlpEarnAccount.address, gmxContracts.gmxToken.address);
        const stakedGmxTotal = await gmxContracts.stakedGmxTracker.totalDepositSupply(gmxContracts.gmxToken.address);

        const stakedEsGmxFromGmxEarnAccount = await gmxContracts.stakedGmxTracker.depositBalances(gmxEarnAccount.address, gmxContracts.esGmxToken.address);
        const stakedEsGmxFromGlpEarnAccount = await gmxContracts.stakedGmxTracker.depositBalances(primaryGlpEarnAccount.address, gmxContracts.esGmxToken.address);
        const stakedEsGmxTotal = await gmxContracts.stakedGmxTracker.totalDepositSupply(gmxContracts.esGmxToken.address);

        const stakedMultPointsFromGmxEarnAccount = await gmxContracts.feeGmxTracker.depositBalances(gmxEarnAccount.address, gmxContracts.multiplierPointsToken.address);
        const stakedMultPointsFromGlpEarnAccount = await gmxContracts.feeGmxTracker.depositBalances(primaryGlpEarnAccount.address, gmxContracts.multiplierPointsToken.address);
        const stakedMultPointsTotal = await gmxContracts.feeGmxTracker.totalDepositSupply(gmxContracts.multiplierPointsToken.address);
        
        // esGMX rewards from staked GMX + staked esGMX
        const origamiEsGmxTotal = stakedGmxFromGmxEarnAccount.add(stakedGmxFromGlpEarnAccount).add(stakedEsGmxFromGmxEarnAccount).add(stakedEsGmxFromGlpEarnAccount);
        const allEsGmxTotal = stakedGmxTotal.add(stakedEsGmxTotal);
        const expectedEsGmxRatio = origamiEsGmxTotal.mul(precision).div(allEsGmxTotal);

        // ETH rewards from staked GMX + staked esGMX + staked mult points
        const origamiEthTotal = origamiEsGmxTotal.add(stakedMultPointsFromGmxEarnAccount).add(stakedMultPointsFromGlpEarnAccount);
        const allEthTotal = allEsGmxTotal.add(stakedMultPointsTotal);
        const expectedEthRatio = origamiEthTotal.mul(precision).div(allEthTotal);

        return {expectedEsGmxRatio, expectedEthRatio};
    }

    async function getOrigamiStakedGlpRatios(precision: BigNumber) {
        const totalDepositSupply = await gmxContracts.feeGlpTracker.totalDepositSupply(gmxContracts.glpToken.address);
        const primaryGlpRatio = (await gmxContracts.feeGlpTracker.depositBalances(primaryGlpEarnAccount.address, gmxContracts.glpToken.address))
            .mul(precision).div(totalDepositSupply);
        const secondaryGlpRatio = (await gmxContracts.feeGlpTracker.depositBalances(secondaryGlpEarnAccount.address, gmxContracts.glpToken.address))
            .mul(precision).div(totalDepositSupply);
        return {primaryGlpRatio, secondaryGlpRatio};
    }

    async function getAggregatorRewardBalances(aggregator: OrigamiGmxRewardsAggregator) {
        return {
            weth: await gmxContracts.wrappedNativeToken.balanceOf(aggregator.address),
            oGmx: await oGmxToken.balanceOf(aggregator.address),
            oGlp: await oGlpToken.balanceOf(aggregator.address),
        };
    }
    
    const harvestGlp = async () => {
        const harvestableRewards = await origamiGlpRewardsAggr.harvestableRewards();
        const balancesBefore = await getAggregatorRewardBalances(origamiGlpRewardsAggr);
        const ethAmountToInvest = harvestableRewards[0].add(harvestableRewards[1].div(100));
        const oGlpInvestQuote = await oGlpToken.investQuote(ethAmountToInvest, gmxContracts.wrappedNativeToken.address, 100, ZERO_DEADLINE);
        const oGmxExitQuote = await oGmxToken.exitQuote(harvestableRewards[1], gmxContracts.gmxToken.address, 100, ZERO_DEADLINE);
        const totalOGlpAvailable = oGlpInvestQuote.quoteData.expectedInvestmentAmount.add(balancesBefore.oGlp);
        const addToReserveAmountPct = 9_000;
        const glpHarvestParams: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct = {
            oGmxExitQuoteData: oGmxExitQuote.quoteData,
            gmxToNativeSwapData: dex.interface.encodeFunctionData("swapToWrappedNative", [harvestableRewards[1]]), // GMX -> wETH
            oGlpInvestQuoteData: oGlpInvestQuote.quoteData,
            addToReserveAmountPct: addToReserveAmountPct,
        };

        const fee = await ovGmxToken.performanceFee();
        if (fee.isZero()) {
            await expect(origamiGlpRewardsAggr.connect(operator).harvestRewards(encodeGlpHarvestParams(glpHarvestParams), {gasLimit:5000000}))
                .to.emit(origamiGlpRewardsAggr, "CompoundOvGlp")
                .to.not.emit(origamiGlpRewardsAggr, "PerformanceFeesCollected");
        } else {
            await expect(origamiGlpRewardsAggr.connect(operator).harvestRewards(encodeGlpHarvestParams(glpHarvestParams), {gasLimit:5000000}))
                .to.emit(origamiGlpRewardsAggr, "CompoundOvGlp")
                .to.emit(origamiGlpRewardsAggr, "PerformanceFeesCollected")
                .withArgs(oGlpToken.address, anyValue, await compoundingFeeCollector.getAddress());
        }

        const reservesAddedAfterFee = totalOGlpAvailable.mul(90).div(100).mul(10_000 - fee.toNumber()).div(10_000);
        return {totalOGlpAvailable, reservesAddedAfterFee};
    }

    const harvestGmx = async () => {
        const harvestableRewards = await origamiGmxRewardsAggr.harvestableRewards();
        const newGmx = harvestableRewards[0].mul(100); // GMX = ETH * 100
        const totalOGmxAvailable = newGmx.add(harvestableRewards[1]);
        const addToReserveAmountPct = 9_000;
        const oGmxInvestQuote = await oGmxToken.investQuote(newGmx, gmxContracts.gmxToken.address, 100, ZERO_DEADLINE);
        const gmxHarvestParams: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct = {
            nativeToGmxSwapData: dex.interface.encodeFunctionData("swapToGMX", [harvestableRewards[0]]), // wETH -> GMX,
            oGmxInvestQuoteData: oGmxInvestQuote.quoteData,
            addToReserveAmountPct: addToReserveAmountPct,
        };

        const fee = await ovGmxToken.performanceFee();
        if (fee.isZero()) {
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(encodeGmxHarvestParams(gmxHarvestParams), {gasLimit:5000000}))
                .to.emit(origamiGmxRewardsAggr, "CompoundOvGmx")
                .to.not.emit(origamiGmxRewardsAggr, "PerformanceFeesCollected");
        } else {
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(encodeGmxHarvestParams(gmxHarvestParams), {gasLimit:5000000}))
                .to.emit(origamiGmxRewardsAggr, "CompoundOvGmx")
                .to.emit(origamiGmxRewardsAggr, "PerformanceFeesCollected")
                .withArgs(oGmxToken.address, anyValue, await compoundingFeeCollector.getAddress());
        }

        const addToReserveAmount = totalOGmxAvailable.mul(90).div(100);
        const reservesAddedAfterFee = addToReserveAmount.mul(10_000 - fee.toNumber()).div(10_000);
        return {totalOGmxAvailable, addToReserveAmount, reservesAddedAfterFee};
    }

    describe("harvestableRewards", async () => {
        it("harvestableRewards - GLP only", async () => {
            // Nothing staked -> nothing earnt
            let harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
            expect(harvestableRewardsGlp).deep.eq([0, 0, 0]);

            const amount = ethers.utils.parseEther("250");

            // Origami applies some GLP
            const precision = ethers.utils.parseEther("1");
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, ZERO_ADDRESS, ZERO_DEADLINE);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, MIN_USDG, bobQuote.quoteData.minInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr, ZERO_ADDRESS, ZERO_DEADLINE);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, origamiQuote.quoteData.minInvestmentAmount);

                // Botstrap Origami with some GMX so it can harvest (need to convert oGMX -> GMX)
                const seedAmount = ethers.utils.parseEther("5000");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, seedAmount);
                await origamiGmxManager.connect(operator).applyGmx(seedAmount);
            }

            await mineForwardSeconds(86400);
            
            // GLP aggregator gets ~50% of staked GLP rewards
            harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
            const {primaryGlpRatio, } = await getOrigamiStakedGlpRatios(precision);
            expectApproxEqRel(harvestableRewardsGlp[0], ethPerSecond.mul(86402).mul(primaryGlpRatio).div(precision), MAX_REL_DELTA);
            expectApproxEqRel(harvestableRewardsGlp[1], esGmxPerSecond.mul(86402).mul(primaryGlpRatio).div(precision), MAX_REL_DELTA);
            expect(harvestableRewardsGlp[2]).eq(0); // No carry over oGlp yet

            // Harvest such that we stake the earnt esGMX
            const {totalOGlpAvailable, reservesAddedAfterFee} = await harvestGlp();           
            await mineForwardSeconds(86400);

            // GLP aggregator still only gets ~50% of staked GLP rewards (no extras from the staked esGMX)
            harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
            const {primaryGlpRatio: primaryGlpRatio2, } = await getOrigamiStakedGlpRatios(precision);

            const existingBalances = await getAggregatorRewardBalances(origamiGlpRewardsAggr);
            expectApproxEqRel(harvestableRewardsGlp[0].sub(existingBalances.weth), ethPerSecond.mul(86400).mul(primaryGlpRatio2).div(precision), MAX_REL_DELTA);
            expectApproxEqRel(harvestableRewardsGlp[1].sub(existingBalances.oGmx), esGmxPerSecond.mul(86400).mul(primaryGlpRatio2).div(precision), MAX_REL_DELTA);

            const feeCollectorBalanceAfter = await oGlpToken.balanceOf(compoundingFeeCollector.getAddress());

            // We left 10% of the amount in to carry over
            expect(harvestableRewardsGlp[2].add(reservesAddedAfterFee).add(feeCollectorBalanceAfter)).eq(totalOGlpAvailable);
        });

        it("harvestableRewards - GMX only", async () => {
            // Nothing staked -> nothing earnt
            let harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
            expect(harvestableRewardsGmx).deep.eq([0, 0, 0]);

            const amount = ethers.utils.parseEther("250");
            const precision = ethers.utils.parseEther("1");

            // Origami applies some GMX
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);
            
            // GMX aggregator gets 50% of staked GMX rewards
            harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
            let {expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedGmxRatios(precision);
            expectApproxEqRel(harvestableRewardsGmx[0], ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), MAX_REL_DELTA);
            expectApproxEqRel(harvestableRewardsGmx[1], esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), MAX_REL_DELTA);
            expect(harvestableRewardsGmx[2]).eq(0); // No oGLP

            await harvestGmx();
            await mineForwardSeconds(86400);

            // The GMX aggregator now gets an extra chunk of rewards from the staked esGMX, mult points earnt from the staked GMX
            harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
            ({expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedGmxRatios(precision));
            const existingBalances = await getAggregatorRewardBalances(origamiGmxRewardsAggr);
            expectApproxEqRel(harvestableRewardsGmx[0].sub(existingBalances.weth), ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), MAX_REL_DELTA);
            expectApproxEqRel(harvestableRewardsGmx[1].sub(existingBalances.oGmx), esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), MAX_REL_DELTA);
            expect(harvestableRewardsGmx[2]).eq(0); // No oGLP
        });

        it("harvestableRewards - GMX & GLP combined", async () => {
            // Nothing staked -> nothing earnt
            let harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
            expect(harvestableRewardsGlp).deep.eq([0, 0, 0]);
            let harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
            expect(harvestableRewardsGmx).deep.eq([0, 0, 0]);

            const amount = ethers.utils.parseEther("250000");

            // Origami applies some GMX and GLP
            const precision = ethers.utils.parseEther("1");
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, MIN_USDG, bobQuote.quoteData.minInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, origamiQuote.quoteData.minInvestmentAmount);

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);
            
            // Check GLP harvestableRewards
            {
                harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
                
                // GLP aggregator gets 50% of staked GLP rewards\
                const {primaryGlpRatio, } = await getOrigamiStakedGlpRatios(precision);
                expectApproxEqRel(harvestableRewardsGlp[0], ethPerSecond.mul(86405).mul(primaryGlpRatio).div(precision), MAX_REL_DELTA);
                expectApproxEqRel(harvestableRewardsGlp[1], esGmxPerSecond.mul(86405).mul(primaryGlpRatio).div(precision), MAX_REL_DELTA);
                expect(harvestableRewardsGlp[2]).eq(0);
            }
                
            // Check GMX harvestableRewards
            {
                harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();

                const { expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedGmxRatios(precision);
                expectApproxEqRel(harvestableRewardsGmx[0], ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), MAX_REL_DELTA);
                expectApproxEqRel(harvestableRewardsGmx[1], esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), MAX_REL_DELTA);
                expect(harvestableRewardsGlp[2]).eq(0);
            }

            await harvestGlp();
            await harvestGmx();
            await mineForwardSeconds(86400);

            // Now GLP aggregator still only gets 50% of staked GLP rewards
            {
                harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
                const existingGlpBalances = await getAggregatorRewardBalances(origamiGlpRewardsAggr);
                const {primaryGlpRatio, } = await getOrigamiStakedGlpRatios(precision);

                expectApproxEqRel(harvestableRewardsGlp[0].sub(existingGlpBalances.weth), ethPerSecond.mul(86400).mul(primaryGlpRatio).div(precision), MAX_REL_DELTA);
                expectApproxEqRel(harvestableRewardsGlp[1].sub(existingGlpBalances.oGmx), esGmxPerSecond.mul(86400).mul(primaryGlpRatio).div(precision), MAX_REL_DELTA);
                expect(harvestableRewardsGlp[2]).eq(existingGlpBalances.oGlp); // We left 10% of the amount in to carry over
            }

            // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
            // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
            {
                const { expectedEsGmxRatio, expectedEthRatio } = await getOrigamiStakedGmxRatios(precision);

                //   ~50% of staked GMX rewards
                //   staked esGMX+mult point rewards (from staked GMX rewards)
                //   staked esGMX+mult point rewards (from staked GLP rewards)
                harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
                const existingGmxBalances = await getAggregatorRewardBalances(origamiGmxRewardsAggr);
                expectApproxEqRel(harvestableRewardsGmx[0].sub(existingGmxBalances.weth), ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), MAX_REL_DELTA);
                expectApproxEqRel(harvestableRewardsGmx[1].sub(existingGmxBalances.oGmx), esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), MAX_REL_DELTA);
                expect(harvestableRewardsGmx[2]).eq(0); // No oGLP
            }
        });
    });
    
    describe("projectedRewardRates", async () => {
        it("projectedRewardRates - GMX & GLP combined", async () => {
            // Nothing staked -> nothing earnt
            let rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates(true);
            expect(rewardRatesGlp).deep.eq([0, 0, 0]);
            let rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates(true);
            expect(rewardRatesGmx).deep.eq([0, 0, 0]);

            const amount = ethers.utils.parseEther("25000");

            // Origami applies some GMX and GLP
            const precision = ethers.utils.parseEther("1");
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, MIN_USDG, bobQuote.quoteData.minInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, origamiQuote.quoteData.minInvestmentAmount);

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // Botstrap Origami with some GMX so it can harvest (need to convert oGMX -> GMX)
                const seedAmount = ethers.utils.parseEther("5000");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, seedAmount);
                await origamiGmxManager.connect(operator).applyGmx(seedAmount);
            }

            await mineForwardSeconds(86400);
            
            const removePerfFee = (bn: BigNumber) => bn.mul(95).div(100);

            // Check GLP
            {
                rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates(true);
                const {primaryGlpRatio, secondaryGlpRatio} = await getOrigamiStakedGlpRatios(precision);
                expectApproxEqRel(rewardRatesGlp[0], removePerfFee(ethPerSecond.mul(primaryGlpRatio.add(secondaryGlpRatio)).div(precision)), MAX_REL_DELTA);
                expectApproxEqRel(rewardRatesGlp[1], removePerfFee(esGmxPerSecond.mul(primaryGlpRatio).div(precision)), MAX_REL_DELTA);
            }

            // Check GMX
            {
                rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates(true);
                const { expectedEsGmxRatio, expectedEthRatio } = await getOrigamiStakedGmxRatios(precision);
                expectApproxEqRel(rewardRatesGmx[0], removePerfFee(ethPerSecond.mul(expectedEthRatio).div(precision)), MAX_REL_DELTA);
                expectApproxEqRel(rewardRatesGmx[1], removePerfFee(esGmxPerSecond.mul(expectedEsGmxRatio).div(precision)), MAX_REL_DELTA);
            }

            await harvestGlp();
            await harvestGmx();
            await mineForwardSeconds(86400);

            // Now GLP aggregator still only gets 50% of staked GLP rewards
            rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates(true);
            const {primaryGlpRatio, secondaryGlpRatio} = await getOrigamiStakedGlpRatios(precision);
            expectApproxEqRel(rewardRatesGlp[0], removePerfFee(ethPerSecond.mul(primaryGlpRatio.add(secondaryGlpRatio)).div(precision)), MAX_REL_DELTA);
            expectApproxEqRel(rewardRatesGlp[1], removePerfFee(esGmxPerSecond.mul(primaryGlpRatio).div(precision)), MAX_REL_DELTA);

            // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
            // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
            const { expectedEsGmxRatio, expectedEthRatio } = await getOrigamiStakedGmxRatios(precision);

            //   ~50% of staked GMX rewards
            //   staked esGMX+mult point rewards (from staked GMX rewards)
            //   staked esGMX+mult point rewards (from staked GLP rewards)
            rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates(true);
            expectApproxEqRel(rewardRatesGmx[0], removePerfFee(ethPerSecond.mul(expectedEthRatio).div(precision)), MAX_REL_DELTA);
            expectApproxEqRel(rewardRatesGmx[1], removePerfFee(esGmxPerSecond.mul(expectedEsGmxRatio).div(precision)), MAX_REL_DELTA);

            // projected rewards without taking out performance fees matches (slight rounding)
            const rewardRatesGmxNoFees = await origamiGmxRewardsAggr.projectedRewardRates(false);
            expectApproxEqRel(removePerfFee(rewardRatesGmxNoFees[0]), rewardRatesGmx[0], MAX_REL_DELTA);
            expectApproxEqRel(removePerfFee(rewardRatesGmxNoFees[1]), rewardRatesGmx[1], MAX_REL_DELTA);
        });
    });

    describe("harvestRewards", async () => {

        const harvestAndCheckGlp = async () => {
            const reservesBefore = (await ovGlpToken.vestedReserves()).add(await ovGlpToken.pendingReserves());
            const feeCollectorBalanceBefore = await oGlpToken.balanceOf(compoundingFeeCollector.getAddress());
            const {totalOGlpAvailable, reservesAddedAfterFee} = await harvestGlp();           
            const reservesAfter = (await ovGlpToken.vestedReserves()).add(await ovGlpToken.pendingReserves());
            const reservesAdded = reservesAfter.sub(reservesBefore);
            expect(reservesAdded).eq(reservesAddedAfterFee);

            // Dust left for eth/oGMX. 10% left in oGLP that wasn't added as reserves
            const balances = await getAggregatorRewardBalances(origamiGlpRewardsAggr);
            expect(balances.weth).lt(ethers.utils.parseEther("0.1"));
            expect(balances.oGmx).lt(ethers.utils.parseEther("0.1"));

            const feeCollectorBalanceAfter = await oGlpToken.balanceOf(compoundingFeeCollector.getAddress());
            const feesCollected = feeCollectorBalanceAfter.sub(feeCollectorBalanceBefore);
            expect(balances.oGlp.add(reservesAdded).add(feesCollected)).eq(totalOGlpAvailable);
        }

        const harvestAndCheckGmx = async () => {
            const reservesBefore = (await ovGmxToken.vestedReserves()).add(await ovGmxToken.pendingReserves());
            const feeCollectorBalanceBefore = await oGmxToken.balanceOf(compoundingFeeCollector.getAddress());
            const {totalOGmxAvailable, reservesAddedAfterFee} = await harvestGmx();
            const reservesAfter = (await ovGmxToken.vestedReserves()).add(await ovGmxToken.pendingReserves());
            const reservesAdded = reservesAfter.sub(reservesBefore);
            // Actual amount added might be slightly higher than estimated because of assumed slippage in WETH->GMX
            expectApproxEqRel(reservesAdded, reservesAddedAfterFee, MAX_REL_DELTA);

            // Dust left for eth/oGMX. 10% left in oGLP that wasn't added as reserves
            const balances = await getAggregatorRewardBalances(origamiGmxRewardsAggr);
            expect(balances.weth).lt(ethers.utils.parseEther("0.1"));

            const feeCollectorBalanceAfter = await oGmxToken.balanceOf(compoundingFeeCollector.getAddress());
            const feesCollected = feeCollectorBalanceAfter.sub(feeCollectorBalanceBefore);
            expectApproxEqRel(balances.oGmx.add(reservesAdded).add(feesCollected), totalOGmxAvailable, MAX_REL_DELTA);
            expect(balances.oGlp).eq(0);
        }

        it("harvestRewards - GLP only", async () => {
            {
                // Botstrap Origami with some GMX so it can harvest (need to convert oGMX -> GMX)
                const seedAmount = ethers.utils.parseEther("5000");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, seedAmount);
                await origamiGmxManager.connect(operator).applyGmx(seedAmount);
            }

            // Nothing staked -> nothing earnt
            {
                const harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
                expect(harvestableRewardsGlp).deep.eq([0,0,0]);
            }
            const amount = ethers.utils.parseEther("250");

            // Origami applies some GLP
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, MIN_USDG, bobQuote.quoteData.minInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, origamiQuote.quoteData.minInvestmentAmount);
            }

            await mineForwardSeconds(86400);
            await harvestAndCheckGlp();
            await mineForwardSeconds(86400);
            await harvestAndCheckGlp();
        });

        it("harvestRewards - GMX only", async () => {
            // Nothing staked -> nothing earnt
            {
                const harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
                expect(harvestableRewardsGmx).deep.eq([0,0,0]);
            }
            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);
            await harvestAndCheckGmx();
            await mineForwardSeconds(86400);
            await harvestAndCheckGmx();
        });

        it("harvestRewards - GMX 0%/100% fees", async () => {
            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX
            {
                await updateDistributionTime(gmxContracts);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            // 0% fees
            await ovGmxToken.setPerformanceFee(0);
            await mineForwardSeconds(86400);
            await harvestAndCheckGmx();

            // 1000% fees
            await ovGmxToken.setPerformanceFee(10_000);
            await mineForwardSeconds(86400);
            await harvestAndCheckGmx();
        });

        it("harvestRewards - GMX & GLP combined", async () => {
            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX and GLP
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, MIN_USDG, bobQuote.quoteData.minInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, MIN_USDG, origamiQuote.quoteData.minInvestmentAmount);

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);


                // Botstrap Origami with some GMX so it can harvest (need to convert oGMX -> GMX)
                const seedAmount = ethers.utils.parseEther("2000");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, seedAmount);
                await origamiGmxManager.connect(operator).applyGmx(seedAmount);
            }

            await mineForwardSeconds(86400);
            await harvestAndCheckGlp();
            await harvestAndCheckGmx();
            await mineForwardSeconds(86400);
            await harvestAndCheckGlp();
            await harvestAndCheckGmx();
        });
    });

    describe("ZeroEx Custom Error", async () => {
        it("A custom error thrown in the 0x proxy should be handled correctly", async () => {          
            // Origami applies some GMX
            {
                await updateDistributionTime(gmxContracts);
                const amount = ethers.utils.parseEther("250");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);

            const oGmxInvestQuote = await oGmxToken.investQuote(100, gmxContracts.gmxToken.address, 100, ZERO_DEADLINE);
            const gmxHarvestParams = encodeGmxHarvestParams({
                nativeToGmxSwapData: dex.interface.encodeFunctionData("revertCustom"), // throws a custom error
                oGmxInvestQuoteData: oGmxInvestQuote.quoteData,
                addToReserveAmountPct: 1_000,
            });
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(gmxHarvestParams))
                .to.revertedWithCustomError(dex, "InvalidParam");

            const gmxHarvestParams2 = encodeGmxHarvestParams({
                nativeToGmxSwapData: dex.interface.encodeFunctionData("revertNoMessage"), // UnknownSwapError
                oGmxInvestQuoteData: oGmxInvestQuote.quoteData,
                addToReserveAmountPct: 1_000,
            });
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(gmxHarvestParams2))
                .to.revertedWithCustomError(origamiGmxRewardsAggr, "UnknownSwapError")
                .withArgs("0x");
        });
    });
});
