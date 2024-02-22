import { ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { expect } from "chai";
import { 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory,
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory, IOrigamiGmxManager, 
    MintableToken, DummyMintableToken__factory, 
} from "../../../../typechain";
import { deployGmx, GmxContracts } from "./gmx-helpers";
import { 
    deployUupsProxy,
    EmptyBytes, 
    recoverToken, 
    setExplicitAccess, 
    shouldRevertInvalidAccess, 
    ZERO_ADDRESS,
    ZERO_DEADLINE,
    ZERO_SLIPPAGE
} from "../../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getSigners } from "../../signers";

describe("Origami GMX", async () => {
    let owner: Signer;
    let alan: Signer;
    let feeCollector: Signer;
    let gov: Signer;
    let govAddr: string;

    let origamiGmxManager: OrigamiGmxManager;
    let oGMX: OrigamiGmxInvestment;

    let gmxContracts: GmxContracts;
    let gmxEarnAccount: OrigamiGmxEarnAccount;
    let randoErc20: MintableToken;

    before( async () => {
        [owner, alan, feeCollector, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });
    
    async function setup() {
        const ethPerSecond = BigNumber.from("41335970000000"); // 0.00004133597 ETH per second
        const esGmxPerSecond = BigNumber.from("20667989410000000"); // 0.02066798941 esGmx per second
        gmxContracts = await deployGmx(owner, esGmxPerSecond, esGmxPerSecond, ethPerSecond, ethPerSecond);

        oGMX = await new OrigamiGmxInvestment__factory(gov).deploy(govAddr);

        gmxEarnAccount = await deployUupsProxy(
            new OrigamiGmxEarnAccount__factory(gov), 
            [gmxContracts.gmxRewardRouter.address],
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            await gmxContracts.glpRewardRouter.glpVester(),
            gmxContracts.stakedGlp.address,
        );

        origamiGmxManager = await new OrigamiGmxManager__factory(gov).deploy(
            govAddr,
            gmxContracts.gmxRewardRouter.address,
            gmxContracts.glpRewardRouter.address,
            oGMX.address,
            ZERO_ADDRESS, // No GLP token required
            feeCollector.getAddress(),
            gmxEarnAccount.address,
            ZERO_ADDRESS,
        );

        await oGMX.setOrigamiGmxManager(origamiGmxManager.address);

        // The Investment is added as an operator such that it can exit out of oGlp
        await setExplicitAccess(
            origamiGmxManager,
            oGMX.address,
            ["investOGmx", "exitOGmx"],
            true
        );

        // The Investment/manager are added as operators such that they can stake/unstake GMX       
        await setExplicitAccess(
            gmxEarnAccount,
            origamiGmxManager.address,
            ["stakeGmx", "unstakeGmx"],
            true
        );

        // The origamiGmxManager mints/burns oGlp tokens
        await oGMX.addMinter(gov.getAddress());

        randoErc20 = await new DummyMintableToken__factory(gov).deploy(govAddr, "rando", "rando", 18);
        await randoErc20.addMinter(gov.getAddress());
        await randoErc20.mint(gov.getAddress(), ethers.utils.parseEther("1"));
        
        return {
            gmxContracts,
            gmxEarnAccount,
            origamiGmxManager,
            oGMX,
            randoErc20,
        };
    }

    beforeEach(async () => {
        ({
            gmxContracts,
            gmxEarnAccount,
            origamiGmxManager,
            oGMX,
            randoErc20,
        } = await loadFixture(setup));
    });

    it("constructor", async () => {
        expect(await oGMX.origamiGmxManager()).eq(origamiGmxManager.address);
        expect(await oGMX.baseToken()).eq(gmxContracts.gmxToken.address);
        expect(await oGMX.apiVersion()).eq("0.2.0");
    });

    it("admin", async () => {
        const {quoteData: investQuote, } = await oGMX.investQuote(10, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
        const {quoteData: exitQuote, } = await oGMX.exitQuote(10, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

        await expect(oGMX.investWithNative(investQuote, {value: 0})).to.be.revertedWithCustomError(oGMX, "Unsupported");
        await expect(oGMX.exitToNative(exitQuote, alan.getAddress())).to.be.revertedWithCustomError(oGMX, "Unsupported");

        await shouldRevertInvalidAccess(oGMX, oGMX.connect(owner).setOrigamiGmxManager(ZERO_ADDRESS));
        await shouldRevertInvalidAccess(oGMX, oGMX.connect(alan).recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10));

        // Happy paths
        await oGMX.connect(gov).setOrigamiGmxManager(origamiGmxManager.address);
        await expect(oGMX.recoverToken(gmxContracts.bnbToken.address, alan.getAddress(), 10))
            .to.revertedWith("ERC20: transfer amount exceeds balance");
    });

    it("areInvestmentsPaused/areExitsPaused should be correct", async () => {
        // Not paused by default
        expect(await oGMX.areInvestmentsPaused()).eq(false);
        expect(await oGMX.areExitsPaused()).eq(false);
        
        // Set to be paused on the gmx manager.
        const paused: IOrigamiGmxManager.PausedStruct = {
            glpInvestmentsPaused: true,
            gmxInvestmentsPaused: true,
            glpExitsPaused: true,
            gmxExitsPaused: true,
        };
        await setExplicitAccess(
            origamiGmxManager,
            govAddr,
            ["setPauser"],
            true
        );
        await origamiGmxManager.setPauser(govAddr, true);
        await origamiGmxManager.setPaused(paused);
        expect(await oGMX.areInvestmentsPaused()).eq(true);
        expect(await oGMX.areExitsPaused()).eq(true);
    });

    it("gov can recover tokens", async () => {           
        const amount = 50;
        await gmxContracts.bnbToken.mint(oGMX.address, amount);
        await recoverToken(gmxContracts.bnbToken, amount, oGMX, owner);   
    });

    it("Should set gmx manager", async () => {
        await expect(oGMX.setOrigamiGmxManager(ZERO_ADDRESS))
            .to.be.revertedWithCustomError(oGMX, "InvalidAddress")
            .withArgs(ZERO_ADDRESS);

        const origamiGmxManager2 = await new OrigamiGmxManager__factory(gov).deploy(
                govAddr,
                gmxContracts.gmxRewardRouter.address,
                gmxContracts.glpRewardRouter.address,
                oGMX.address,
                ZERO_ADDRESS, // No GLP token required
                feeCollector.getAddress(),
                gmxEarnAccount.address,
                ZERO_ADDRESS,
            );
        await expect(oGMX.setOrigamiGmxManager(origamiGmxManager2.address))
            .to.emit(oGMX, "OrigamiGmxManagerSet")
            .withArgs(origamiGmxManager2.address);

        expect(await oGMX.origamiGmxManager()).eq(origamiGmxManager2.address);
    });

    it("Should get accepted tokens", async () => {
        const tokens = await oGMX.acceptedInvestTokens();
        expect(tokens).deep.eq(
            [
                gmxContracts.gmxToken.address,
            ]
        );

        // exit tokens are the same as invest tokens
        expect(await oGMX.acceptedExitTokens()).deep.eq(tokens);
    });

    describe("Invest/Exit OGmx", async () => {
        it("Invest/Exit quote", async () => {
            // investQuote
            {
                await expect(oGMX.investQuote(0, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                    .to.be.revertedWithCustomError(oGMX, "ExpectedNonZero");

                await expect(oGMX.investQuote(100, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidToken")
                    .withArgs(gmxContracts.bnbToken.address);
                
                const quote1 = await oGMX.investQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                expect(quote1.quoteData.fromToken).eq(gmxContracts.gmxToken.address);
                expect(quote1.quoteData.fromTokenAmount).eq(100);
                expect(quote1.quoteData.expectedInvestmentAmount).eq(100);
                expect(quote1.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
                expect(quote1.investFeeBps).deep.eq([]);
            }

            // exitQuote
            {
                await expect(oGMX.exitQuote(0, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                    .to.be.revertedWithCustomError(oGMX, "ExpectedNonZero");

                await expect(oGMX.exitQuote(100, gmxContracts.bnbToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidToken")
                    .withArgs(gmxContracts.bnbToken.address);
                
                await origamiGmxManager.setSellFeeRate(3_000);
                const quote2 = await oGMX.exitQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                expect(quote2.quoteData.investmentTokenAmount).eq(100);
                expect(quote2.quoteData.toToken).eq(gmxContracts.gmxToken.address);
                expect(quote2.quoteData.expectedToTokenAmount).eq(70);
                expect(quote2.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
                expect(quote2.exitFeeBps).deep.eq([3000]);
            }
        });

        it("max Exit and Invest", async () => {
            expect(await oGMX.maxInvest(await alan.getAddress())).eq(ethers.constants.MaxUint256);
            expect(await oGMX.maxInvest(gmxContracts.bnbToken.address)).eq(ethers.constants.MaxUint256);
    
            expect(await oGMX.maxExit(await alan.getAddress())).eq(ethers.constants.MaxUint256);
            expect(await oGMX.maxExit(gmxContracts.bnbToken.address)).eq(ethers.constants.MaxUint256);
        });

        it("Invest OGmx with GMX", async () => {
            // 0 fromTokenAmount errors
            {
                const manualQuote = {
                    ...(await oGMX.investQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                    fromTokenAmount: BigNumber.from(0),
                };
                await expect(oGMX.investWithToken(manualQuote))
                    .to.be.revertedWithCustomError(origamiGmxManager, "ExpectedNonZero");
            }

            // Non-gmx token errors
            {
                const manualQuote = {
                    ...(await oGMX.investQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                    fromToken: randoErc20.address
                };
                await randoErc20.approve(oGMX.address, 100);
                await expect(oGMX.investWithToken(manualQuote))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidToken")
                    .withArgs(randoErc20.address);
            }

            const amount = ethers.utils.parseEther("100");
            const quote = await oGMX.investQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

            await expect(oGMX.investWithToken(quote.quoteData))
                .to.be.revertedWith("BaseToken: transfer amount exceeds allowance");

            await gmxContracts.gmxToken.mint(alan.getAddress(), amount);
            await gmxContracts.gmxToken.connect(alan).approve(oGMX.address, amount);

            // Successfully bought
            await expect(oGMX.connect(alan).investWithToken(quote.quoteData))
                .to.emit(oGMX, "Invested")
                .withArgs(await alan.getAddress(), amount, gmxContracts.gmxToken.address, amount);

            // Alan doesn't have the GMX, but has the oGmx
            expect(await gmxContracts.gmxToken.balanceOf(alan.getAddress())).eq(0);
            expect(await oGMX.balanceOf(alan.getAddress())).eq(amount);

            // The origamiGmxManager and earn account don't have the GMX
            expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
            expect(await gmxContracts.gmxToken.balanceOf(gmxEarnAccount.address)).eq(0);
            
            // The earn account has the staked GMX
            expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(amount);
        });

        it("Invest/Exit OGmx with native fails", async () => {
            const investQuote = await oGMX.investQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGMX.investWithNative(investQuote.quoteData))
                .to.be.revertedWithCustomError(oGMX, "Unsupported");
            
            const exitQuote = await oGMX.exitQuote(100, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGMX.exitToNative(exitQuote.quoteData, alan.getAddress()))
                .to.be.revertedWithCustomError(oGMX, "Unsupported");
        });

        it("Exit OGmx to GMX", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await oGMX.exitQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGMX.connect(alan).exitToToken(quote.quoteData, alan.getAddress()))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            // Alan invests into some oGmx
            {
                await gmxContracts.gmxToken.mint(alan.getAddress(), amount);
                await gmxContracts.gmxToken.connect(alan).approve(oGMX.address, amount);
                const investQuote = await oGMX.investQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await oGMX.connect(alan).investWithToken(investQuote.quoteData);
                expect(await oGMX.balanceOf(alan.getAddress())).eq(amount);
                expect(await gmxContracts.gmxToken.balanceOf(alan.getAddress())).eq(0);
                expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
                expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(amount);
            }

            // Can now exit out of the position
            const exitQuote = await oGMX.exitQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

            // 0 investmentTokenAmount errors
            {
                const manualQuote = {
                    ...exitQuote.quoteData,
                    investmentTokenAmount: BigNumber.from(0),
                };
                await expect(oGMX.connect(alan).exitToToken(manualQuote, alan.getAddress()))
                    .to.be.revertedWithCustomError(origamiGmxManager, "ExpectedNonZero");
            }

            // Non-gmx token errors
            {
                const manualQuote = {
                    ...exitQuote.quoteData,
                    toToken: randoErc20.address,
                };
                await expect(oGMX.connect(alan).exitToToken(manualQuote, alan.getAddress()))
                    .to.be.revertedWithCustomError(origamiGmxManager, "InvalidToken")
                    .withArgs(randoErc20.address);
            }

            {
                await expect(
                    oGMX.connect(alan).exitToToken(exitQuote.quoteData, ZERO_ADDRESS)
                ).to.revertedWithCustomError(oGMX, "InvalidAddress")
                .withArgs(ZERO_ADDRESS);
            }

            {
                await expect(oGMX.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGMX, "Exited")
                    .withArgs(await alan.getAddress(), amount, gmxContracts.gmxToken.address, amount, await alan.getAddress())
                    .to.emit(gmxContracts.gmxRewardRouter, "UnstakeGmx");
                expect(exitQuote.quoteData.expectedToTokenAmount).eq(amount);
                expect(exitQuote.exitFeeBps).deep.eq([0]);
                expect(await oGMX.balanceOf(alan.getAddress())).eq(0);
                expect(await gmxContracts.gmxToken.balanceOf(alan.getAddress())).eq(amount);
                expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
                expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(0);
            }
            
            // If just directly minting, Origami doesn't have any GMX to unstake.
            await oGMX.mint(alan.getAddress(), amount);
            await expect(oGMX.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount");
        });

        it("Exit OGmx to GMX - with fees", async () => {
            const amount = ethers.utils.parseEther("100");
            const quote = await oGMX.exitQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await expect(oGMX.connect(alan).exitToToken(quote.quoteData, alan.getAddress()))
                .to.be.revertedWith("ERC20: transfer amount exceeds balance");

            // Alan invests into some oGmx
            {
                await gmxContracts.gmxToken.mint(alan.getAddress(), amount);
                await gmxContracts.gmxToken.connect(alan).approve(oGMX.address, amount);
                const investQuote = await oGMX.investQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await oGMX.connect(alan).investWithToken(investQuote.quoteData);
                expect(investQuote.quoteData.expectedInvestmentAmount).equals(amount);
                expect(await oGMX.balanceOf(alan.getAddress())).eq(amount);
                expect(await gmxContracts.gmxToken.balanceOf(alan.getAddress())).eq(0);
                expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
                expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(amount);
            }

            await origamiGmxManager.setSellFeeRate(3_000);

            // Can now exit out of the position
            {
                const feeAmount = amount.mul(30).div(100);
                const remainderAmount = amount.sub(feeAmount);

                const exitQuote = await oGMX.exitQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                expect(exitQuote.quoteData.expectedToTokenAmount).eq(remainderAmount);
                expect(exitQuote.exitFeeBps).deep.eq([3000]);
                await expect(oGMX.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGMX, "Exited")
                    .withArgs(await alan.getAddress(), amount, gmxContracts.gmxToken.address, remainderAmount, await alan.getAddress())
                    .to.emit(gmxContracts.gmxRewardRouter, "UnstakeGmx");
                expect(await oGMX.balanceOf(alan.getAddress())).eq(0);
                expect(await oGMX.balanceOf(feeCollector.getAddress())).eq(feeAmount);
                expect(await oGMX.totalSupply()).eq(feeAmount);

                // Fees/remainder for GMX are in the right place
                expect(await gmxContracts.gmxToken.balanceOf(alan.getAddress())).eq(remainderAmount);
                expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
                expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(feeAmount);
            }
        });

        it("Exit OGmx to GMX - with 100% fees", async () => {
            const amount = ethers.utils.parseEther("100");

            // Alan invests into some oGmx
            {
                await gmxContracts.gmxToken.mint(alan.getAddress(), amount);
                await gmxContracts.gmxToken.connect(alan).approve(oGMX.address, amount);
                const investQuote = await oGMX.investQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                await oGMX.connect(alan).investWithToken(investQuote.quoteData);
            }

            await origamiGmxManager.setSellFeeRate(10_000);

            // Can now exit out of the position
            {
                const feeAmount = amount.mul(100).div(100);
                const remainderAmount = 0;

                const exitQuote = await oGMX.exitQuote(amount, gmxContracts.gmxToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                expect(exitQuote.quoteData.expectedToTokenAmount).eq(remainderAmount);
                expect(exitQuote.exitFeeBps).deep.eq([10000]);
                await expect(oGMX.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress()))
                    .to.emit(oGMX, "Exited")
                    .withArgs(await alan.getAddress(), amount, gmxContracts.gmxToken.address, remainderAmount, await alan.getAddress())
                    .to.not.emit(gmxContracts.gmxRewardRouter, "UnstakeGmx");
                expect(await oGMX.balanceOf(alan.getAddress())).eq(0);
                expect(await oGMX.balanceOf(feeCollector.getAddress())).eq(feeAmount);
                expect(await oGMX.totalSupply()).eq(feeAmount);

                // Fees/remainder for GMX are in the right place
                expect(await gmxContracts.gmxToken.balanceOf(alan.getAddress())).eq(remainderAmount);
                expect(await gmxContracts.gmxToken.balanceOf(origamiGmxManager.address)).eq(0);
                expect(await gmxContracts.stakedGmxTracker.stakedAmounts(gmxEarnAccount.address)).eq(feeAmount);
            }
        });
    });

});
