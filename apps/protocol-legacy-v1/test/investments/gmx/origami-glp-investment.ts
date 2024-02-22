import { ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { expect } from "chai";
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory,
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory, 
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory, IOrigamiGmxManager, 
    MintableToken, DummyMintableToken__factory, 
} from "../../../typechain";
import { addDefaultGlpLiquidity, deployGmx, GmxContracts } from "./gmx-helpers";
import { 
    applySlippage, 
    BN_ZERO, 
    deployUupsProxy, 
    EmptyBytes, 
    expectBalancesChangeBy, 
    mineForwardSeconds, 
    ONE_ETH, 
    recoverToken, 
    shouldRevertNotGov,
    ZERO_ADDRESS,
    ZERO_DEADLINE,
    ZERO_SLIPPAGE
} from "../../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getSigners } from "../../signers";

describe("Origami GLP Investment", async () => {
    let owner: Signer;
    let alan: Signer;
    let bob: Signer;
    let fred: Signer;
    let feeCollector: Signer;
    let dailyTransferKeeper: Signer;
    let gov: Signer;
    let govAddr: string;
    let origamiGlpManager: OrigamiGmxManager;
    let oGMX: OrigamiGmxInvestment;  
    let oGLP: OrigamiGlpInvestment;
    let gmxContracts: GmxContracts;
    let randoErc20: MintableToken;

    // GMX Reward rates
    const ethPerSecond = BigNumber.from("41335970000000"); // 0.00004133597 ETH per second
    const esGmxPerSecond = BigNumber.from("20667989410000000"); // 0.02066798941 esGmx per second

    let primaryEarnAccount: OrigamiGmxEarnAccount;
    let secondaryEarnAccount: OrigamiGmxEarnAccount;

    before( async () => {
        [owner, alan, bob, fred, feeCollector, dailyTransferKeeper, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });
    
    async function setup() {
        gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

        oGMX = await new OrigamiGmxInvestment__factory(gov).deploy(govAddr);
        
        oGLP = await new OrigamiGlpInvestment__factory(gov).deploy(
            govAddr,
            gmxContracts.wrappedNativeToken.address,
        );

        primaryEarnAccount = await deployUupsProxy(
            new OrigamiGmxEarnAccount__factory(gov), 
            [gmxContracts.gmxRewardRouter.address],
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            await gmxContracts.gmxRewardRouter.glpVester(),
            gmxContracts.stakedGlp.address,
        );

        secondaryEarnAccount = await deployUupsProxy(
            new OrigamiGmxEarnAccount__factory(gov), 
            [gmxContracts.gmxRewardRouter.address],
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            await gmxContracts.gmxRewardRouter.glpVester(),
            gmxContracts.stakedGlp.address,
        );

        origamiGlpManager = await new OrigamiGmxManager__factory(gov).deploy(
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            oGMX.address,
            oGLP.address,
            feeCollector.getAddress(),
            primaryEarnAccount.address,
            secondaryEarnAccount.address,
        );

        await oGLP.setOrigamiGlpManager(origamiGlpManager.address);

        // The Investment is added as an operator such that it can exit oGlp
        await origamiGlpManager.addOperator(oGLP.address);

        // The Investment/manager are added as operators such that they can stake/unstake GMX
        await primaryEarnAccount.addOperator(origamiGlpManager.address);

        // The Investment/manager are added as operators such that they can stake/unstake GMX
        await secondaryEarnAccount.addOperator(origamiGlpManager.address);
        await secondaryEarnAccount.addOperator(oGLP.address);

        // Allow the 'daily transfer keeper' to move staked LP from secondary -> primary earn account
        await secondaryEarnAccount.addOperator(dailyTransferKeeper.getAddress());

        // The origamiGlpManager mints/burns oGlp tokens
        await oGLP.addMinter(govAddr);

        await addDefaultGlpLiquidity(bob, gmxContracts);

        randoErc20 = await new DummyMintableToken__factory(gov).deploy(govAddr, "rando", "rando");
        await randoErc20.addMinter(govAddr);
        await randoErc20.mint(govAddr, ONE_ETH);

        return {
            gmxContracts,
            primaryEarnAccount,
            secondaryEarnAccount,
            origamiGlpManager,
            oGLP,
            randoErc20,
        }
    }

    beforeEach(async () => {
        ({
            gmxContracts,
            primaryEarnAccount,
            secondaryEarnAccount,
            origamiGlpManager,
            oGLP,
            randoErc20,
        } = await loadFixture(setup));
    });

    it("constructor", async () => {
        expect(await oGLP.origamiGlpManager()).eq(origamiGlpManager.address);
        expect(await oGLP.baseToken()).eq(gmxContracts.glpToken.address);
        expect(await oGLP.wrappedNativeToken()).eq(gmxContracts.wrappedNativeToken.address);
        expect(await oGLP.apiVersion()).eq("0.1.0");
    });

    it("admin", async () => {
        await shouldRevertNotGov(oGLP, oGLP.connect(owner).setOrigamiGlpManager(ZERO_ADDRESS));
        await shouldRevertNotGov(oGLP, oGLP.connect(owner).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10));

        // Happy paths
        await oGLP.connect(gov).setOrigamiGlpManager(origamiGlpManager.address);
        await expect(oGLP.connect(gov).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10))
            .to.revertedWith("ERC20: transfer amount exceeds balance");
    });

    it("areInvestmentsPaused/areExitsPaused should be correct", async () => {
        // Not paused by default
        expect(await oGLP.areInvestmentsPaused()).eq(false);
        expect(await oGLP.areExitsPaused()).eq(false);

        // Buy and immediately transfer transfer staked GLP so the secondary earn account is paused
        const glpAmount = ethers.utils.parseEther("10");
        {
            const tokenAddr = gmxContracts.bnbToken.address;
            const investAmount = ethers.utils.parseEther("100");
            const investQuote = await oGLP.investQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await gmxContracts.bnbToken.mint(fred.getAddress(), investAmount);
            await gmxContracts.bnbToken.connect(fred).approve(oGLP.address, investAmount);
            await oGLP.connect(fred).investWithToken(investQuote.quoteData);
            await secondaryEarnAccount.connect(dailyTransferKeeper).transferStakedGlpOrPause(glpAmount, primaryEarnAccount.address);
            expect(await secondaryEarnAccount.glpInvestmentsPaused()).eq(true);
        }

        // Now GLP investments are paused, exits are still open
        expect(await oGLP.areInvestmentsPaused()).eq(true);
        expect(await oGLP.areExitsPaused()).eq(false);

        // Wait for the cooldown and do the transfer so glp investments are unpaused
        {
            await mineForwardSeconds(15*60);
            await secondaryEarnAccount.connect(dailyTransferKeeper).transferStakedGlpOrPause(glpAmount, primaryEarnAccount.address);
        }

        // Unpaused again
        expect(await oGLP.areInvestmentsPaused()).eq(false);
        expect(await oGLP.areExitsPaused()).eq(false);
        
        // Finally set to be paused on the gmx manager.
        const paused: IOrigamiGmxManager.PausedStruct = {
            glpInvestmentsPaused: true,
            gmxInvestmentsPaused: true,
            glpExitsPaused: true,
            gmxExitsPaused: true,
        };
        await origamiGlpManager.setPauser(govAddr, true);
        await origamiGlpManager.setPaused(paused);
        expect(await oGLP.areInvestmentsPaused()).eq(true);
        expect(await oGLP.areExitsPaused()).eq(true);
    });

    it("gov can recover tokens", async () => {           
        const amount = 50;
        await gmxContracts.bnbToken.mint(oGLP.address, amount);
        await recoverToken(gmxContracts.bnbToken, amount, oGLP, owner);   
    });

    it("Should only receive eth from the wrappedNative token", async () => {
        await expect(
            owner.sendTransaction({
                to: oGLP.address,
                value: ethers.utils.parseEther("0.5")
            })
        ).to.revertedWithCustomError(oGLP, "InvalidSender").withArgs(await owner.getAddress());

        // Receiving ETH from the wrappedNative token is tested below
    });

    it("Should set gmx manager", async () => {
        await expect(oGLP.setOrigamiGlpManager(ZERO_ADDRESS))
            .to.be.revertedWithCustomError(oGLP, "InvalidAddress")
            .withArgs(ZERO_ADDRESS);

        const origamiGlpManager2 = await new OrigamiGmxManager__factory(owner).deploy(
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            oGMX.address,
            oGLP.address,
            feeCollector.getAddress(),
            primaryEarnAccount.address,
            secondaryEarnAccount.address,
        );
        await expect(oGLP.setOrigamiGlpManager(origamiGlpManager2.address))
            .to.emit(oGLP, "OrigamiGlpManagerSet")
            .withArgs(origamiGlpManager2.address);

        expect(await oGLP.origamiGlpManager()).eq(origamiGlpManager2.address);
    });

    it("Should get accepted tokens", async () => {
        const tokens = await oGLP.acceptedInvestTokens();
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

        // exit tokens are the same as invest tokens
        expect(await oGLP.acceptedExitTokens()).deep.eq(tokens);
    });
    
    describe("Invest oGLP", async () => {
        it("Invest oGLP Quote", async () => {
            const amount = ethers.utils.parseEther("500");          
            const quote = await oGLP.investQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

            await expect(oGLP.investQuote(0, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                .to.be.revertedWithCustomError(oGLP, "ExpectedNonZero");
            await expect(oGLP.investQuote(10, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                .to.be.revertedWithCustomError(origamiGlpManager, "InvalidToken")
                .withArgs(gmxContracts.gmxToken.address);

            // 500x300 - 35bps fee
            const expectedGlp = ethers.utils.parseEther("149475")
            expect(quote.quoteData.fromToken).eq(gmxContracts.bnbToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedGlp);
            expect(quote.quoteData.minInvestmentAmount).eq(expectedGlp);
            expect(quote.investFeeBps).deep.eq([35]);
        });

        it("Invest oGLP Quote - with slippage", async () => {
            const amount = ethers.utils.parseEther("500");          
            const slippage = 100; // 1%
            const quote = await oGLP.investQuote(amount, gmxContracts.bnbToken.address, slippage, ZERO_DEADLINE);

            // 500x300 - 35bps fee
            const expectedGlp = ethers.utils.parseEther("149475")
            expect(quote.quoteData.fromToken).eq(gmxContracts.bnbToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(slippage);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedGlp);
            expect(quote.quoteData.minInvestmentAmount).eq(applySlippage(expectedGlp, slippage));
            expect(quote.investFeeBps).deep.eq([35]);
        });

        it("Invest oGLP with token", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;

            // 0 amount errors
            {
                const manualQuote = {
                    ...(await oGLP.investQuote(100, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                    fromTokenAmount: BN_ZERO,
                };
                await expect(oGLP.investWithToken(manualQuote))
                    .to.be.revertedWithCustomError(origamiGlpManager, "ExpectedNonZero");
            }

            // Non-glp token errors
            {
                const manualQuote = {
                    ...(await oGLP.investQuote(100, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                    fromToken: randoErc20.address,
                };

                await randoErc20.approve(oGLP.address, 100);
                await expect(oGLP.investWithToken(manualQuote))
                    .to.be.revertedWithCustomError(origamiGlpManager, "InvalidToken")
                    .withArgs(randoErc20.address)
            }

            const amount = ethers.utils.parseEther("100");
            const quote = await oGLP.investQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.investWithToken(quote.quoteData))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            await gmxContracts.bnbToken.mint(alan.getAddress(), amount);
            await gmxContracts.bnbToken.connect(alan).approve(oGLP.address, amount);

            // 1 more than the GLP quote amount fails
            {
                const manualQuote = {
                    ...quote.quoteData,
                    expectedInvestmentAmount: quote.quoteData.expectedInvestmentAmount.add(1),
                    minInvestmentAmount: quote.quoteData.expectedInvestmentAmount.add(1),
                };
                await expect(oGLP.connect(alan).investWithToken(manualQuote))
                    .to.be.revertedWith("GlpManager: insufficient GLP output");
            }

            // Successfully bought
            await expect(oGLP.connect(alan).investWithToken(quote.quoteData))
                .to.emit(oGLP, "Invested")
                .withArgs(await alan.getAddress(), amount, tokenAddr, quote.quoteData.expectedInvestmentAmount);

            // No bnb left now
            expect(await gmxContracts.bnbToken.balanceOf(alan.getAddress())).eq(0);
    
            // Alan has the oGlp
            expect(await oGLP.balanceOf(alan.getAddress())).eq(quote.quoteData.expectedInvestmentAmount);

            // The primary earn account doesn't have the staked GLP
            expect(await gmxContracts.stakedGlpTracker.balanceOf(primaryEarnAccount.address)).eq(0);

            // The secondary earn account DOES have the staked GLP
            expect(await gmxContracts.stakedGlpTracker.balanceOf(secondaryEarnAccount.address)).eq(quote.quoteData.expectedInvestmentAmount);
        });

        it("Invest oGLP with staked GLP", async () => {
            const tokenAddr = gmxContracts.stakedGlp.address;

            const amount = ethers.utils.parseEther("100");
            const quote = await oGLP.investQuote(amount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.investWithToken(quote.quoteData))
                .to.be.revertedWith("StakedGlp: transfer amount exceeds allowance");

            // Alan first invests GLP directly, rather than via Origami
            let glpAmount;
            {
                await gmxContracts.bnbToken.mint(alan.getAddress(), amount);
                await gmxContracts.bnbToken.connect(alan).approve(gmxContracts.glpRewardRouter.glpManager(), amount);
                await gmxContracts.glpRewardRouter.connect(alan).mintAndStakeGlp(gmxContracts.bnbToken.address, amount, 0, 0);
                glpAmount = await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress());
            }

            // Need to wait for the 15min cooldown first
            await gmxContracts.stakedGlp.connect(alan).approve(oGLP.address, glpAmount);
            const quote2 = await oGLP.investQuote(glpAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.connect(alan).investWithToken(quote2.quoteData))
                .to.revertedWith("StakedGlp: cooldown duration not yet passed");

            await mineForwardSeconds(15*60);

            // Successfully bought
            await expect(oGLP.connect(alan).investWithToken(quote2.quoteData))
                .to.emit(oGLP, "Invested")
                .withArgs(await alan.getAddress(), glpAmount, gmxContracts.stakedGlp.address, glpAmount);

            // Alan has no bnb or staked GLP left now
            expect(await gmxContracts.bnbToken.balanceOf(alan.getAddress())).eq(0);
            expect(await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress())).eq(0);

            // Alan has the oGlp
            expect(await oGLP.balanceOf(alan.getAddress())).eq(glpAmount);

            // The earn account has the staked GLP
            expect(await gmxContracts.stakedGlpTracker.balanceOf(primaryEarnAccount.address)).eq(glpAmount);
        });

        it("Invest oGLP with ETH", async () => {
            const tokenAddr = ZERO_ADDRESS;
            const quoteData = (await oGLP.investQuote(100, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            const manualQuote = {
                ...quoteData,
                fromTokenAmount: BN_ZERO,
            };
            await expect(oGLP.investWithNative(manualQuote, {value:0}))
                .to.be.revertedWithCustomError(oGLP, "ExpectedNonZero");

            await expect(oGLP.investWithNative(quoteData, {value:0}))
                .to.be.revertedWithCustomError(oGLP, "InvalidAmount")
                .withArgs(ZERO_ADDRESS, 0);

            const manualQuote2 = {
                ...quoteData,
                fromToken: gmxContracts.bnbToken.address,
            };
            await expect(oGLP.investWithNative(manualQuote2, {value:100}))
                .to.be.revertedWithCustomError(oGLP, "InvalidToken")
                .withArgs(gmxContracts.bnbToken.address);

            const amount = ethers.utils.parseEther("123");
            const quote = await oGLP.investQuote(amount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);

            // 1 more than the GLP quote amount fails
            {
                const manualQuote = {
                    ...quote.quoteData,
                    minInvestmentAmount: quote.quoteData.expectedInvestmentAmount.add(1),
                };
                await expect(oGLP.connect(alan).investWithNative(
                    manualQuote, {value: amount})
                ).to.be.revertedWith("GlpManager: insufficient GLP output");
            }

            const ethBalBefore = await alan.getBalance();

            // Successfully bought
            await expect(
                oGLP.connect(alan).investWithNative(quote.quoteData, {value: amount})
            )
                .to.emit(oGLP, "Invested")
                .withArgs(await alan.getAddress(), amount, ZERO_ADDRESS, quote.quoteData.expectedInvestmentAmount)
                .to.emit(gmxContracts.glpRewardRouter, "StakeGlp")
                .withArgs(secondaryEarnAccount.address, quote.quoteData.expectedInvestmentAmount);

            const ethBalAfter = await alan.getBalance();

            // The eth was withdrawn, accounting for tx gas
            expect(ethBalBefore.sub(ethBalAfter)).gte(amount);
            expect(ethBalBefore.sub(ethBalAfter)).lte(amount.add(ethers.utils.parseEther("0.001")));

            // Alan has the oGlp
            expect(await oGLP.balanceOf(alan.getAddress())).eq(quote.quoteData.expectedInvestmentAmount);

            // The primary earn account doesn't have the staked GLP
            expect(await gmxContracts.stakedGlpTracker.balanceOf(primaryEarnAccount.address)).eq(0);

            // The secondary earn account DOES have the staked GLP
            expect(await gmxContracts.stakedGlpTracker.balanceOf(secondaryEarnAccount.address)).eq(quote.quoteData.expectedInvestmentAmount);
        });
    });

    describe("Exit oGLP", async () => {
        it("Exit Glp Quote", async () => {
            await expect(oGLP.exitQuote(0, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                .to.be.revertedWithCustomError(oGLP, "ExpectedNonZero");
            await expect(oGLP.exitQuote(10, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                .to.be.revertedWithCustomError(origamiGlpManager, "InvalidToken")
                .withArgs(gmxContracts.gmxToken.address);

            const amount = ethers.utils.parseEther("500");          
            const quote = await oGLP.exitQuote(amount, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            expect(quote.exitFeeBps).deep.eq([
                0,   // No origami fees
                15   // GMX.io fees
            ]);
            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(gmxContracts.bnbToken.address);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(BigNumber.from("1664166666666666666"));  // 500/300 - 15bps fee
            expect(quote.quoteData.minToTokenAmount).eq(quote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
        });

        it("Exit Glp Quote - with slippage", async () => {
            const slippage = 100;
            const amount = ethers.utils.parseEther("500");          
            const quote = await oGLP.exitQuote(amount, gmxContracts.bnbToken.address, slippage, ZERO_DEADLINE);
            expect(quote.exitFeeBps).deep.eq([
                0,   // No origami fees
                15   // GMX.io fees
            ]);
            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(gmxContracts.bnbToken.address);
            expect(quote.quoteData.maxSlippageBps).eq(slippage);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(BigNumber.from("1664166666666666666"));  // 500/300 - 15bps fee
            expect(quote.quoteData.minToTokenAmount).eq(applySlippage(quote.quoteData.expectedToTokenAmount, slippage));
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
        });

        async function investAndTransferStakedGlp(tokenAddr: string, investAmount: BigNumber, invester: Signer) {
            // Invest oGLP
            const investQuote = await oGLP.investQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expectBalancesChangeBy(async () => { 
                await gmxContracts.bnbToken.mint(invester.getAddress(), investAmount);
                await gmxContracts.bnbToken.connect(invester).approve(oGLP.address, investAmount);
                await oGLP.connect(invester).investWithToken(investQuote.quoteData);
            },
                [oGLP, invester, investQuote.quoteData.expectedInvestmentAmount],
                [gmxContracts.bnbToken, invester, 0],
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, 0],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, investQuote.quoteData.expectedInvestmentAmount],
            );

            // Can't immediately transfer from secondary -> primary because of the GMX cooldown (15mins)
            await expect(secondaryEarnAccount.connect(dailyTransferKeeper).transferStakedGlp(investQuote.quoteData.expectedInvestmentAmount, primaryEarnAccount.address))
                .to.be.revertedWith("StakedGlp: cooldown duration not yet passed");

            await transferStakedGlp(investQuote.quoteData.expectedInvestmentAmount);

            return investQuote.quoteData.expectedInvestmentAmount;
        }

        async function transferStakedGlp(amount: BigNumber) {
            await mineForwardSeconds(15*60);
            
            // Can now transfer - the staked GLP now ends up in the primary account
            await expectBalancesChangeBy(async () => { 
                await secondaryEarnAccount.connect(dailyTransferKeeper).transferStakedGlp(amount, primaryEarnAccount.address);
            },
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, amount],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, amount.mul(-1)],
            );
        }

        it("Invest and immediately exit oGLP fails - no GLP in primary", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const investAmount = ethers.utils.parseEther("100");

            // Don't invest->transfer glp into the primary earn account upfront, so an immediate sale will fail.

            // Alan invests some oGlp
            const investQuote = await oGLP.investQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expectBalancesChangeBy(async () => { 
                await gmxContracts.bnbToken.mint(alan.getAddress(), investAmount);
                await gmxContracts.bnbToken.connect(alan).approve(oGLP.address, investAmount);
                await oGLP.connect(alan).investWithToken(investQuote.quoteData);
            },
                [oGLP, alan, investQuote.quoteData.expectedInvestmentAmount],
                [gmxContracts.bnbToken, alan, 0],
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, 0],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, investQuote.quoteData.expectedInvestmentAmount],
            );

            // Now immediately exit out of the position
            const exitAmount = investQuote.quoteData.expectedInvestmentAmount;
            const exitQuote = await oGLP.exitQuote(exitAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount");

            // Transfer the staked GLP from secondary -> primary
            await transferStakedGlp(exitAmount);

            // Now it succeeds
            await expectBalancesChangeBy(async () => { 
                await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGLP, "Exited")
                    .withArgs(await alan.getAddress(), exitAmount, tokenAddr, exitQuote.quoteData.expectedToTokenAmount, await alan.getAddress());
            },
                [oGLP, alan, exitAmount.mul(-1)],
                [gmxContracts.bnbToken, alan, exitQuote.quoteData.expectedToTokenAmount],
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, exitAmount.mul(-1)],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
            );
        });

        it("Exit oGLP to token", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const investAmount = ethers.utils.parseEther("100");

            // Ensure there's some volume in the primary account invest investing (going to the secondary) and transferring the primary
            await investAndTransferStakedGlp(tokenAddr, investAmount, fred);

            const quote = await oGLP.exitQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.connect(alan).exitToToken(quote.quoteData, alan.getAddress()))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            // Alan invests some oGlp
            const investQuote = await oGLP.investQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            {
                await gmxContracts.bnbToken.mint(alan.getAddress(), investAmount);
                await gmxContracts.bnbToken.connect(alan).approve(oGLP.address, investAmount);
                await oGLP.connect(alan).investWithToken(investQuote.quoteData);
            }
            
            // 0 amount errors
            {
                const manualQuote = {
                    ...quote.quoteData,
                    investmentTokenAmount: 0,
                };
                await expect(oGLP.connect(alan).exitToToken(manualQuote, alan.getAddress()))
                    .to.be.revertedWithCustomError(oGLP, "ExpectedNonZero");
            }
            
            // non-glp token fails
            {
                const manualQuote = {
                    ...quote.quoteData,
                    toToken: gmxContracts.gmxToken.address
                };
                await expect(oGLP.connect(alan).exitToToken(manualQuote, alan.getAddress()))
                    .to.be.revertedWithCustomError(oGLP, "InvalidToken")
                    .withArgs(gmxContracts.gmxToken.address);
            }

            // Can now immediately exit out of the position
            const exitAmount = investQuote.quoteData.expectedInvestmentAmount;
            const exitQuote = await oGLP.exitQuote(exitAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expectBalancesChangeBy(async () => {
                await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGLP, "Exited")
                    .withArgs(await alan.getAddress(), exitAmount, tokenAddr, exitQuote.quoteData.expectedToTokenAmount, await alan.getAddress());
            },
                [oGLP, alan, exitAmount.mul(-1)],
                [gmxContracts.bnbToken, alan, exitQuote.quoteData.expectedToTokenAmount],
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, exitAmount.mul(-1)],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
            );

            // If just directly minting, Origami doesn't have any GMX to unstake.
            await oGLP.mint(alan.getAddress(), exitAmount);
            await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount");
        });

        it("Exit oGLP to token - with fees", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const investAmount = ethers.utils.parseEther("100");
            await origamiGlpManager.setSellFeeRate(30, 100);

            // Ensure there's some volume in the primary account invest investing (going to the secondary) and transferring the primary
            const initialOGlpMint = await investAndTransferStakedGlp(tokenAddr, investAmount, fred);

            const quote = await oGLP.exitQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.connect(alan).exitToToken(quote.quoteData, alan.getAddress()))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            // Alan invests some oGlp
            const investQuote = await oGLP.investQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            {
                await gmxContracts.bnbToken.mint(alan.getAddress(), investAmount);
                await gmxContracts.bnbToken.connect(alan).approve(oGLP.address, investAmount);
                await oGLP.connect(alan).investWithToken(investQuote.quoteData);
            }

            // Total supply of oGlp == initial mint amount + what alan just bought.
            expect(await oGLP.totalSupply()).eq(initialOGlpMint.add(investQuote.quoteData.expectedInvestmentAmount));

            // Can now immediately exit out of the position
            const exitAmount = investQuote.quoteData.expectedInvestmentAmount;
            const exitQuote = await oGLP.exitQuote(exitAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            {
                expect(exitQuote.exitFeeBps).deep.eq([3000, 15]);
                const feeAmount = exitAmount.mul(30).div(100);
                const nonFeeAmount = exitAmount.sub(feeAmount);

                // Fails with a bad min amount
                {
                    const manualQuote = {
                        ...exitQuote.quoteData,
                        minToTokenAmount: exitQuote.quoteData.expectedToTokenAmount.add(1),
                    };

                    await expect(oGLP.connect(alan).exitToToken(manualQuote, alan.getAddress()))
                        .to.revertedWith("GlpManager: insufficient output");
                }

                await expectBalancesChangeBy(async () => {
                    await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                        .to.emit(oGLP, "Exited")
                        .withArgs(await alan.getAddress(), exitAmount, tokenAddr, exitQuote.quoteData.expectedToTokenAmount, await alan.getAddress());
                },
                    [oGLP, alan, exitAmount.mul(-1)],
                    [oGLP, feeCollector, feeAmount],
                    [gmxContracts.bnbToken, alan, exitQuote.quoteData.expectedToTokenAmount],
                    [gmxContracts.stakedGlpTracker, primaryEarnAccount, nonFeeAmount.mul(-1)],
                    [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
                );

                // Total oGLP supply == the initial mint amount + the remainder now left from the fee.
                expect(await oGLP.totalSupply()).eq(initialOGlpMint.add(feeAmount));
            }
        });

        it("Exit oGLP to token - with 100% fees", async () => {
            const tokenAddr = gmxContracts.bnbToken.address;
            const investAmount = ethers.utils.parseEther("100");
            await origamiGlpManager.setSellFeeRate(100, 100);

            // Ensure there's some volume in the primary account invest investing (going to the secondary) and transferring the primary
            const initialOGlpMint = await investAndTransferStakedGlp(tokenAddr, investAmount, fred);

            // Alan invests some oGlp
            const investQuote = await oGLP.investQuote(investAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            { 
                await gmxContracts.bnbToken.mint(alan.getAddress(), investAmount);
                await gmxContracts.bnbToken.connect(alan).approve(oGLP.address, investAmount);
                await oGLP.connect(alan).investWithToken(investQuote.quoteData);
            }

            // Total supply of oGlp == initial mint amount + what alan just bought.
            expect(await oGLP.totalSupply()).eq(initialOGlpMint.add(investQuote.quoteData.expectedInvestmentAmount));

            // Can now immediately exit out of the position
            const exitAmount = investQuote.quoteData.expectedInvestmentAmount;
            const exitQuote = await oGLP.exitQuote(exitAmount, tokenAddr, ZERO_SLIPPAGE, ZERO_DEADLINE);
            {
                expect(exitQuote.exitFeeBps).deep.eq([10000, 0]);
                const feeAmount = exitAmount;
                const nonFeeAmount = BN_ZERO;

                await expectBalancesChangeBy(async () => {
                    await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                        .to.emit(oGLP, "Exited")
                        .withArgs(await alan.getAddress(), exitAmount, tokenAddr, exitQuote.quoteData.expectedToTokenAmount, await alan.getAddress());
                },
                    [oGLP, alan, exitAmount.mul(-1)],
                    [oGLP, feeCollector, feeAmount],
                    [gmxContracts.bnbToken, alan, exitQuote.quoteData.expectedToTokenAmount],
                    [gmxContracts.stakedGlpTracker, primaryEarnAccount, nonFeeAmount.mul(-1)],
                    [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
                );

                // Total oGLP supply == the initial mint amount + the remainder now left from the fee.
                expect(await oGLP.totalSupply()).eq(initialOGlpMint.add(feeAmount));
            }
        });

        it("Exit oGLP to staked GLP", async () => {
            const investAmount = ethers.utils.parseEther("100");
            const exitQuote = await oGLP.exitQuote(investAmount, gmxContracts.stakedGlp.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            // Invest
            let glpAmount: BigNumber;
            {
                // Alan first invests GLP directly, rather than via Origami
                {
                    await gmxContracts.bnbToken.mint(alan.getAddress(), investAmount);
                    await gmxContracts.bnbToken.connect(alan).approve(gmxContracts.glpRewardRouter.glpManager(), investAmount);
                    await gmxContracts.glpRewardRouter.connect(alan).mintAndStakeGlp(gmxContracts.bnbToken.address, investAmount, 0, 0);
                    glpAmount = await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress());
                }

                // Need to wait for the 15min cooldown first
                await mineForwardSeconds(15*60);

                // Successfully bought
                await expectBalancesChangeBy(async () => {
                    await gmxContracts.stakedGlp.connect(alan).approve(oGLP.address, glpAmount);
                    const investQuote = await oGLP.investQuote(glpAmount, gmxContracts.stakedGlp.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                    await oGLP.connect(alan).investWithToken(investQuote.quoteData);
                },
                    [oGLP, alan, glpAmount], 
                    [gmxContracts.stakedGlpTracker, alan, glpAmount.mul(-1)],
                    [gmxContracts.stakedGlpTracker, primaryEarnAccount, glpAmount],
                    [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
                );
            }

            // Can now exit
            await expectBalancesChangeBy(async () => {
                const exitQuote2 = await oGLP.exitQuote(glpAmount, gmxContracts.stakedGlp.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await expect(oGLP.connect(alan).exitToToken(exitQuote2.quoteData, alan.getAddress()))
                    .to.emit(oGLP, "Exited")
                    .withArgs(await alan.getAddress(), glpAmount, gmxContracts.stakedGlp.address, glpAmount, await alan.getAddress());
            },
                [oGLP, alan, glpAmount.mul(-1)], 
                [gmxContracts.stakedGlpTracker, alan, glpAmount],
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, glpAmount.mul(-1)],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
            );
        });

        it("Exit oGLP to staked GLP - with 100% fees", async () => {
            await origamiGlpManager.setSellFeeRate(100, 100);
            const investAmount = ethers.utils.parseEther("100");

            // Invest
            let glpAmount: BigNumber;
            {
                // Alan first invests GLP directly, rather than via Origami
                {
                    await gmxContracts.bnbToken.mint(alan.getAddress(), investAmount);
                    await gmxContracts.bnbToken.connect(alan).approve(gmxContracts.glpRewardRouter.glpManager(), investAmount);
                    await gmxContracts.glpRewardRouter.connect(alan).mintAndStakeGlp(gmxContracts.bnbToken.address, investAmount, 0, 0);
                    glpAmount = await gmxContracts.stakedGlpTracker.balanceOf(alan.getAddress());
                }

                // Need to wait for the 15min cooldown first
                await mineForwardSeconds(15*60);

                // Successfully bought
                await gmxContracts.stakedGlp.connect(alan).approve(oGLP.address, glpAmount);
                const investQuote = await oGLP.investQuote(glpAmount, gmxContracts.stakedGlp.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await oGLP.connect(alan).investWithToken(investQuote.quoteData);
            }

            // Can now exit to token
            const glpAmount1 = glpAmount.div(2);
            await expectBalancesChangeBy(async () => {
                const exitQuote = await oGLP.exitQuote(glpAmount1, gmxContracts.stakedGlp.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await expect(oGLP.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGLP, "Exited")
                    .withArgs(await alan.getAddress(), glpAmount1, gmxContracts.stakedGlp.address, 0, await alan.getAddress());
            },
                [oGLP, alan, glpAmount1.mul(-1)], 
                [oGLP, feeCollector, glpAmount1], 
                [gmxContracts.stakedGlpTracker, alan, 0], // Alan gets nothing - all collected as fees
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, 0], // Nothing to unstake since all were taken as fees
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
            );

            // And to native
            const glpAmount2 = glpAmount.sub(glpAmount1);
            await expectBalancesChangeBy(async () => {
                const exitQuote = await oGLP.exitQuote(glpAmount2, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await expect(oGLP.connect(alan).exitToNative(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGLP, "Exited")
                    .withArgs(await alan.getAddress(), glpAmount2, ZERO_ADDRESS, 0, await alan.getAddress());
            },
                [oGLP, alan, glpAmount2.mul(-1)], 
                [oGLP, feeCollector, glpAmount2], 
                [gmxContracts.stakedGlpTracker, alan, 0], // Alan gets nothing - all collected as fees
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, 0], // Nothing to unstake since all were taken as fees
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
            );
        });

        it("Exit oGLP to ETH", async () => {
            const investAmount = ethers.utils.parseEther("100");

            // Ensure there's some GLP volume in the primary account invest investing (going to the secondary) and transferring the primary
            const tokenAddr = gmxContracts.bnbToken.address;
            const initialOGlpMint = await investAndTransferStakedGlp(tokenAddr, ethers.utils.parseEther("1000"), fred);

            const exitQuote1 = await oGLP.exitQuote(investAmount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGLP.connect(alan).exitToNative(exitQuote1.quoteData, alan.getAddress()))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            {
                const manualQuote = {
                    ...exitQuote1.quoteData,
                    toToken: tokenAddr,
                };
                await expect(oGLP.connect(alan).exitToNative(manualQuote, alan.getAddress()))
                    .to.be.revertedWithCustomError(oGLP, "InvalidToken")
                    .withArgs(tokenAddr);
            }

            {
                const manualQuote = {
                    ...exitQuote1.quoteData,
                    investmentTokenAmount: 0,
                };
                await expect(oGLP.connect(alan).exitToNative(manualQuote, alan.getAddress()))
                    .to.be.revertedWithCustomError(oGLP, "ExpectedNonZero");
            }

            // Alan invests some oGlp
            const investQuote = await oGLP.investQuote(investAmount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expectBalancesChangeBy(async () => { 
                await oGLP.connect(alan).investWithNative(investQuote.quoteData, {value:investAmount});
            },
                [oGLP, alan, investQuote.quoteData.expectedInvestmentAmount],
                [gmxContracts.stakedGlpTracker, primaryEarnAccount, 0],
                [gmxContracts.stakedGlpTracker, secondaryEarnAccount, investQuote.quoteData.expectedInvestmentAmount],
            );
            expect(await oGLP.totalSupply()).eq(initialOGlpMint.add(investQuote.quoteData.expectedInvestmentAmount));

            // Can now immediately exit out of the position
            const exitAmount = investQuote.quoteData.expectedInvestmentAmount;
            const exitQuote = await oGLP.exitQuote(exitAmount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
            {
                const ethBalBefore = await alan.getBalance();

                // Fails with a bad min amount
                {
                    const manualQuote = {
                        ...exitQuote.quoteData,
                        minToTokenAmount: exitQuote.quoteData.expectedToTokenAmount.add(1),
                    };
                    
                    await expect(oGLP.connect(alan).exitToNative(manualQuote, alan.getAddress()))
                        .to.revertedWith("GlpManager: insufficient output");
                }
                    
                // Works with slippage
                await expectBalancesChangeBy(async () => { 
                    await expect(oGLP.connect(alan).exitToNative(exitQuote.quoteData, alan.getAddress()))
                        .to.emit(oGLP, "Exited")
                        .withArgs(await alan.getAddress(), exitAmount, ZERO_ADDRESS, exitQuote.quoteData.expectedToTokenAmount, await alan.getAddress());
                },
                    [oGLP, alan, exitAmount.mul(-1)],
                    [gmxContracts.stakedGlpTracker, primaryEarnAccount, exitAmount.mul(-1)],
                    [gmxContracts.stakedGlpTracker, secondaryEarnAccount, 0],
                );

                // Alan received the ETH (minus gas tx cost)
                const ethBalAfter = await alan.getBalance();
                expect(ethBalAfter.sub(ethBalBefore)).gte(exitQuote.quoteData.expectedToTokenAmount.sub(ethers.utils.parseEther("0.002")));
                expect(ethBalAfter.sub(ethBalBefore)).lt(exitQuote.quoteData.expectedToTokenAmount);
            }
            
            // If just directly minting, Origami doesn't have any GLP to unstake.
            await oGLP.mint(alan.getAddress(), exitAmount);
            await expect(oGLP.connect(alan).exitToNative(exitQuote.quoteData, alan.getAddress()))
                .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount");
        });
    });
});