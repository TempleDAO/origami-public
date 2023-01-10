import { ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { expect } from "chai";
import { 
    mineForwardSeconds,
    ZERO_ADDRESS, recoverToken, 
    shouldRevertNotOwner, shouldRevertPaused, slightlyGte, blockTimestamp, deployUupsProxy
} from "../../helpers";
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory, 
    MintableToken, MintableToken__factory, 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,
} from "../../../typechain";
import {
    deployGmx, GmxContracts, updateDistributionTime } from "./gmx-helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { GmxVaultType } from "../../../scripts/deploys/helpers";

describe("Origami GMX Rewards Aggregator", async () => {
    let owner: Signer;
    let feeCollector: Signer;
    let alan: Signer;
    let bob: Signer;
    let operator: Signer;

    let origamiGmxManager: OrigamiGmxManager;
    let origamiGlpManager: OrigamiGmxManager;
    let gmxEarnAccount: OrigamiGmxEarnAccount;
    let primaryGlpEarnAccount: OrigamiGmxEarnAccount;
    let secondaryGlpEarnAccount: OrigamiGmxEarnAccount;
    let oGmxToken: MintableToken;
    let oGlpToken: MintableToken;

    let origamiGmxRewardsAggr: OrigamiGmxRewardsAggregator;
    let origamiGlpRewardsAggr: OrigamiGmxRewardsAggregator;

    let origamiGlpRewardsDistributor: Signer;
    let origamiGmxRewardsDistributor: Signer;

    let gmxContracts: GmxContracts;

    // GMX Reward rates
    const ethPerSecond = BigNumber.from("41335970000000"); // 0.00004133597 ETH per second
    const esGmxPerSecond = BigNumber.from("20667989410000000"); // 0.02066798941 esGmx per second

    before( async () => {
        [owner, bob, alan, operator, feeCollector, origamiGlpRewardsDistributor, origamiGmxRewardsDistributor] = await ethers.getSigners();
    });

    async function setup() {
        gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

        oGmxToken = await new MintableToken__factory(owner).deploy("oGMX", "oGMX");
        oGlpToken = await new MintableToken__factory(owner).deploy("oGLP", "oGLP");

        // Setup the GMX Manager/Earn Account
        {
            gmxEarnAccount = await deployUupsProxy(
                new OrigamiGmxEarnAccount__factory(owner), 
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                await gmxContracts.gmxRewardRouter.gmxVester(),
                gmxContracts.stakedGlp.address,
            );
            origamiGmxManager = await new OrigamiGmxManager__factory(owner).deploy(
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                oGmxToken.address,
                oGlpToken.address,
                feeCollector.getAddress(),
                gmxEarnAccount.address,
                ZERO_ADDRESS,
            );
            await gmxEarnAccount.addOperator(origamiGmxManager.address);
            await gmxEarnAccount.addOperator(operator.getAddress());
            await origamiGmxManager.addOperator(operator.getAddress());
            await oGmxToken.addMinter(origamiGmxManager.address);
        }

        // Setup the GLP Manager/Earn Account
        {
            primaryGlpEarnAccount = await deployUupsProxy(
                new OrigamiGmxEarnAccount__factory(owner), 
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                await gmxContracts.glpRewardRouter.glpVester(),
                gmxContracts.stakedGlp.address,
            );
            secondaryGlpEarnAccount = await deployUupsProxy(
                new OrigamiGmxEarnAccount__factory(owner), 
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                await gmxContracts.glpRewardRouter.glpVester(),
                gmxContracts.stakedGlp.address,
            );
            origamiGlpManager = await new OrigamiGmxManager__factory(owner).deploy(
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                oGmxToken.address,
                oGlpToken.address,
                feeCollector.getAddress(),
                primaryGlpEarnAccount.address,
                secondaryGlpEarnAccount.address,
            );
            await primaryGlpEarnAccount.addOperator(origamiGlpManager.address);
            await primaryGlpEarnAccount.addOperator(operator.getAddress());
            await origamiGlpManager.addOperator(operator.getAddress());
            await oGmxToken.addMinter(origamiGlpManager.address);
            await oGlpToken.addMinter(origamiGlpManager.address);    
        }

        // Setup the rewards aggregators
        {
            origamiGmxRewardsAggr = await new OrigamiGmxRewardsAggregator__factory(owner).deploy(
                GmxVaultType.GMX,
                origamiGmxManager.address,
                origamiGlpManager.address,
                [
                    {
                        numerator: 3, 
                        denominator: 100,
                    },
                    {
                        numerator: 5, 
                        denominator: 100,
                    },
                ],
            );
            await origamiGmxRewardsAggr.setRewardsDistributor(origamiGmxRewardsDistributor.getAddress());

            origamiGlpRewardsAggr = await new OrigamiGmxRewardsAggregator__factory(owner).deploy(
                GmxVaultType.GLP,
                origamiGmxManager.address,
                origamiGlpManager.address,
                [
                    {
                        numerator: 3, 
                        denominator: 100,
                    },
                    {
                        numerator: 5, 
                        denominator: 100,
                    },
                ],
            );
            await origamiGlpRewardsAggr.setRewardsDistributor(origamiGlpRewardsDistributor.getAddress());

            // GLP aggregator not required for GMX Manager
            await origamiGmxManager.setRewardsAggregators(origamiGmxRewardsAggr.address, ZERO_ADDRESS);
            await origamiGlpManager.setRewardsAggregators(origamiGmxRewardsAggr.address, origamiGlpRewardsAggr.address);
        }

        // Allow owner to mint for staking purposes.
        {
            await oGmxToken.addMinter(owner.getAddress());
            await oGlpToken.addMinter(owner.getAddress());
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

            expect(await origamiGmxRewardsAggr.rewardTokensList()).deep.eq([gmxContracts.wrappedNativeToken.address, oGmxToken.address]);
            expect(await origamiGlpRewardsAggr.rewardTokensList()).deep.eq([gmxContracts.wrappedNativeToken.address, oGmxToken.address]);

            expect(await origamiGmxRewardsAggr.rewardsDistributor()).eq(await origamiGmxRewardsDistributor.getAddress());
            expect(await origamiGlpRewardsAggr.rewardsDistributor()).eq(await origamiGlpRewardsDistributor.getAddress());
        });

        it("admin", async () => {
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).setOrigamiGmxManagers(
                GmxVaultType.GMX,
                origamiGmxManager.address, 
                origamiGlpManager.address
            ));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).setRewardsDistributor(operator.getAddress()));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).setPerformanceFees([]));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).pause());
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).unpause());

            await expect(origamiGmxRewardsAggr.harvestRewards())
                .to.revertedWithCustomError(origamiGmxRewardsAggr, "OnlyRewardsDistributor")
                .withArgs(await owner.getAddress());

            // Happy Paths
            await origamiGmxRewardsAggr.setRewardsDistributor(origamiGmxRewardsDistributor.getAddress());
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
            await origamiGmxRewardsAggr.setOrigamiGmxManagers(
                GmxVaultType.GMX,
                origamiGmxManager.address, 
                origamiGlpManager.address
            );
            await expect(origamiGmxRewardsAggr.recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10))
                .to.revertedWith("ERC20: transfer amount exceeds balance");
            await origamiGmxRewardsAggr.pause();
            await origamiGmxRewardsAggr.unpause();
            await expect(origamiGmxRewardsAggr.setPerformanceFees([]))
                .to.revertedWithCustomError(origamiGmxRewardsAggr, "InvalidParam");
        });

        it("pause/unpause", async () => {
            // Pause the contract
            await origamiGmxRewardsAggr.pause();
    
            await shouldRevertPaused(origamiGmxRewardsAggr.harvestRewards());

            // Unpause the contract and check harvestRewards can be called again
            await origamiGmxRewardsAggr.unpause();
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
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

        it("Should setPerformanceFees()", async () => {
            const fees = [
                {
                    numerator: 13, 
                    denominator: 100,
                },
                {
                    numerator: 15, 
                    denominator: 100,
                },
            ];
            await expect(origamiGmxRewardsAggr.setPerformanceFees(fees))
                .to.emit(origamiGmxRewardsAggr, "PerformanceFeesSet");

            const pf1 = await origamiGmxRewardsAggr.performanceFeeRates(0);
            expect(pf1.numerator).eq(13);
            expect(pf1.denominator).eq(100);

            const pf2 = await origamiGmxRewardsAggr.performanceFeeRates(1);
            expect(pf2.numerator).eq(15);
            expect(pf2.denominator).eq(100);
        });

        it("Should setRewardsDistributor()", async () => {
            await expect(origamiGmxRewardsAggr.setRewardsDistributor(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(origamiGmxRewardsAggr, "InvalidAddress")
                .withArgs(ZERO_ADDRESS);

            const bobAddr = await bob.getAddress();
            await expect(origamiGmxRewardsAggr.setRewardsDistributor(bobAddr))
                .to.emit(origamiGmxRewardsAggr, "RewardsDistributorSet")
                .withArgs(bobAddr);

            expect(await origamiGmxRewardsAggr.rewardsDistributor()).eq(bobAddr);
        });

        it("owner can recover tokens", async () => {
            const amount = 50;
            await gmxContracts.bnbToken.mint(origamiGmxRewardsAggr.address, amount);
            await recoverToken(gmxContracts.bnbToken, amount, origamiGmxRewardsAggr, owner);   
        });

    });
    
    async function getOrigamiStakedRatios(amount: BigNumber, precision: BigNumber) {
        const stakedEsGmxFromGmxEarnAccount = await gmxContracts.stakedGmxTracker.depositBalances(gmxEarnAccount.address, gmxContracts.esGmxToken.address);
        const stakedEsGmxFromGlpEarnAccount = await gmxContracts.stakedGmxTracker.depositBalances(primaryGlpEarnAccount.address, gmxContracts.esGmxToken.address);
        const stakedMultPointsFromGmxEarnAccount = await gmxContracts.feeGmxTracker.depositBalances(gmxEarnAccount.address, gmxContracts.multiplierPointsToken.address);
        const stakedMultPointsFromGlpEarnAccount = await gmxContracts.feeGmxTracker.depositBalances(primaryGlpEarnAccount.address, gmxContracts.multiplierPointsToken.address);
        
        const totalGmxAndEsGmx = amount.add(stakedEsGmxFromGmxEarnAccount).add(stakedEsGmxFromGlpEarnAccount);
        const expectedEsGmxRatio = totalGmxAndEsGmx.mul(precision).div(totalGmxAndEsGmx.add(amount));

        const totalGmxEsGmxAndMultPoints = totalGmxAndEsGmx.add(stakedMultPointsFromGmxEarnAccount).add(stakedMultPointsFromGlpEarnAccount);
        const expectedEthRatio = totalGmxEsGmxAndMultPoints.mul(precision).div(totalGmxEsGmxAndMultPoints.add(amount));

        return {expectedEsGmxRatio, expectedEthRatio};
    }
    
    describe("harvestableRewards", async () => {
        it("harvestableRewards - GLP only", async () => {
            // Nothing staked -> nothing earnt
            let rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
            expect(rewardRatesGlp).deep.eq([0, 0]);

            const amount = ethers.utils.parseEther("250");

            // Origami applies some GLP
            const precision = ethers.utils.parseEther("1");
            let expectedRatio: BigNumber;
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.buyOGlpQuote(amount, gmxContracts.bnbToken.address);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, bobQuote.expectedUsdg, bobQuote.oGlpAmountOut
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.buyOGlpQuote(amount, tokenAddr);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, origamiQuote.expectedUsdg, origamiQuote.oGlpAmountOut, 0);

                expectedRatio = origamiQuote.oGlpAmountOut.mul(precision).div(origamiQuote.oGlpAmountOut.add(bobQuote.oGlpAmountOut));
            }

            await mineForwardSeconds(86400);
            
            // GLP aggregator gets ~50% of staked GLP rewards
            rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
            expect(slightlyGte(rewardRatesGlp[0], ethPerSecond.mul(86400).mul(expectedRatio).div(precision), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGlp[1], esGmxPerSecond.mul(86400).mul(expectedRatio).div(precision), 0.01)).eq(true);

            // Harvest such that we stake the earnt esGMX
            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards();
            await mineForwardSeconds(86400);

            // GLP aggregator still only gets ~50% of staked GLP rewards (no extras from the staked esGMX)
            rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
            expect(slightlyGte(rewardRatesGlp[0], ethPerSecond.mul(86400).mul(expectedRatio).div(precision), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGlp[1], esGmxPerSecond.mul(86400).mul(expectedRatio).div(precision), 1)).eq(true);
        });

        it("harvestableRewards - GMX only", async () => {
            // Nothing staked -> nothing earnt
            let rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
            expect(rewardRatesGmx).deep.eq([0, 0]);

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
            
            // GMX aggregator gets 50% of staked GMX rewards
            rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
            expect(slightlyGte(rewardRatesGmx[0], ethPerSecond.mul(86400/2), 0.00001)).eq(true);
            expect(slightlyGte(rewardRatesGmx[1], esGmxPerSecond.mul(86400/2), 0.01)).eq(true);

            // Harvest to stake esGMX/mult points
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
            await mineForwardSeconds(86400);

            // The GMX aggregator now gets an extra chunk of rewards from the staked esGMX, mult points earnt from the staked GMX
            rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
            expect(rewardRatesGmx[0]).gt(ethPerSecond.mul(86400/2*1.5));
            expect(rewardRatesGmx[1]).gt(esGmxPerSecond.mul(86400/2*1.5));
        });

        it("harvestableRewards - GMX & GLP combined", async () => {
            // Nothing staked -> nothing earnt
            let rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
            expect(rewardRatesGlp).deep.eq([0, 0]);
            let rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
            expect(rewardRatesGmx).deep.eq([0, 0]);

            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX and GLP
            const precision = ethers.utils.parseEther("1");
            let expectedRatio: BigNumber;
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.buyOGlpQuote(amount, gmxContracts.bnbToken.address);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, bobQuote.expectedUsdg, bobQuote.oGlpAmountOut
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.buyOGlpQuote(amount, tokenAddr);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, origamiQuote.expectedUsdg, origamiQuote.oGlpAmountOut, 0);

                expectedRatio = origamiQuote.oGlpAmountOut.mul(precision).div(origamiQuote.oGlpAmountOut.add(bobQuote.oGlpAmountOut));

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);
            
            {
                // Check then harvest the GLP rewards
                rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
                
                // GLP aggregator gets 50% of staked GLP rewards
                expect(slightlyGte(rewardRatesGlp[0], ethPerSecond.mul(86405).mul(expectedRatio).div(precision).sub(1), 0.005)).eq(true);
                expect(slightlyGte(rewardRatesGlp[1], esGmxPerSecond.mul(86405).mul(expectedRatio).div(precision).sub(1), 0.1)).eq(true);

                rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
                expect(slightlyGte(rewardRatesGmx[0], ethPerSecond.mul(86400/2), 0.001)).eq(true);
                expect(slightlyGte(rewardRatesGmx[1], esGmxPerSecond.mul(86400/2), 0.1)).eq(true);
            }

            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards();
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
            await mineForwardSeconds(86400);

            {
                // Now GLP aggregator still only gets 50% of staked GLP rewards
                rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
                expect(slightlyGte(ethPerSecond.mul(86405).mul(expectedRatio).div(precision), rewardRatesGlp[0], 0.01)).eq(true);
                expect(slightlyGte(esGmxPerSecond.mul(86405).mul(expectedRatio).div(precision), rewardRatesGlp[1], 0.1)).eq(true);

                // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
                // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
                const { expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedRatios(amount, precision);

                //   ~50% of staked GMX rewards
                //   staked esGMX+mult point rewards (from staked GMX rewards)
                //   staked esGMX+mult point rewards (from staked GLP rewards)
                rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
                expect(slightlyGte(ethPerSecond.mul(86405).mul(expectedEthRatio).div(precision), rewardRatesGmx[0], 0.005)).eq(true);
                expect(slightlyGte(esGmxPerSecond.mul(86405).mul(expectedEsGmxRatio).div(precision), rewardRatesGmx[1], 0.1)).eq(true);
            }
        });
    });
    
    describe("projectedRewardRates", async () => {
        it("projectedRewardRates - GMX & GLP combined", async () => {
            // Nothing staked -> nothing earnt
            let rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates();
            expect(rewardRatesGlp).deep.eq([0, 0]);
            let rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates();
            expect(rewardRatesGmx).deep.eq([0, 0]);

            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX and GLP
            const precision = ethers.utils.parseEther("1");
            let expectedRatio: BigNumber;
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.buyOGlpQuote(amount, gmxContracts.bnbToken.address);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, bobQuote.expectedUsdg, bobQuote.oGlpAmountOut
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.buyOGlpQuote(amount, tokenAddr);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, origamiQuote.expectedUsdg, origamiQuote.oGlpAmountOut, 0);

                expectedRatio = origamiQuote.oGlpAmountOut.mul(precision).div(origamiQuote.oGlpAmountOut.add(bobQuote.oGlpAmountOut));

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);
            
            // GLP aggregator gets 50% of staked GLP rewards
            rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates();
            expect(slightlyGte(rewardRatesGlp[0], ethPerSecond.mul(expectedRatio).div(precision).mul(97).div(100), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGlp[1], esGmxPerSecond.mul(expectedRatio).div(precision).mul(95).div(100), 0.01)).eq(true);

            // GLP aggregator gets 50% of staked GMX rewards
            rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates();
            expect(slightlyGte(rewardRatesGmx[0], ethPerSecond.div(2).mul(97).div(100), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGmx[1], esGmxPerSecond.div(2).mul(95).div(100), 0.01)).eq(true);

            // Harvest on both
            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards();
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
            await mineForwardSeconds(86400);

            // Now GLP aggregator still only gets 50% of staked GLP rewards
            rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates();
            expect(slightlyGte(rewardRatesGlp[0], ethPerSecond.mul(expectedRatio).div(precision).mul(97).div(100), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGlp[1], esGmxPerSecond.mul(expectedRatio).div(precision).mul(95).div(100), 1)).eq(true);

            // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
            // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
            const { expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedRatios(amount, precision);

            //   ~50% of staked GMX rewards
            //   staked esGMX+mult point rewards (from staked GMX rewards)
            //   staked esGMX+mult point rewards (from staked GLP rewards)
            rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates();
            expect(slightlyGte(rewardRatesGmx[0], ethPerSecond.mul(expectedEthRatio).div(precision).mul(97).div(100), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGmx[1], esGmxPerSecond.mul(expectedEsGmxRatio).div(precision).mul(95).div(100), 1)).eq(true);
        });
    });

    describe("harvestRewards", async () => {
        it("harvestRewards - GLP only", async () => {
            const distributorAddr = await origamiGlpRewardsDistributor.getAddress();

            // Nothing staked -> nothing earnt           
            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards();
            let cumGlpEth = await gmxContracts.wrappedNativeToken.balanceOf(distributorAddr);
            let cumGlpOGmx = await oGmxToken.balanceOf(distributorAddr);
            expect(cumGlpEth).eq(cumGlpOGmx).eq(0);

            const amount = ethers.utils.parseEther("250");

            // Origami applies some GLP
            const precision = ethers.utils.parseEther("1");
            let expectedRatio: BigNumber;
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.buyOGlpQuote(amount, gmxContracts.bnbToken.address);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, bobQuote.expectedUsdg, bobQuote.oGlpAmountOut
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.buyOGlpQuote(amount, tokenAddr);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, origamiQuote.expectedUsdg, origamiQuote.oGlpAmountOut, 0);

                expectedRatio = origamiQuote.oGlpAmountOut.mul(precision).div(origamiQuote.oGlpAmountOut.add(bobQuote.oGlpAmountOut));
            }

            await mineForwardSeconds(86400);
            
            // GLP aggregator gets ~50% of staked GLP rewards
            let rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards();
            cumGlpEth = await gmxContracts.wrappedNativeToken.balanceOf(distributorAddr);
            cumGlpOGmx = await oGmxToken.balanceOf(distributorAddr);
            // Add one second worth of rewards since it just got mined.
            expect(slightlyGte(cumGlpEth, rewardRatesGlp[0].add(ethPerSecond.mul(expectedRatio).div(precision)), 0.0001)).eq(true);
            expect(slightlyGte(cumGlpOGmx, rewardRatesGlp[1].add(esGmxPerSecond.mul(expectedRatio).div(precision)), 0.1)).eq(true);

            await mineForwardSeconds(86400);

            // GLP aggregator still only gets ~50% of staked GLP rewards (no extras from the staked esGMX)
            rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards({gasLimit:5000000});
            const cumGlpEth2 = await gmxContracts.wrappedNativeToken.balanceOf(distributorAddr);
            const cumGlpOGmx2 = await oGmxToken.balanceOf(distributorAddr);
            expect(slightlyGte(cumGlpEth2, cumGlpEth.add(rewardRatesGlp[0]).add(ethPerSecond.mul(expectedRatio).div(precision)), 0.0001)).eq(true);
            expect(slightlyGte(cumGlpOGmx2, cumGlpOGmx.add(rewardRatesGlp[1]).add(esGmxPerSecond.mul(expectedRatio).div(precision)), 0.1)).eq(true);
        });

        it("harvestRewards - GMX only", async () => {
            const distributorAddr = await origamiGmxRewardsDistributor.getAddress();

            // Nothing staked -> nothing earnt           
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
            let cumGmxEth = await gmxContracts.wrappedNativeToken.balanceOf(distributorAddr);
            let cumGmxOGmx = await oGmxToken.balanceOf(distributorAddr);
            expect(cumGmxEth).eq(cumGmxOGmx).eq(0);

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
            
            // GMX aggregator gets 50% of staked GMX rewards
            let rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards();
            cumGmxEth = await gmxContracts.wrappedNativeToken.balanceOf(distributorAddr);
            cumGmxOGmx = await oGmxToken.balanceOf(distributorAddr)
            // Add one second worth of rewards since it just got mined.
            expect(slightlyGte(cumGmxEth, rewardRatesGmx[0].add(ethPerSecond.div(2)), 0.0001)).eq(true);
            expect(slightlyGte(cumGmxOGmx, rewardRatesGmx[1].add(esGmxPerSecond.div(2)), 0.1)).eq(true);

            await mineForwardSeconds(86400);

            // The GMX aggregator now gets an extra chunk of rewards from the staked esGMX, mult points earnt from the staked GMX
            rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards({gasLimit:5000000});
            expect(rewardRatesGmx[0]).gt(ethPerSecond.mul(86400/2*1.5));
            expect(rewardRatesGmx[1]).gt(esGmxPerSecond.mul(86400/2*1.5));
            const cumGmxEth2 = await gmxContracts.wrappedNativeToken.balanceOf(distributorAddr);
            const cumGmxOGmx2 = await oGmxToken.balanceOf(distributorAddr);
            expect(slightlyGte(cumGmxEth2, cumGmxEth.add(rewardRatesGmx[0]).add(ethPerSecond.div(2)), 0.0001)).eq(true);
            expect(slightlyGte(cumGmxOGmx2, cumGmxOGmx.add(rewardRatesGmx[1]).add(esGmxPerSecond.div(2)), 0.1)).eq(true);
        });

        it("harvestRewards - GMX & GLP combined", async () => {
            // Nothing staked -> nothing earnt
            await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards({gasLimit:5000000});
            await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards({gasLimit:5000000});
            let cumGlpEthForGlp = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsDistributor.getAddress());
            let cumGlpOGmxForGlp = await oGmxToken.balanceOf(origamiGlpRewardsDistributor.getAddress());
            let cumGlpEthForGmx = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsDistributor.getAddress());
            let cumGlpOGmxForGmx = await oGmxToken.balanceOf(origamiGmxRewardsDistributor.getAddress());
            expect(cumGlpEthForGlp).eq(cumGlpOGmxForGlp).eq(cumGlpEthForGmx).eq(cumGlpOGmxForGmx).eq(0);

            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX and GLP
            const precision = ethers.utils.parseEther("1");
            let expectedRatio: BigNumber;
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.buyOGlpQuote(amount, gmxContracts.bnbToken.address);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, bobQuote.expectedUsdg, bobQuote.oGlpAmountOut
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.buyOGlpQuote(amount, tokenAddr);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, origamiQuote.expectedUsdg, origamiQuote.oGlpAmountOut, 0);

                expectedRatio = origamiQuote.oGlpAmountOut.mul(precision).div(origamiQuote.oGlpAmountOut.add(bobQuote.oGlpAmountOut));

                // Bob buys GMX directly (outside of origami)
                await gmxContracts.gmxToken.mint(bob.getAddress(), amount);
                await gmxContracts.gmxToken.connect(bob).approve(gmxContracts.stakedGmxTracker.address, amount);
                await gmxContracts.gmxRewardRouter.connect(bob).stakeGmx(amount);

                // GMX ==> GMX Manager
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, amount);
                await origamiGmxManager.connect(operator).applyGmx(amount);
            }

            await mineForwardSeconds(86400);

            {
                // Check then harvest the GLP rewards
                let blockTs = await blockTimestamp();
                const rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
                await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards({gasLimit:5000000});
                
                // This should equal 1 second normally - but sometimes hardhat/ganache increments the block by more for some reason.
                let elapsedSecs = (await blockTimestamp()) - blockTs;

                cumGlpEthForGlp = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsDistributor.getAddress());
                cumGlpOGmxForGlp = await oGmxToken.balanceOf(origamiGlpRewardsDistributor.getAddress());

                // The harvested balance of rewards in the distributor should equal (+1 or 2 secs of rewards)
                // the harvestable amount
                expect(slightlyGte(cumGlpEthForGlp, rewardRatesGlp[0].add(ethPerSecond.mul(elapsedSecs).mul(expectedRatio).div(precision)), 0.0001)).eq(true);
                expect(slightlyGte(cumGlpOGmxForGlp, rewardRatesGlp[1].add(esGmxPerSecond.mul(elapsedSecs).mul(expectedRatio).div(precision)), 0.1)).eq(true);

                // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
                // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
                const { expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedRatios(amount, precision);

                // Do the same for the GMX rewards
                blockTs = await blockTimestamp();
                let rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
                await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards({gasLimit:5000000});
                elapsedSecs = (await blockTimestamp()) - blockTs;

                cumGlpEthForGmx = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsDistributor.getAddress());
                cumGlpOGmxForGmx = await oGmxToken.balanceOf(origamiGmxRewardsDistributor.getAddress());
                expect(slightlyGte(
                    rewardRatesGmx[0].add(ethPerSecond.mul(elapsedSecs).mul(expectedEthRatio).div(precision)), cumGlpEthForGmx, 0.0001),
                ).eq(true);
                expect(slightlyGte(
                    rewardRatesGmx[1].add(esGmxPerSecond.mul(elapsedSecs).mul(expectedEsGmxRatio).div(precision)), cumGlpOGmxForGmx, 0.1)
                ).eq(true);
            }

            await mineForwardSeconds(86400);
            
            {
                let blockTs = await blockTimestamp();
                const rewardRatesGlp = await origamiGlpRewardsAggr.harvestableRewards();
                await origamiGlpRewardsAggr.connect(origamiGlpRewardsDistributor).harvestRewards({gasLimit:5000000});
                let elapsedSecs = (await blockTimestamp()) - blockTs;

                // Now GLP aggregator still only gets 50% of staked GLP rewards
                const cumGlpEthForGlp2 = await gmxContracts.wrappedNativeToken.balanceOf(origamiGlpRewardsDistributor.getAddress());
                const cumGlpOGmxForGlp2 = await oGmxToken.balanceOf(origamiGlpRewardsDistributor.getAddress());
                expect(slightlyGte(cumGlpEthForGlp2, 
                    cumGlpEthForGlp.add(rewardRatesGlp[0]).add(ethPerSecond.mul(elapsedSecs).mul(expectedRatio).div(precision)).sub(1), 0.001)
                ).eq(true);
                expect(slightlyGte(cumGlpOGmxForGlp2, 
                    cumGlpOGmxForGlp.add(rewardRatesGlp[1]).add(esGmxPerSecond.mul(elapsedSecs).mul(expectedRatio).div(precision)).sub(1), 0.1)
                ).eq(true);
                
                // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
                // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
                const { expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedRatios(amount, precision);

                //   ~50% of staked GMX rewards
                //   staked esGMX+mult point rewards (from staked GMX rewards)
                //   staked esGMX+mult point rewards (from staked GLP rewards)
                blockTs = await blockTimestamp();
                const rewardRatesGmx = await origamiGmxRewardsAggr.harvestableRewards();
                await origamiGmxRewardsAggr.connect(origamiGmxRewardsDistributor).harvestRewards({gasLimit:5000000});
                elapsedSecs = (await blockTimestamp()) - blockTs;

                const cumGlpEthForGmx2 = await gmxContracts.wrappedNativeToken.balanceOf(origamiGmxRewardsDistributor.getAddress());
                const cumGlpOGmxForGmx2 = await oGmxToken.balanceOf(origamiGmxRewardsDistributor.getAddress());
                expect(slightlyGte(
                    cumGlpEthForGmx.add(rewardRatesGmx[0]).add(ethPerSecond.mul(elapsedSecs).mul(expectedEthRatio).div(precision)), cumGlpEthForGmx2, 0.0001)
                ).eq(true);
                expect(slightlyGte(
                    cumGlpOGmxForGmx.add(rewardRatesGmx[1]).add(esGmxPerSecond.mul(elapsedSecs).mul(expectedEsGmxRatio).div(precision)), cumGlpOGmxForGmx2, 0.2)
                ).eq(true);
            }
        });
    });
});
