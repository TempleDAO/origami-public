import { ethers } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyOrigamiInvestment, DummyOrigamiInvestment__factory, 
    DummyOrigamiInvestmentManager, DummyOrigamiInvestmentManager__factory,
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory, 
    TokenPrices, TokenPrices__factory,
    MintableToken, DummyMintableToken__factory,
    IOrigamiInvestment,
    DummyOracle, DummyOracle__factory,
} from "../../typechain";
import { 
    expectBalancesChangeBy, 
    shouldRevertNotGov,
    ZERO_ADDRESS, EmptyBytes, 
    getEthBalance,
    encodeInvestQuoteData,
    decodeInvestQuoteData,
    expectApproxEqRel, 
    tolerance, 
    ONE_ETH,
    ZERO_SLIPPAGE,
    ZERO_DEADLINE,
    applySlippage,
    blockTimestamp,
    mineForwardSeconds,
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getSigners } from "../signers";

// 0.001% max relative delta for time based reward checks - ie from BigNumber order of operations -> rounding
const MAX_REL_DELTA = tolerance(0.001);
const vestingDuration = 7 * 86400;

describe("Origami Investment Vault", async () => {
    let owner: Signer;
    let operator: Signer;
    let alan: Signer;
    let bob: Signer;
    let gov: Signer;
    let govAddr: string;
    let oToken: DummyOrigamiInvestment;
    let ovToken: OrigamiInvestmentVault;
    let tokenPrices: TokenPrices;
    let investmentManager: DummyOrigamiInvestmentManager;
    let underlyingInvestToken: MintableToken;
    let underlyingExitToken: MintableToken;
    let rewardToken1: MintableToken;
    let rewardToken2: MintableToken;
    
    before( async () => {
        [owner, operator, alan, bob, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });

    async function setup() {
        // Setup oToken
        {
            underlyingInvestToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "investToken", "investToken");
            underlyingInvestToken.addMinter(operator.getAddress());
            underlyingExitToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "exitToken", "exitToken");
            underlyingExitToken.addMinter(operator.getAddress());
            oToken = await new DummyOrigamiInvestment__factory(gov).deploy(
                govAddr,
                "oToken", "oToken", 
                underlyingInvestToken.address, 
                underlyingExitToken.address
            );
            await oToken.addMinter(operator.getAddress());
        }
        
        // Setup ovToken
        {
            tokenPrices = await new TokenPrices__factory(gov).deploy(30);
            ovToken = await new OrigamiInvestmentVault__factory(gov).deploy(govAddr, "ovToken", "ovToken", oToken.address, tokenPrices.address, 5, vestingDuration);
            await ovToken.addOperator(operator.getAddress());
        }
        
        // Setup investment manager
        {
            rewardToken1 = await new DummyMintableToken__factory(gov).deploy(govAddr, "rwd1", "rwd1");
            rewardToken2 = await new DummyMintableToken__factory(gov).deploy(govAddr, "rwd2", "rwd2");
            investmentManager = await new DummyOrigamiInvestmentManager__factory(gov).deploy(
                [rewardToken1.address, rewardToken2.address],
                [
                    ethers.utils.parseEther("0.000028935185185185"), // 2.5 per day, 912.5 per year
                    ethers.utils.parseEther("0.000017361111111111"), // 1.5 per day, 547.5 per year
                ],
                ovToken.address,
            );
        }

        // Setup ovToken
        {
            await ovToken.setInvestmentManager(investmentManager.address);
        }

        // Setup tokenPrices
        {
            const tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
            let oracleAnswer: DummyOracle.AnswerStruct = {
                roundId: 10,
                answer: BigNumber.from("3000000000"),
                startedAt: await blockTimestamp(),
                updatedAtLag: 10,
                answeredInRound: 5
            };

            // Set $rewardToken1 == 30
            const rewardToken1UsdOracle = await new DummyOracle__factory(gov).deploy(oracleAnswer, 8);
            const encodedRewardToken1UsdOracle = tokenPricesInterface.encodeFunctionData("oraclePrice", [rewardToken1UsdOracle.address, 600]);
            await tokenPrices.setTokenPriceFunction(rewardToken1.address, encodedRewardToken1UsdOracle);

            // Set $rewardToken1 == 50
            oracleAnswer = {
                ...oracleAnswer,
                answer: BigNumber.from("5000000000")
            };
            const rewardToken2UsdOracle = await new DummyOracle__factory(gov).deploy(oracleAnswer, 8);
            const encodedRewardToken2UsdOracle = tokenPricesInterface.encodeFunctionData("oraclePrice", [rewardToken2UsdOracle.address, 600]);
            await tokenPrices.setTokenPriceFunction(rewardToken2.address, encodedRewardToken2UsdOracle);

            // Set $oToken == 15
            oracleAnswer = {
                ...oracleAnswer,
                answer: BigNumber.from("1500000000")
            };
            const oTokenUsdOracle = await new DummyOracle__factory(gov).deploy(oracleAnswer, 8);
            const encodedoTokenUsdOracle = tokenPricesInterface.encodeFunctionData("oraclePrice", [oTokenUsdOracle.address, 600]);
            await tokenPrices.setTokenPriceFunction(oToken.address, encodedoTokenUsdOracle);

            // ovToken price == oToken price * reservesPerShare()
            const encodedovTokenUsd = tokenPricesInterface.encodeFunctionData("repricingTokenPrice", [ovToken.address]);
            await tokenPrices.setTokenPriceFunction(ovToken.address, encodedovTokenUsd);
        }

        return {
            oToken,
            ovToken,
            tokenPrices,
            rewardToken1,
            rewardToken2,
            investmentManager,
            underlyingInvestToken,
            underlyingExitToken,
        }
    }

    beforeEach(async () => {
        ({
            oToken,
            ovToken,
            tokenPrices,
            rewardToken1,
            rewardToken2,
            investmentManager,
            underlyingInvestToken,
            underlyingExitToken,
        } = await loadFixture(setup));
    });

    const addPendingReserves = async (extraReservesAmount: BigNumber) => {
        await oToken.connect(operator).mint(operator.getAddress(), extraReservesAmount);
        await oToken.connect(operator).approve(ovToken.address, extraReservesAmount);
        await ovToken.connect(operator).addPendingReserves(extraReservesAmount);
    }

    // Invest and add extra reserves to bump the price
    const bootstrapReserves = async (): Promise<BigNumber> => {
        // Mint to alan
        const investAmount = ethers.utils.parseEther("10000");
        await oToken.connect(operator).mint(alan.getAddress(), investAmount);
        await oToken.connect(alan).approve(ovToken.address, investAmount);

        // Alan invests 10k
        const quote = await ovToken.investQuote(investAmount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
        await ovToken.connect(alan).investWithToken(quote.quoteData);

        // Mint to operator
        const extraReservesAmount = ethers.utils.parseEther("1000");
        await addPendingReserves(extraReservesAmount);
        await mineForwardSeconds(vestingDuration);

        const reservesPerShare = await ovToken.reservesPerShare();
        return reservesPerShare;
    }

    it("entry and exit", async () => {
        const investAmount = ethers.utils.parseEther("10000");
        await oToken.connect(operator).mint(alan.getAddress(), investAmount);
        await oToken.connect(alan).approve(ovToken.address, investAmount);
        await oToken.connect(operator).mint(bob.getAddress(), investAmount);
        await oToken.connect(bob).approve(ovToken.address, investAmount);

        // Alan invests - check 
        let investQuote = await ovToken.investQuote(investAmount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
        await ovToken.connect(alan).investWithToken(investQuote.quoteData);

        let alanBal = await ovToken.balanceOf(alan.getAddress());
        let shares = await ovToken.sharesToReserves(alanBal);
        expect(alanBal).eq(investAmount);
        expect(shares).eq(investAmount);
        expect(await ovToken.reservesToShares(shares)).eq(investAmount);

        let totalSupply = await ovToken.totalSupply();
        shares = await ovToken.sharesToReserves(totalSupply);
        expect(totalSupply).eq(investAmount);
        expect(shares).eq(investAmount);
        expect(await ovToken.reservesToShares(shares)).eq(investAmount);

        // Bob invests
        investQuote = await ovToken.investQuote(investAmount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
        await ovToken.connect(bob).investWithToken(investQuote.quoteData);

        let bobBal = await ovToken.balanceOf(bob.getAddress());
        shares = await ovToken.sharesToReserves(bobBal);
        expect(bobBal).eq(investAmount);
        expect(shares).eq(investAmount);
        expect(await ovToken.reservesToShares(shares)).eq(investAmount);

        totalSupply = await ovToken.totalSupply();
        shares = await ovToken.sharesToReserves(totalSupply);
        expect(totalSupply).eq(investAmount.mul(2));
        expect(shares).eq(investAmount.mul(2));
        expect(await ovToken.reservesToShares(shares)).eq(investAmount.mul(2));

        // Add reserves
        const reservesAmt = investAmount.mul(1).div(100);
        await oToken.connect(operator).mint(operator.getAddress(), reservesAmt);
        await oToken.connect(operator).approve(ovToken.address, reservesAmt);
        await ovToken.connect(operator).addPendingReserves(reservesAmt);
        await mineForwardSeconds(vestingDuration);

        // The final drips of the extra reserves that were added in aren't available until
        // a checkpoint is done.
        // This world ordinarily happen daily anyway, and only impacts the very last chunk
        await ovToken.checkpointReserves();

        totalSupply = await ovToken.totalSupply();
        shares = await ovToken.sharesToReserves(totalSupply);
        expect(totalSupply).eq(investAmount.mul(2));
        expect(shares).eq(investAmount.mul(2).add(reservesAmt));
        expect(await ovToken.reservesToShares(shares)).eq(investAmount.mul(2));

        // Alan exits
        let exitQuote = await ovToken.exitQuote(alanBal, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
        await ovToken.connect(alan).exitToToken(exitQuote.quoteData, alan.getAddress());

        alanBal = await ovToken.balanceOf(alan.getAddress());
        shares = await ovToken.sharesToReserves(alanBal);
        expect(alanBal).eq(0);
        expect(shares).eq(0);
        expect(await ovToken.reservesToShares(shares)).eq(0);

        totalSupply = await ovToken.totalSupply();
        shares = await ovToken.sharesToReserves(totalSupply);
        expect(totalSupply).eq(investAmount);
        expect(shares).eq(investAmount.add(reservesAmt.div(2)));
        expect(await ovToken.reservesToShares(shares)).eq(investAmount);

        // Bob exits
        exitQuote = await ovToken.exitQuote(bobBal, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
        await ovToken.connect(bob).exitToToken(exitQuote.quoteData, bob.getAddress());

        bobBal = await ovToken.balanceOf(bob.getAddress());
        shares = await ovToken.sharesToReserves(bobBal);
        expect(bobBal).eq(0);
        expect(shares).eq(0);
        expect(await ovToken.reservesToShares(shares)).eq(0);

        totalSupply = await ovToken.totalSupply();
        shares = await ovToken.sharesToReserves(totalSupply);
        expect(totalSupply).eq(0);
        expect(shares).eq(0);
        expect(await ovToken.reservesToShares(shares)).eq(0);
    });

    it("constructor", async () => {
        expect(await ovToken.reserveToken()).eq(oToken.address);
        expect(await ovToken.baseToken()).eq(oToken.address);
        expect(await ovToken.tokenPrices()).eq(tokenPrices.address);
        const [numerator, denominator] = await ovToken.performanceFee();
        expect(numerator.toNumber()).to.eq(5);
        expect(denominator.toNumber()).to.eq(100);
        expect(await ovToken.apiVersion()).eq("0.1.0");
    });

    it("admin", async () => {
        await shouldRevertNotGov(ovToken, ovToken.connect(owner).setInvestmentManager(investmentManager.address));
        await shouldRevertNotGov(ovToken, ovToken.connect(owner).setTokenPrices(tokenPrices.address));
        await shouldRevertNotGov(ovToken, ovToken.connect(owner).setPerformanceFee(80, 100));

        await expect(ovToken.connect(alan).addPendingReserves(0))
            .to.revertedWithCustomError(ovToken, "OnlyOperators")
            .withArgs(await alan.getAddress());

        // Happy paths
        await ovToken.connect(gov).setInvestmentManager(investmentManager.address);
        await ovToken.connect(gov).setTokenPrices(tokenPrices.address);
        await ovToken.connect(gov).setPerformanceFee(80, 100);
    });

    it("gov can set the investment manager", async () => {           
        await expect(ovToken.setInvestmentManager(ZERO_ADDRESS))
            .to.be.revertedWithCustomError(ovToken, "InvalidAddress")
            .withArgs(ZERO_ADDRESS);
        await expect(ovToken.setInvestmentManager(investmentManager.address))
            .to.emit(ovToken, "InvestmentManagerSet")
            .withArgs(investmentManager.address);
        expect(await ovToken.investmentManager()).to.eq(investmentManager.address);
    });

    it("gov can set token prices", async () => {           
        await expect(ovToken.setTokenPrices(ZERO_ADDRESS))
            .to.be.revertedWithCustomError(ovToken, "InvalidAddress")
            .withArgs(ZERO_ADDRESS);
        await expect(ovToken.setTokenPrices(tokenPrices.address))
            .to.emit(ovToken, "TokenPricesSet")
            .withArgs(tokenPrices.address);
        expect(await ovToken.tokenPrices()).to.eq(tokenPrices.address);
    });

    it("Should setPerformanceFee()", async () => {
        await expect(ovToken.setPerformanceFee(80, 100))
            .to.emit(ovToken, "PerformanceFeeSet")
            .withArgs(80, 100);
        const [numerator, denominator] = await ovToken.performanceFee();
        expect(numerator.toNumber()).to.eq(80);
        expect(denominator.toNumber()).to.eq(100);
    });

    it("areInvestmentsPaused/areExitsPaused should be correct", async () => {
        // Not paused by default
        expect(await ovToken.areInvestmentsPaused()).eq(false);
        expect(await ovToken.areExitsPaused()).eq(false);

        // Set to be disabled on the underlying oToken
        await oToken.setPaused(true, true);

        expect(await ovToken.areInvestmentsPaused()).eq(true);
        expect(await ovToken.areExitsPaused()).eq(true);
    });

    it("correctly wrapped accepted tokens", async () => {
        // Appends the oToken at the end
        let tokens = await ovToken.acceptedInvestTokens();
        expect(tokens).deep.eq([underlyingInvestToken.address, oToken.address]);

        tokens = await ovToken.acceptedExitTokens();
        expect(tokens).deep.eq([underlyingExitToken.address, oToken.address]);
    });

    const exitQuoteTypes = 'tuple(tuple(uint256 investmentTokenAmount, address toToken, uint256 maxSlippageBps, uint256 deadline, uint256 expectedToTokenAmount, uint256 minToTokenAmount, bytes underlyingInvestmentQuoteData) underlyingExitQuoteData)';
    const encodeUnderlyingExitQuoteData = (quoteData: IOrigamiInvestment.ExitQuoteDataStruct): string => {
        return ethers.utils.defaultAbiCoder.encode(
            [exitQuoteTypes], 
            [{
                underlyingExitQuoteData: quoteData,
            }]
        );
    }

    type UnderlyingExitQuoteData = {
        underlyingExitQuoteData: IOrigamiInvestment.ExitQuoteDataStruct,
    }
    const decodeUnderlyingExitQuoteData = (encodedQuoteData: string): UnderlyingExitQuoteData => {
        return ethers.utils.defaultAbiCoder.decode(
            [exitQuoteTypes], 
            encodedQuoteData
        )[0];
    }

    it("correctly wrapped invest quote", async () => {
        // Can't give quote for 0 amount        
        await expect(ovToken.investQuote(0, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
            .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
        
        // The reserve token, expected 1:1 since no reserves yet added
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.investQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedSharesAmount = await ovToken.reservesToShares(amount);
            expect(expectedSharesAmount).eq(amount);

            expect(quote.quoteData.fromToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.minInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.investFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const underlyingQuote = await oToken.investQuote(amount, underlyingInvestToken.address, 0, ZERO_DEADLINE);
            const expectedSharesAmount = await ovToken.reservesToShares(underlyingQuote.quoteData.expectedInvestmentAmount);
            expect(expectedSharesAmount).eq(amount.mul(9_900).div(10_000));

            expect(quote.quoteData.fromToken).eq(underlyingInvestToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.minInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeInvestQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.investFeeBps).deep.eq([100]);
        }

        const reservesPerShare = await bootstrapReserves();
        expect(reservesPerShare).eq(ONE_ETH.mul(11_000).div(10_000));

        // The reserve token, now expect less shares as the price has increased
        {
            const amount = ethers.utils.parseEther("1000");
            const quote = await ovToken.investQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedSharesAmount = await ovToken.reservesToShares(amount);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedSharesAmount).eq(amount.mul(ONE_ETH).div(reservesPerShare));

            expect(quote.quoteData.fromToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.minInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.investFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees. Now expect less shares as the price has increased
        {
            const amount = ethers.utils.parseEther("1000");
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const underlyingQuote = await oToken.investQuote(amount, underlyingInvestToken.address, 0, ZERO_DEADLINE);
            const expectedSharesAmount = await ovToken.reservesToShares(underlyingQuote.quoteData.expectedInvestmentAmount);

            // Now expect less shares for the same amount of reserves, 
            // since there is a fee, and also the reservesPerShare has now gone up
            expect(expectedSharesAmount).eq(amount.mul(9_900).div(10_000).mul(ONE_ETH).div(reservesPerShare));

            expect(quote.quoteData.fromToken).eq(underlyingInvestToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.minInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeInvestQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.investFeeBps).deep.eq([100]);
        }

        // Check slippage
        {
            const amount = ethers.utils.parseEther("1000");
            const slippage = 100; // 1%
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address, slippage, ZERO_DEADLINE);
            const underlyingQuote = await oToken.investQuote(amount, underlyingInvestToken.address, 0, ZERO_DEADLINE);
            const expectedSharesAmount = await ovToken.reservesToShares(underlyingQuote.quoteData.expectedInvestmentAmount);

            // Now expect less shares for the same amount of reserves, 
            // since there is a fee, and also the reservesPerShare has now gone up
            expect(expectedSharesAmount).eq(amount.mul(9_900).div(10_000).mul(ONE_ETH).div(reservesPerShare));

            expect(quote.quoteData.fromToken).eq(underlyingInvestToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.maxSlippageBps).eq(slippage);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.minInvestmentAmount).eq(applySlippage(expectedSharesAmount, slippage));
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeInvestQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.investFeeBps).deep.eq([100]);
        }
    });

    it("correctly wrapped exit quote", async () => {
        // Can't give quote for 0 amount        
        await expect(ovToken.exitQuote(0, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE))
            .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
    
        // The reserve token, expected 0 since no shares
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(0);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.minToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.exitFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            expect(quote.quoteData.expectedToTokenAmount).eq(0);
            const underlyingQuote = await oToken.exitQuote(expectedReserveAmount, underlyingExitToken.address, 0, ZERO_DEADLINE);

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(underlyingExitToken.address);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(underlyingQuote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.minToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeUnderlyingExitQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.exitFeeBps).deep.eq([500]);
        }

        const reservesPerShare = await bootstrapReserves();
        expect(reservesPerShare).eq(ONE_ETH.mul(11_000).div(10_000));

        // The reserve token, expected 1:1 since no reserves yet added
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedReserveAmount).eq(amount.mul(reservesPerShare).div(ONE_ETH));

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.minToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.exitFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            const underlyingQuote = await oToken.exitQuote(expectedReserveAmount, underlyingExitToken.address, 0, ZERO_DEADLINE);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedReserveAmount).eq(amount.mul(reservesPerShare).div(ONE_ETH));

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(underlyingExitToken.address);
            expect(quote.quoteData.maxSlippageBps).eq(ZERO_SLIPPAGE);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(underlyingQuote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.minToTokenAmount).eq(quote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeUnderlyingExitQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.exitFeeBps).deep.eq([500]);
        }

        // Slippage
        {
            const amount = ethers.utils.parseEther("100");
            const slippage = 100; // 1%
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address, slippage, ZERO_DEADLINE);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            const underlyingQuote = await oToken.exitQuote(expectedReserveAmount, underlyingExitToken.address, 0, ZERO_DEADLINE);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedReserveAmount).eq(amount.mul(reservesPerShare).div(ONE_ETH));

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(underlyingExitToken.address);
            expect(quote.quoteData.maxSlippageBps).eq(slippage);
            expect(quote.quoteData.deadline).eq(ZERO_DEADLINE);
            expect(quote.quoteData.expectedToTokenAmount).eq(underlyingQuote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.minToTokenAmount).eq(applySlippage(quote.quoteData.expectedToTokenAmount, slippage));
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeUnderlyingExitQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.exitFeeBps).deep.eq([500]);
        }
    });

    it("correctly wrapped invest with token", async () => {
        // The reserve token, expected 1:1 since no reserves yet added
        const investWithReserveToken = async () => {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            {
                const amount = ethers.utils.parseEther("1000");
                const quote = await ovToken.investQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
                const expectedNewReserves = amount;

                await oToken.connect(operator).mint(bob.getAddress(), amount);
                await oToken.connect(bob).approve(ovToken.address, amount);

                await expectBalancesChangeBy(async () => { 
                    await expect(ovToken.connect(bob).investWithToken(quote.quoteData))
                        .to.emit(ovToken, "Transfer")
                        .withArgs(ZERO_ADDRESS, await bob.getAddress(), quote.quoteData.expectedInvestmentAmount)
                        .to.emit(ovToken, "VestedReservesAdded")
                        .withArgs(expectedNewReserves)
                        .to.emit(ovToken, "Invested")
                        .withArgs(await bob.getAddress(), expectedNewReserves, oToken.address, quote.quoteData.expectedInvestmentAmount);
                },
                    [oToken, bob, amount.mul(-1)],
                    [oToken, ovToken, expectedNewReserves],
                    [ovToken, bob, quote.quoteData.expectedInvestmentAmount],
                );

                expect(await oToken.totalSupply()).eq(oTokenSupply.add(expectedNewReserves));
                expect(await ovToken.totalReserves()).eq(osReservesSupply.add(expectedNewReserves));
                expect(await ovToken.totalSupply()).eq(ovTokenSupply.add(quote.quoteData.expectedInvestmentAmount));
            }
        };
        
        // Another allowed token, with fees
        const investWithOtherToken = async () => {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();

            const amount = ethers.utils.parseEther("1000");
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const underlyingQuoteData = decodeInvestQuoteData(quote.quoteData.underlyingInvestmentQuoteData);
            const expectedNewReserves = underlyingQuoteData.expectedInvestmentAmount as BigNumber;

            await underlyingInvestToken.connect(operator).mint(bob.getAddress(), amount);
            await underlyingInvestToken.connect(bob).approve(ovToken.address, amount);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).investWithToken(quote.quoteData))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(ZERO_ADDRESS, await bob.getAddress(), quote.quoteData.expectedInvestmentAmount)
                    .to.emit(ovToken, "VestedReservesAdded")
                    .withArgs(expectedNewReserves)
                    .to.emit(oToken, "Invested")
                    .withArgs(ovToken.address, amount, underlyingInvestToken.address, expectedNewReserves)
                    .to.emit(ovToken, "Invested")
                    .withArgs(await bob.getAddress(), amount, underlyingInvestToken.address, quote.quoteData.expectedInvestmentAmount);
            },
                [underlyingInvestToken, bob, amount.mul(-1)],
                [underlyingInvestToken, oToken, amount],
                [oToken, bob, 0],
                [oToken, ovToken, expectedNewReserves],
                [ovToken, bob, quote.quoteData.expectedInvestmentAmount],
            );
            
            expect(await oToken.totalSupply()).eq(oTokenSupply.add(expectedNewReserves));
            expect(await ovToken.totalReserves()).eq(osReservesSupply.add(expectedNewReserves));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.add(quote.quoteData.expectedInvestmentAmount));
        };

        // Can't get a quote for 0
        {
            const quoteData = {
                ...(await ovToken.investQuote(100, underlyingInvestToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                fromTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).investWithToken(quoteData))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
        }

        await investWithReserveToken();
        await investWithOtherToken();
        
        // Add some more reserves and go again
        {
            const reservesPerShare = await bootstrapReserves();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            expect(reservesPerShare).eq(ONE_ETH.mul(osReservesSupply).div(ovTokenSupply));
        }

        await investWithReserveToken();
        await investWithOtherToken();

        // Check slippage is applied
        {
            const amount = ethers.utils.parseEther("1000");
            await oToken.connect(operator).mint(bob.getAddress(), amount);
            await oToken.connect(bob).approve(ovToken.address, amount);

            // A quote for 0 slippage
            const quoteData = (await ovToken.investQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            const minAmountOut = quoteData.minInvestmentAmount.add(1);
            const manualQuoteData = {
                ...quoteData,
                minInvestmentAmount: minAmountOut
            };

            // Fails when asking for too much
            await expect(ovToken.connect(bob).investWithToken(manualQuoteData))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(minAmountOut, quoteData.expectedInvestmentAmount);

            // Works with the right min amount
            await expect(ovToken.connect(bob).investWithToken(quoteData))
                .to.emit(ovToken, "Invested");
        }
    });

    it("correctly wrapped invest with native", async () => {       
        const investWithNative = async () => {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();

            const amount = ethers.utils.parseEther("1");
            const quote = await ovToken.investQuote(amount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const underlyingQuoteData = decodeInvestQuoteData(quote.quoteData.underlyingInvestmentQuoteData);
            const expectedNewReserves = underlyingQuoteData.expectedInvestmentAmount as BigNumber;

            const bobEthBefore = await getEthBalance(bob);
            const oTokenEthBefore = await getEthBalance(oToken);

            await expectBalancesChangeBy(async () => {
                await expect(ovToken.connect(bob).investWithNative(quote.quoteData, {value: amount}))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(ZERO_ADDRESS, await bob.getAddress(), quote.quoteData.expectedInvestmentAmount)
                    .to.emit(ovToken, "VestedReservesAdded")
                    .withArgs(expectedNewReserves);
            },
                [oToken, ovToken, expectedNewReserves],
                [ovToken, bob, quote.quoteData.expectedInvestmentAmount],
            );

            const bobEthAfter = await getEthBalance(bob);
            const oTokenEthAfter = await getEthBalance(oToken);

            // A very rough expectation of gas cost to bob which gets deducted from the expected diff.
            const expectedGas = ethers.utils.parseEther("0.0001");
            expectApproxEqRel(bobEthAfter.sub(bobEthBefore).mul(-1).sub(expectedGas), amount, tolerance(0.01));
            expect(oTokenEthAfter.sub(oTokenEthBefore)).eq(amount);
            
            expect(await oToken.totalSupply()).eq(oTokenSupply.add(expectedNewReserves));
            expect(await ovToken.totalReserves()).eq(osReservesSupply.add(expectedNewReserves));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.add(quote.quoteData.expectedInvestmentAmount));
        };

        // Error checking
        {
            let quoteData = (await ovToken.investQuote(100, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;

            // Different amount of eth passed in
            await expect(ovToken.connect(bob).investWithNative(quoteData, {value: 111}))
                .to.revertedWithCustomError(ovToken, "InvalidAmount")
                .withArgs(ZERO_ADDRESS, 111);

            // Non-zero
            quoteData = {
                ...quoteData,
                fromTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).investWithNative(quoteData, {value: 0}))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");

            // non-eth token
            quoteData = {
                ...quoteData,
                fromTokenAmount: BigNumber.from(100),
                fromToken: underlyingInvestToken.address,
            };
            await expect(ovToken.connect(bob).investWithNative(quoteData, {value: 100}))
                .to.revertedWithCustomError(ovToken, "InvalidToken")
                .withArgs(underlyingInvestToken.address);
        }

        await investWithNative();
        
        // Add some more reserves and go again
        {
            const reservesPerShare = await bootstrapReserves();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            expect(reservesPerShare).eq(ONE_ETH.mul(osReservesSupply).div(ovTokenSupply));
        }

        await investWithNative();

        // Check slippage is applied
        {
            const amount = ethers.utils.parseEther("1000");

            // A quote for 0 slippage
            const quoteData = (await ovToken.investQuote(amount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            const minAmountOut = quoteData.minInvestmentAmount.add(1);
            const manualQuoteData = {
                ...quoteData,
                minInvestmentAmount: minAmountOut
            };

            // Fails when asking for too much
            await expect(ovToken.connect(bob).investWithNative(manualQuoteData, {value:amount}))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(minAmountOut, quoteData.expectedInvestmentAmount);

            // Works with the right min amount
            await expect(ovToken.connect(bob).investWithNative(quoteData, {value:amount}))
                .to.emit(ovToken, "Invested");
        }
    });

    it("correctly wrapped exit to token", async () => {
        await bootstrapReserves();
        const amount = ethers.utils.parseEther("1000");

        // Can't get a quote for 0
        {
            const quoteData = {
                ...(await ovToken.exitQuote(100, underlyingInvestToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                investmentTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).exitToToken(quoteData, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
        }

        // Bob has no investment token - so it fails
        {
            const quote = await ovToken.exitQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

            // Bob doesn't have any ovToken's yet
            await expect(ovToken.connect(bob).exitToToken(quote.quoteData, bob.getAddress()))
                .to.be.revertedWithCustomError(ovToken, "InsufficientBalance")
                .withArgs(ovToken.address, amount, 0);
        }

        {
            // Mint oToken to bob and invest
            const reservesAmount = amount.mul(10);
            await oToken.connect(operator).mint(bob.getAddress(), reservesAmount);
            await oToken.connect(bob).approve(ovToken.address, reservesAmount);
            const quote = await ovToken.investQuote(reservesAmount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await ovToken.connect(bob).investWithToken(quote.quoteData);

            // Also mint the ovToken some underlyingInvestToken so positions can exit
            await underlyingExitToken.connect(operator).mint(oToken.address, ethers.utils.parseEther("100000"));
        }

        // Sell to the reserve token
        {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            
            const quote = await ovToken.exitQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).exitToToken(quote.quoteData, alan.getAddress()))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(await bob.getAddress(), ZERO_ADDRESS, amount)
                    .to.emit(oToken, "Transfer")
                    .withArgs(ovToken.address, await alan.getAddress(), quote.quoteData.expectedToTokenAmount)
                    .to.emit(ovToken, "VestedReservesRemoved")
                    .withArgs(quote.quoteData.expectedToTokenAmount)
                    .to.emit(ovToken, "Exited")
                    .withArgs(await bob.getAddress(), amount, oToken.address, quote.quoteData.expectedToTokenAmount, await alan.getAddress());
            },
                [oToken, alan, quote.quoteData.expectedToTokenAmount],
                [oToken, bob, 0],
                [oToken, ovToken, quote.quoteData.expectedToTokenAmount.mul(-1)],
                [ovToken, bob, amount.mul(-1)],
            );

            expect(await oToken.totalSupply()).eq(oTokenSupply);
            expect(await ovToken.totalReserves()).eq(osReservesSupply.sub(quote.quoteData.expectedToTokenAmount));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.sub(amount));
        }

        // Sell to a different token
        {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).exitToToken(quote.quoteData, alan.getAddress()))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(await bob.getAddress(), ZERO_ADDRESS, amount)
                    .to.emit(ovToken, "VestedReservesRemoved")
                    .withArgs(expectedReserveAmount)
                    .to.emit(ovToken, "Exited")
                    .withArgs(await bob.getAddress(), amount, underlyingExitToken.address, quote.quoteData.expectedToTokenAmount, await alan.getAddress())
                    .to.emit(oToken, "Exited")
                    .withArgs(ovToken.address, expectedReserveAmount, underlyingExitToken.address, quote.quoteData.expectedToTokenAmount, await alan.getAddress())
                    .to.emit(underlyingExitToken, "Transfer")
                    .withArgs(oToken.address, await alan.getAddress(), quote.quoteData.expectedToTokenAmount);
                },
                [underlyingExitToken, alan, quote.quoteData.expectedToTokenAmount],
                [underlyingExitToken, bob, 0],
                [underlyingExitToken, oToken, quote.quoteData.expectedToTokenAmount.mul(-1)],
                [ovToken, bob, amount.mul(-1)],
                [oToken, ovToken, expectedReserveAmount.mul(-1)],
            );

            expect(await oToken.totalSupply()).eq(oTokenSupply.sub(expectedReserveAmount));
            expect(await ovToken.totalReserves()).eq(osReservesSupply.sub(expectedReserveAmount));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.sub(amount));
        }

        // Check slippage is applied for reserve token
        {
            // A quote for 0 slippage
            const quoteData = (await ovToken.exitQuote(amount, oToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            const minAmountOut = quoteData.minToTokenAmount.add(1);
            const manualQuoteData = {
                ...quoteData,
                minToTokenAmount: minAmountOut
            };

            // Fails when asking for too much
            await expect(ovToken.connect(bob).exitToToken(manualQuoteData, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(minAmountOut, quoteData.expectedToTokenAmount);

            // Works with the right min amount
            await expect(ovToken.connect(bob).exitToToken(quoteData, bob.getAddress()))
                .to.emit(ovToken, "Exited");
        }

        // Check slippage is applied for other token
        {
            // A quote for 0 slippage
            const quoteData = (await ovToken.exitQuote(amount, underlyingExitToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            const minAmountOut = quoteData.minToTokenAmount.add(1);
            const manualQuoteData = {
                ...quoteData,
                minToTokenAmount: minAmountOut
            };

            // Fails with slippage
            await expect(ovToken.connect(bob).exitToToken(manualQuoteData, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(minAmountOut, quoteData.expectedToTokenAmount);

            // Works with the right min amount
            await expect(ovToken.connect(bob).exitToToken(quoteData, bob.getAddress()))
                .to.emit(ovToken, "Exited");
        }
    });

    it("correctly wrapped exit to ETH", async () => {
        await bootstrapReserves();
        const amount = ethers.utils.parseEther("100");

        // Error checking in quote
        {
            // Can't get a quote for 0
            let quoteData = {
                ...(await ovToken.exitQuote(100, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData,
                investmentTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).exitToNative(quoteData, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");

            // non 0x address
            quoteData = {
                ...quoteData,
                investmentTokenAmount: BigNumber.from(100),
                toToken: underlyingExitToken.address
            };
            await expect(ovToken.connect(bob).exitToNative(quoteData, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "InvalidToken")
                .withArgs(underlyingExitToken.address);
        }

        // Bob has no investment token - so it fails
        {
            const quote = await ovToken.exitQuote(amount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);

            // Bob doesn't have any ovToken's yet
            await expect(ovToken.connect(bob).exitToNative(quote.quoteData, bob.getAddress()))
                .to.be.revertedWithCustomError(ovToken, "InsufficientBalance")
                .withArgs(ovToken.address, amount, 0);
        }

        // First invest with ETH
        {
            const reservesAmount = ethers.utils.parseEther("500");
            const quote = await ovToken.investQuote(reservesAmount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await ovToken.connect(bob).investWithNative(quote.quoteData, {value: reservesAmount});
            expect(await getEthBalance(oToken)).eq(reservesAmount);
            expect(await ovToken.balanceOf(bob.getAddress())).eq(quote.quoteData.expectedInvestmentAmount);
        }

        // Can now exit to ETH
        {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            
            const quote = await ovToken.exitQuote(amount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);

            const bobEthBefore = await getEthBalance(bob);
            const alanEthBefore = await getEthBalance(alan);
            const oTokenEthBefore = await getEthBalance(oToken);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).exitToNative(quote.quoteData, alan.getAddress()))
                .to.emit(ovToken, "Transfer")
                .withArgs(await bob.getAddress(), ZERO_ADDRESS, amount)
                .to.emit(ovToken, "VestedReservesRemoved")
                .withArgs(expectedReserveAmount)
                .to.emit(ovToken, "Exited")
                .withArgs(await bob.getAddress(), amount, ZERO_ADDRESS, quote.quoteData.expectedToTokenAmount, await alan.getAddress())
                .to.emit(oToken, "Exited")
                .withArgs(ovToken.address, expectedReserveAmount, ZERO_ADDRESS, quote.quoteData.expectedToTokenAmount, await alan.getAddress())
            },
                [ovToken, bob, amount.mul(-1)],
                [oToken, ovToken, expectedReserveAmount.mul(-1)],
            );

            const bobEthAfter = await getEthBalance(bob);
            const alanEthAfter = await getEthBalance(alan);
            const oTokenEthAfter = await getEthBalance(oToken);
            expectApproxEqRel(bobEthAfter, bobEthBefore, MAX_REL_DELTA); // Bob paid for gas only
            expect(alanEthAfter.sub(alanEthBefore)).eq(quote.quoteData.expectedToTokenAmount);
            expect(oTokenEthAfter.sub(oTokenEthBefore).mul(-1)).eq(quote.quoteData.expectedToTokenAmount);
            
            expect(await oToken.totalSupply()).eq(oTokenSupply.sub(expectedReserveAmount));
            expect(await ovToken.totalReserves()).eq(osReservesSupply.sub(expectedReserveAmount));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.sub(amount));
        }

        // Check slippage is applie
        {
            // A quote for 0 slippage
            const quoteData = (await ovToken.exitQuote(amount, ZERO_ADDRESS, ZERO_SLIPPAGE, ZERO_DEADLINE)).quoteData;
            const minAmountOut = quoteData.minToTokenAmount.add(1);
            const manualQuoteData = {
                ...quoteData,
                minToTokenAmount: minAmountOut
            };

            // Fails with slippage
            await expect(ovToken.connect(bob).exitToNative(manualQuoteData, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(minAmountOut, quoteData.expectedToTokenAmount);

            // Works with the right min amount
            await expect(ovToken.connect(bob).exitToNative(quoteData, bob.getAddress()))
                .to.emit(ovToken, "Exited");
        }
    });

    it("should invest -> addPendingReserves -> exit correctly", async () => {
        // Invest
        const startingAmount = ethers.utils.parseEther("1000");
        let numShares = BigNumber.from(0);
        {

            const quote = await ovToken.investQuote(startingAmount, underlyingInvestToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            numShares = quote.quoteData.expectedInvestmentAmount;

            await underlyingInvestToken.connect(operator).mint(bob.getAddress(), startingAmount);
            await underlyingInvestToken.connect(bob).approve(ovToken.address, startingAmount);
            await ovToken.connect(bob).investWithToken(quote.quoteData);
        }

        // Add some more reserves
        let reservesPerShare: BigNumber;
        {
            reservesPerShare = await bootstrapReserves();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            expect(reservesPerShare).eq(ONE_ETH.mul(osReservesSupply).div(ovTokenSupply));

            // Mint some exit tokens to the oToken so we can exit
            await underlyingExitToken.connect(operator).mint(oToken.address, ethers.utils.parseEther("100000"));
        }

        // Now Exit
        {
            const quote = await ovToken.exitQuote(numShares, underlyingExitToken.address, ZERO_SLIPPAGE, ZERO_DEADLINE);
            await ovToken.connect(bob).exitToToken(quote.quoteData, bob.getAddress());
        }

        const finalAmount = await underlyingExitToken.balanceOf(bob.getAddress());
        const one_eth = ethers.utils.parseEther("1");
        const expectedFinalAmount = startingAmount
            .mul(99).div(100) // 1% invest fee
            .mul(reservesPerShare).div(one_eth)
            .mul(95).div(100);  // 5% exit fee
        expectApproxEqRel(finalAmount, expectedFinalAmount, MAX_REL_DELTA);
    });

    it("Calculate APR", async () => {
        // When no shares issued, apr = 0
        expect(await ovToken.apr()).eq(0);

        const invest = async (amount: number) => {
            // Mint to alan
            const investAmount = ethers.utils.parseEther(amount.toString());
            await oToken.connect(operator).mint(alan.getAddress(), investAmount);
            await oToken.connect(alan).approve(ovToken.address, investAmount);

            // Alan invests 10k
            const quote = await ovToken.investQuote(investAmount, oToken.address, 50, ZERO_DEADLINE);
            await ovToken.connect(alan).investWithToken(quote.quoteData, {gasLimit:5000000});
        }

        const checkApr = async (weeklyDistribution: number, reserves: number) => {
            const annualDistribution = weeklyDistribution * 365 / 7;
            const expectedApr = Math.floor(10_000 * annualDistribution / reserves);
            expect(await ovToken.apr()).eq(expectedApr);
        }

        // Bootstrap some base reserves - Alan invests 20k
        const intitialReserves = 20_000;
        await invest(intitialReserves);

        // Add some pending reserves
        const currentWeeklyDistribution = 150;
        await addPendingReserves(ethers.utils.parseEther(currentWeeklyDistribution.toString()));
        await checkApr(currentWeeklyDistribution, intitialReserves);
        
        // After moving forward a day but not adding any new pending reserves,
        // the reserves per second remains the same.
        await mineForwardSeconds(86400);
        await checkApr(currentWeeklyDistribution, intitialReserves);

        // Now add a new distribution of daily compounded rewards.
        // This distribution gets added to the remaining 6 days of unvested pending rewards.
        const newDailyDistribution = 35;
        await addPendingReserves(ethers.utils.parseEther(newDailyDistribution.toString()));
        await checkApr(currentWeeklyDistribution * 6/7 + newDailyDistribution, currentWeeklyDistribution * 1/7 + intitialReserves);

        // A new investment decreases the APR
        const extraInvestment = 5_000;
        await invest(extraInvestment);
        await checkApr(currentWeeklyDistribution * 6/7 + newDailyDistribution, currentWeeklyDistribution * 1/7 + intitialReserves + extraInvestment);

        // Moving forward over a week with no new pending reserves => 0% APR
        await mineForwardSeconds(7*86400);
        await ovToken.checkpointReserves();
        await checkApr(0, intitialReserves + currentWeeklyDistribution + newDailyDistribution);
    });
});
