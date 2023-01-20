import { ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { expect } from "chai";
import { 
    mineForwardSeconds,
    ZERO_ADDRESS, recoverToken, 
    shouldRevertNotOwner, slightlyGte, deployUupsProxy, slightlyLte, shouldRevertNotOperator
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
} from "../../../typechain";
import {
    decodeGlpUnderlyingInvestQuoteData,
    deployGmx, GmxContracts, updateDistributionTime } from "./gmx-helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { GmxVaultType, encodeGlpHarvestParams, encodeGmxHarvestParams } from "../../../scripts/deploys/helpers";

describe("Origami GMX Rewards Aggregator", async () => {
    let owner: Signer;
    let feeCollector: Signer;
    let alan: Signer;
    let bob: Signer;
    let operator: Signer;

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

    before( async () => {
        [owner, bob, alan, operator, feeCollector] = await ethers.getSigners();
    });

    async function setup() {
        gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

        oGmxToken =  await new OrigamiGmxInvestment__factory(owner).deploy();
        oGlpToken = await new OrigamiGlpInvestment__factory(owner).deploy(
            gmxContracts.wrappedNativeToken.address,
        );

        // Set up DEX
        {
            dex = await new DummyDex__factory(owner).deploy(
                gmxContracts.gmxToken.address,
                gmxContracts.wrappedNativeToken.address,
                ethers.utils.parseEther("1"), // Use a price of 1 ETH == 100 GMX
                ethers.utils.parseEther("100"),
            )
            await gmxContracts.gmxToken.mint(dex.address, ethers.utils.parseEther("100000"));
            await gmxContracts.wrappedNativeToken.mint(dex.address,  ethers.utils.parseEther("100000"));
        }
        
        // Setup ovTokens
        {
            tokenPrices = await new TokenPrices__factory(owner).deploy(30);
            ovGmxToken = await new OrigamiInvestmentVault__factory(owner).deploy("ovGmxToken", "ovGmxToken", oGmxToken.address, tokenPrices.address, 5);
            ovGlpToken = await new OrigamiInvestmentVault__factory(owner).deploy("ovGlpToken", "ovGlpToken", oGlpToken.address, tokenPrices.address, 5);
        }
        
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
            await oGmxToken.setOrigamiGmxManager(origamiGmxManager.address)

            await gmxEarnAccount.addOperator(origamiGmxManager.address);
            await gmxEarnAccount.addOperator(operator.getAddress());
            await origamiGmxManager.addOperator(operator.getAddress());
            await origamiGmxManager.addOperator(oGmxToken.address);
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
                secondaryGlpEarnAccount.address
            );
            await oGlpToken.setOrigamiGlpManager(origamiGlpManager.address);
            await primaryGlpEarnAccount.addOperator(origamiGlpManager.address);
            await secondaryGlpEarnAccount.addOperator(origamiGlpManager.address);
            await primaryGlpEarnAccount.addOperator(operator.getAddress());
            await origamiGlpManager.addOperator(operator.getAddress());
            await origamiGlpManager.addOperator(oGlpToken.address);
            await oGmxToken.addMinter(origamiGlpManager.address);
            await oGlpToken.addMinter(origamiGlpManager.address);    
        }

        // Setup the rewards aggregators
        {
            origamiGmxRewardsAggr = await new OrigamiGmxRewardsAggregator__factory(owner).deploy(
                GmxVaultType.GMX,
                origamiGmxManager.address,
                origamiGlpManager.address,
                ovGmxToken.address,
                gmxContracts.wrappedNativeToken.address,
                dex.address,
            );
            await origamiGmxManager.addOperator(origamiGmxRewardsAggr.address);
            await origamiGlpManager.addOperator(origamiGmxRewardsAggr.address);

            origamiGlpRewardsAggr = await new OrigamiGmxRewardsAggregator__factory(owner).deploy(
                GmxVaultType.GLP,
                origamiGmxManager.address,
                origamiGlpManager.address,
                ovGlpToken.address,
                gmxContracts.wrappedNativeToken.address,
                dex.address,
            );
            await origamiGlpManager.addOperator(origamiGlpRewardsAggr.address);

            // GLP aggregator not required for GMX Manager
            await origamiGmxManager.setRewardsAggregators(origamiGmxRewardsAggr.address, ZERO_ADDRESS);
            await origamiGlpManager.setRewardsAggregators(origamiGmxRewardsAggr.address, origamiGlpRewardsAggr.address);

            // Required so the aggregator can compound
            await ovGmxToken.addOperator(origamiGmxRewardsAggr.address);
            await ovGlpToken.addOperator(origamiGlpRewardsAggr.address);

            await origamiGmxRewardsAggr.addOperator(operator.getAddress());
            await origamiGlpRewardsAggr.addOperator(operator.getAddress());
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
        });

        const dummyHarvestParams = async (): Promise<string> => {
            const amount = 1000000;
            const quote = await oGmxToken.investQuote(amount, gmxContracts.gmxToken.address);
            const params: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct = {
                nativeToGmxSwapData: dex.interface.encodeFunctionData("swapToGMX", [amount]),
                oGmxInvestQuoteData: quote.quoteData,
                oGmxInvestSlippageBps: 100, // 1%
                addToReserveAmount: amount,
            };
            return encodeGmxHarvestParams(params);
        }

        it("admin", async () => {
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).setOrigamiGmxManagers(
                GmxVaultType.GMX,
                origamiGmxManager.address, 
                origamiGlpManager.address
            ));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).addOperator(await operator.getAddress()));
            await shouldRevertNotOwner(origamiGmxRewardsAggr.connect(alan).removeOperator(await operator.getAddress()));

            const harvestParams = await dummyHarvestParams();
            await shouldRevertNotOperator(origamiGmxRewardsAggr.harvestRewards(harvestParams), origamiGmxRewardsAggr, owner);

            // Happy Paths
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(harvestParams))
                .to.revertedWith("ERC20: transfer amount exceeds balance");

            await origamiGmxRewardsAggr.setOrigamiGmxManagers(
                GmxVaultType.GMX,
                origamiGmxManager.address, 
                origamiGlpManager.address
            );
            await expect(origamiGmxRewardsAggr.recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10))
                .to.revertedWith("ERC20: transfer amount exceeds balance");

            await origamiGmxRewardsAggr.addOperator(await operator.getAddress());
            await origamiGmxRewardsAggr.removeOperator(await operator.getAddress());
        });

        it("should add operator", async() => {
            // addOperator() test covered by operators.ts
        });

        it("should remove operator", async() => {
            // removeOperator() test covered by operators.ts
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

        it("owner can recover tokens", async () => {
            const amount = 50;
            await gmxContracts.bnbToken.mint(origamiGmxRewardsAggr.address, amount);
            await recoverToken(gmxContracts.bnbToken, amount, origamiGmxRewardsAggr, owner);   
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
        const oGlpInvestQuote = await oGlpToken.investQuote(ethAmountToInvest, gmxContracts.wrappedNativeToken.address);
        const oGmxExitQuote = await oGmxToken.exitQuote(harvestableRewards[1], gmxContracts.gmxToken.address);
        const totalOGlpAvailable = oGlpInvestQuote.quoteData.expectedInvestmentAmount.add(balancesBefore.oGlp);
        const addToReserveAmount = totalOGlpAvailable.mul(90).div(100);
        const glpHarvestParams: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct = {
            oGmxExitQuoteData: oGmxExitQuote.quoteData,
            gmxToNativeSwapData: dex.interface.encodeFunctionData("swapToWrappedNative", [harvestableRewards[1]]), // GMX -> wETH
            oGlpInvestQuoteData: oGlpInvestQuote.quoteData,
            oGmxExitSlippageBps: 100, // 1%
            oGlpInvestSlippageBps: 100, // 1%
            addToReserveAmount: addToReserveAmount,
        };

        await expect(origamiGlpRewardsAggr.connect(operator).harvestRewards(encodeGlpHarvestParams(glpHarvestParams)))
            .to.emit(origamiGlpRewardsAggr, "CompoundOvGlp");

        return {totalOGlpAvailable, addToReserveAmount};
    }

    const harvestGmx = async () => {
        const harvestableRewards = await origamiGmxRewardsAggr.harvestableRewards();
        const newGmx = harvestableRewards[0].mul(100); // GMX = ETH * 100
        const totalOGmxAvailable = newGmx.add(harvestableRewards[1]);
        const addToReserveAmount = totalOGmxAvailable.mul(90).div(100);
        const oGmxInvestQuote = await oGmxToken.investQuote(newGmx, gmxContracts.gmxToken.address);
        const gmxHarvestParams = encodeGmxHarvestParams({
            nativeToGmxSwapData: dex.interface.encodeFunctionData("swapToGMX", [harvestableRewards[0]]), // wETH -> GMX,
            oGmxInvestQuoteData: oGmxInvestQuote.quoteData,
            oGmxInvestSlippageBps: 100, // 1%
            addToReserveAmount: addToReserveAmount,
        });

        await origamiGmxRewardsAggr.connect(operator).harvestRewards(gmxHarvestParams);
        return {totalOGmxAvailable, addToReserveAmount};
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
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address);
                const decodedQuote = decodeGlpUnderlyingInvestQuoteData(bobQuote.quoteData.underlyingInvestmentQuoteData);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, decodedQuote.expectedUsdg, bobQuote.quoteData.expectedInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr);
                const decodedOrigamiQuote = decodeGlpUnderlyingInvestQuoteData(origamiQuote.quoteData.underlyingInvestmentQuoteData);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, decodedOrigamiQuote.expectedUsdg, origamiQuote.quoteData.expectedInvestmentAmount, 0);

                // Botstrap Origami with some GMX so it can harvest (need to convert oGMX -> GMX)
                const seedAmount = ethers.utils.parseEther("5000");
                await gmxContracts.gmxToken.mint(origamiGmxManager.address, seedAmount);
                await origamiGmxManager.connect(operator).applyGmx(seedAmount);
            }

            await mineForwardSeconds(86400);
            
            // GLP aggregator gets ~50% of staked GLP rewards
            harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
            const {primaryGlpRatio, } = await getOrigamiStakedGlpRatios(precision);
            expect(slightlyGte(harvestableRewardsGlp[0], ethPerSecond.mul(86402).mul(primaryGlpRatio).div(precision), 0.0001)).eq(true);
            expect(slightlyGte(harvestableRewardsGlp[1], esGmxPerSecond.mul(86402).mul(primaryGlpRatio).div(precision), 0.01)).eq(true);
            expect(harvestableRewardsGlp[2]).eq(0); // No carry over oGlp yet

            // Harvest such that we stake the earnt esGMX
            const {totalOGlpAvailable, addToReserveAmount} = await harvestGlp();           
            await mineForwardSeconds(86400);

            // GLP aggregator still only gets ~50% of staked GLP rewards (no extras from the staked esGMX)
            harvestableRewardsGlp = await origamiGlpRewardsAggr.harvestableRewards();
            const {primaryGlpRatio: primaryGlpRatio2, } = await getOrigamiStakedGlpRatios(precision);

            const existingBalances = await getAggregatorRewardBalances(origamiGlpRewardsAggr);
            expect(slightlyGte(harvestableRewardsGlp[0].sub(existingBalances.weth), ethPerSecond.mul(86400).mul(primaryGlpRatio2).div(precision), 0.0001)).eq(true);
            expect(slightlyGte(harvestableRewardsGlp[1].sub(existingBalances.oGmx), esGmxPerSecond.mul(86400).mul(primaryGlpRatio2).div(precision), 0.0001)).eq(true);
            // We left 10% of the amount in to carry over
            expect(harvestableRewardsGlp[2].add(addToReserveAmount)).eq(totalOGlpAvailable);
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
            expect(slightlyGte(harvestableRewardsGmx[0], ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), 0.00001)).eq(true);
            expect(slightlyGte(harvestableRewardsGmx[1], esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), 0.01)).eq(true);
            expect(harvestableRewardsGmx[2]).eq(0); // No oGLP

            await harvestGmx();
            await mineForwardSeconds(86400);

            // The GMX aggregator now gets an extra chunk of rewards from the staked esGMX, mult points earnt from the staked GMX
            harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();
            ({expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedGmxRatios(precision));
            const existingBalances = await getAggregatorRewardBalances(origamiGmxRewardsAggr);
            expect(slightlyGte(harvestableRewardsGmx[0].sub(existingBalances.weth), ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), 0.0001)).eq(true);
            expect(slightlyGte(harvestableRewardsGmx[1].sub(existingBalances.oGmx), esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), 0.0001)).eq(true);
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
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address);
                const decodedQuote = decodeGlpUnderlyingInvestQuoteData(bobQuote.quoteData.underlyingInvestmentQuoteData);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, decodedQuote.expectedUsdg, bobQuote.quoteData.expectedInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr);
                const decodedOrigamiQuote = decodeGlpUnderlyingInvestQuoteData(origamiQuote.quoteData.underlyingInvestmentQuoteData);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, decodedOrigamiQuote.expectedUsdg, origamiQuote.quoteData.expectedInvestmentAmount, 0);

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
                expect(slightlyGte(harvestableRewardsGlp[0], ethPerSecond.mul(86405).mul(primaryGlpRatio).div(precision), 0.001)).eq(true);
                expect(slightlyGte(harvestableRewardsGlp[1], esGmxPerSecond.mul(86405).mul(primaryGlpRatio).div(precision), 0.001)).eq(true);
                expect(harvestableRewardsGlp[2]).eq(0);
            }
                
            // Check GMX harvestableRewards
            {
                harvestableRewardsGmx = await origamiGmxRewardsAggr.harvestableRewards();

                const { expectedEsGmxRatio, expectedEthRatio} = await getOrigamiStakedGmxRatios(precision);
                expect(slightlyGte(harvestableRewardsGmx[0], ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), 0.001)).eq(true);
                expect(slightlyGte(harvestableRewardsGmx[1], esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), 0.001)).eq(true);
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

                expect(slightlyGte(harvestableRewardsGlp[0].sub(existingGlpBalances.weth), ethPerSecond.mul(86400).mul(primaryGlpRatio).div(precision), 0.0001)).eq(true);
                expect(slightlyGte(harvestableRewardsGlp[1].sub(existingGlpBalances.oGmx), esGmxPerSecond.mul(86400).mul(primaryGlpRatio).div(precision), 0.0001)).eq(true);
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
                expect(slightlyGte(harvestableRewardsGmx[0].sub(existingGmxBalances.weth), ethPerSecond.mul(86400).mul(expectedEthRatio).div(precision), 0.0001)).eq(true);
                expect(slightlyGte(harvestableRewardsGmx[1].sub(existingGmxBalances.oGmx), esGmxPerSecond.mul(86400).mul(expectedEsGmxRatio).div(precision), 0.0001)).eq(true);
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
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address);
                const decodedQuote = decodeGlpUnderlyingInvestQuoteData(bobQuote.quoteData.underlyingInvestmentQuoteData);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, decodedQuote.expectedUsdg, bobQuote.quoteData.expectedInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr);
                const decodedOrigamiQuote = decodeGlpUnderlyingInvestQuoteData(origamiQuote.quoteData.underlyingInvestmentQuoteData);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, decodedOrigamiQuote.expectedUsdg, origamiQuote.quoteData.expectedInvestmentAmount, 0);

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
                expect(slightlyGte(rewardRatesGlp[0], removePerfFee(ethPerSecond.mul(primaryGlpRatio.add(secondaryGlpRatio)).div(precision)), 0.0001)).eq(true);
                expect(slightlyGte(rewardRatesGlp[1], removePerfFee(esGmxPerSecond.mul(primaryGlpRatio).div(precision)), 0.0001)).eq(true);
            }

            // Check GMX
            {
                rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates(true);
                const { expectedEsGmxRatio, expectedEthRatio } = await getOrigamiStakedGmxRatios(precision);
                expect(slightlyGte(rewardRatesGmx[0], removePerfFee(ethPerSecond.mul(expectedEthRatio).div(precision)), 0.0001)).eq(true);
                expect(slightlyGte(rewardRatesGmx[1], removePerfFee(esGmxPerSecond.mul(expectedEsGmxRatio).div(precision)), 0.0001)).eq(true);
            }

            await harvestGlp();
            await harvestGmx();
            await mineForwardSeconds(86400);

            // Now GLP aggregator still only gets 50% of staked GLP rewards
            rewardRatesGlp = await origamiGlpRewardsAggr.projectedRewardRates(true);
            const {primaryGlpRatio, secondaryGlpRatio} = await getOrigamiStakedGlpRatios(precision);
            expect(slightlyGte(rewardRatesGlp[0], removePerfFee(ethPerSecond.mul(primaryGlpRatio.add(secondaryGlpRatio)).div(precision)), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGlp[1], removePerfFee(esGmxPerSecond.mul(primaryGlpRatio).div(precision)), 0.0001)).eq(true);

            // But the GMX aggregator gets rewards based off it's total GMX+esGMX 
            // from both the GMX and GLP manager vs the rest of the pool (bob had 50% originally)
            const { expectedEsGmxRatio, expectedEthRatio } = await getOrigamiStakedGmxRatios(precision);

            //   ~50% of staked GMX rewards
            //   staked esGMX+mult point rewards (from staked GMX rewards)
            //   staked esGMX+mult point rewards (from staked GLP rewards)
            rewardRatesGmx = await origamiGmxRewardsAggr.projectedRewardRates(true);
            expect(slightlyGte(rewardRatesGmx[0], removePerfFee(ethPerSecond.mul(expectedEthRatio).div(precision)), 0.0001)).eq(true);
            expect(slightlyGte(rewardRatesGmx[1], removePerfFee(esGmxPerSecond.mul(expectedEsGmxRatio).div(precision)), 0.0001)).eq(true);

            // projected rewards without taking out performance fees matches (slight rounding)
            const rewardRatesGmxNoFees = await origamiGmxRewardsAggr.projectedRewardRates(false);
            expect(slightlyLte(removePerfFee(rewardRatesGmxNoFees[0]), rewardRatesGmx[0], BigNumber.from(1))).eq(true);
            expect(slightlyLte(removePerfFee(rewardRatesGmxNoFees[1]), rewardRatesGmx[1], BigNumber.from(1))).eq(true);
        });
    });

    describe("harvestRewards", async () => {

        const harvestAndCheckGlp = async () => {
            const reservesBefore = await ovGlpToken.totalReserves();
            const {totalOGlpAvailable, addToReserveAmount} = await harvestGlp();           
            const reservesAfter = await ovGlpToken.totalReserves();
            const reservesAdded = reservesAfter.sub(reservesBefore);
            expect(reservesAdded).eq(addToReserveAmount);

            // Dust left for eth/oGMX. 10% left in oGLP that wasn't added as reserves
            const balances = await getAggregatorRewardBalances(origamiGlpRewardsAggr);
            expect(balances.weth).lt(ethers.utils.parseEther("0.1"));
            expect(balances.oGmx).lt(ethers.utils.parseEther("0.1"));
            expect(balances.oGlp.add(reservesAdded)).eq(totalOGlpAvailable);
        }

        const harvestAndCheckGmx = async () => {
            const reservesBefore = await ovGmxToken.totalReserves();
            const {totalOGmxAvailable, addToReserveAmount} = await harvestGmx();
            const reservesAfter = await ovGmxToken.totalReserves();
            const reservesAdded = reservesAfter.sub(reservesBefore);
            expect(reservesAdded).eq(addToReserveAmount);

            // Dust left for eth/oGMX. 10% left in oGLP that wasn't added as reserves
            const balances = await getAggregatorRewardBalances(origamiGmxRewardsAggr);
            expect(balances.weth).lt(ethers.utils.parseEther("0.1"));
            expect(slightlyGte(balances.oGmx.add(reservesAdded), totalOGmxAvailable, 0.1));
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
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address);
                const decodedQuote = decodeGlpUnderlyingInvestQuoteData(bobQuote.quoteData.underlyingInvestmentQuoteData);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, decodedQuote.expectedUsdg, bobQuote.quoteData.expectedInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr);
                const decodedOrigamiQuote = decodeGlpUnderlyingInvestQuoteData(origamiQuote.quoteData.underlyingInvestmentQuoteData);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, decodedOrigamiQuote.expectedUsdg, origamiQuote.quoteData.expectedInvestmentAmount, 0);
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

        it("harvestRewards - GMX & GLP combined", async () => {
            const amount = ethers.utils.parseEther("250");

            // Origami applies some GMX and GLP
            const precision = ethers.utils.parseEther("1");
            {
                await updateDistributionTime(gmxContracts);

                // Bob buys the same amount GLP directly (not via Origami)
                await gmxContracts.bnbToken.mint(bob.getAddress(), amount);
                await gmxContracts.bnbToken.connect(bob).approve(await gmxContracts.glpRewardRouter.glpManager(), amount);
                const bobQuote = await origamiGmxManager.investOGlpQuote(amount, gmxContracts.bnbToken.address);
                const decodedQuote = decodeGlpUnderlyingInvestQuoteData(bobQuote.quoteData.underlyingInvestmentQuoteData);
                await gmxContracts.glpRewardRouter.connect(bob).mintAndStakeGlp(
                    gmxContracts.bnbToken.address, amount, decodedQuote.expectedUsdg, bobQuote.quoteData.expectedInvestmentAmount
                );

                // GLP ==> GLP Manager
                const tokenAddr = gmxContracts.bnbToken.address;
                await gmxContracts.bnbToken.mint(primaryGlpEarnAccount.address, amount);
                const origamiQuote = await origamiGlpManager.investOGlpQuote(amount, tokenAddr);
                const decodedOrigamiQuote = decodeGlpUnderlyingInvestQuoteData(origamiQuote.quoteData.underlyingInvestmentQuoteData);
                await primaryGlpEarnAccount.connect(operator).mintAndStakeGlp(amount, tokenAddr, decodedOrigamiQuote.expectedUsdg, origamiQuote.quoteData.expectedInvestmentAmount, 0);

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

            const oGmxInvestQuote = await oGmxToken.investQuote(100, gmxContracts.gmxToken.address);
            const gmxHarvestParams = encodeGmxHarvestParams({
                nativeToGmxSwapData: dex.interface.encodeFunctionData("revertCustom"), // throws a custom error
                oGmxInvestQuoteData: oGmxInvestQuote.quoteData,
                oGmxInvestSlippageBps: 100, // 1%
                addToReserveAmount: 100,
            });
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(gmxHarvestParams))
                .to.revertedWithCustomError(dex, "InvalidParam");

            const gmxHarvestParams2 = encodeGmxHarvestParams({
                nativeToGmxSwapData: dex.interface.encodeFunctionData("revertNoMessage"), // UnknownSwapError
                oGmxInvestQuoteData: oGmxInvestQuote.quoteData,
                oGmxInvestSlippageBps: 100, // 1%
                addToReserveAmount: 100,
            });
            await expect(origamiGmxRewardsAggr.connect(operator).harvestRewards(gmxHarvestParams2))
                .to.revertedWithCustomError(origamiGmxRewardsAggr, "UnknownSwapError")
                .withArgs("0x");
        });
    });
});
