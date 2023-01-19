import { ethers } from "hardhat";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyOrigamiInvestment, DummyOrigamiInvestment__factory, 
    DummyOrigamiInvestmentManager, DummyOrigamiInvestmentManager__factory,
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory, 
    TokenPrices, TokenPrices__factory,
    MintableToken__factory,
    MintableToken,
    IOrigamiInvestment,
    DummyOracle__factory,
} from "../../typechain";
import { 
    expectBalancesChangeBy, 
    shouldRevertNotOwner, shouldRevertPaused, 
    ZERO_ADDRESS, EmptyBytes, 
    slightlyGte, slightlyLte,
    getEthBalance,
    encodeInvestQuoteData,
    decodeInvestQuoteData, 
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

const ONE_ETH = ethers.utils.parseEther("1");

describe("Origami Investment Vault", async () => {
    let owner: Signer;
    let operator: Signer;
    let alan: Signer;
    let bob: Signer;
    let oToken: DummyOrigamiInvestment;
    let ovToken: OrigamiInvestmentVault;
    let tokenPrices: TokenPrices;
    let investmentManager: DummyOrigamiInvestmentManager;
    let underlyingInvestToken: MintableToken;
    let underlyingExitToken: MintableToken;
    let rewardToken1: MintableToken;
    let rewardToken2: MintableToken;
    
    before( async () => {
        [owner, operator, alan, bob] = await ethers.getSigners();
    });

    async function setup() {
        // Setup oToken
        {
            underlyingInvestToken = await new MintableToken__factory(owner).deploy("investToken", "investToken");
            underlyingInvestToken.addMinter(operator.getAddress());
            underlyingExitToken = await new MintableToken__factory(owner).deploy("exitToken", "exitToken");
            underlyingExitToken.addMinter(operator.getAddress());
            oToken = await new DummyOrigamiInvestment__factory(owner).deploy(
                "oToken", "oToken", 
                underlyingInvestToken.address, 
                underlyingExitToken.address
            );
            await oToken.addMinter(operator.getAddress());
        }
        
        // Setup ovToken
        {
            tokenPrices = await new TokenPrices__factory(owner).deploy(30);
            ovToken = await new OrigamiInvestmentVault__factory(owner).deploy("ovToken", "ovToken", oToken.address, tokenPrices.address, 5);
            await ovToken.addOperator(operator.getAddress());
        }
        
        // Setup investment manager
        {
            rewardToken1 = await new MintableToken__factory(owner).deploy("rwd1", "rwd1");
            rewardToken2 = await new MintableToken__factory(owner).deploy("rwd2", "rwd2");
            investmentManager = await new DummyOrigamiInvestmentManager__factory(owner).deploy(
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

            // Set $rewardToken1 == 30
            const rewardToken1UsdOracle = await new DummyOracle__factory(owner).deploy(BigNumber.from("3000000000"), 8);
            const encodedRewardToken1UsdOracle = tokenPricesInterface.encodeFunctionData("oraclePrice", [rewardToken1UsdOracle.address]);
            await tokenPrices.setTokenPriceFunction(rewardToken1.address, encodedRewardToken1UsdOracle);

            // Set $rewardToken1 == 50
            const rewardToken2UsdOracle = await new DummyOracle__factory(owner).deploy(BigNumber.from("5000000000"), 8);
            const encodedRewardToken2UsdOracle = tokenPricesInterface.encodeFunctionData("oraclePrice", [rewardToken2UsdOracle.address]);
            await tokenPrices.setTokenPriceFunction(rewardToken2.address, encodedRewardToken2UsdOracle);

            // Set $oToken == 15
            const oTokenUsdOracle = await new DummyOracle__factory(owner).deploy(BigNumber.from("1500000000"), 8);
            const encodedoTokenUsdOracle = tokenPricesInterface.encodeFunctionData("oraclePrice", [oTokenUsdOracle.address]);
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

    // Invest and add extra reserves to bump the price
    const bootstrapReserves = async (): Promise<BigNumber> => {
        // Mint to alan
        const investAmount = ethers.utils.parseEther("10000");
        await oToken.connect(operator).mint(alan.getAddress(), investAmount);
        await oToken.connect(alan).approve(ovToken.address, investAmount);

        // Alan invests 10k
        const quote = await ovToken.investQuote(investAmount, oToken.address);
        await ovToken.connect(alan).investWithToken(quote.quoteData, 0);

        // Mint to operator
        const extraReservesAmount = ethers.utils.parseEther("1000");
        await oToken.connect(operator).mint(operator.getAddress(), extraReservesAmount);
        await oToken.connect(operator).approve(ovToken.address, extraReservesAmount);

        // Add reserves for the other 10k
        await ovToken.connect(operator).addReserves(extraReservesAmount);

        const reservesPerShare = await ovToken.reservesPerShare();
        return reservesPerShare;
    }

    it("constructor", async () => {
        expect(await ovToken.reserveToken()).eq(oToken.address);
        expect(await ovToken.tokenPrices()).eq(tokenPrices.address);
        const [numerator, denominator] = await ovToken.performanceFee();
        expect(numerator.toNumber()).to.eq(5);
        expect(denominator.toNumber()).to.eq(100);
    });

    it("admin", async () => {
        await shouldRevertNotOwner(ovToken.connect(alan).setInvestmentManager(investmentManager.address));
        await shouldRevertNotOwner(ovToken.connect(alan).setTokenPrices(tokenPrices.address));
        await shouldRevertNotOwner(ovToken.connect(alan).setPerformanceFee(80, 100));

        await expect(ovToken.connect(alan).addReserves(0))
            .to.revertedWithCustomError(ovToken, "OnlyOperators")
            .withArgs(await alan.getAddress());
        await expect(ovToken.connect(alan).removeReserves(0))
            .to.revertedWithCustomError(ovToken, "OnlyOperators")
            .withArgs(await alan.getAddress());

        // Happy paths
        await ovToken.setInvestmentManager(investmentManager.address);
        await ovToken.setTokenPrices(tokenPrices.address);
        await ovToken.setPerformanceFee(80, 100);
    });

    it("owner can set the investment manager", async () => {           
        await expect(ovToken.setInvestmentManager(ZERO_ADDRESS))
            .to.be.revertedWithCustomError(ovToken, "InvalidAddress")
            .withArgs(ZERO_ADDRESS);
        await expect(ovToken.setInvestmentManager(investmentManager.address))
            .to.emit(ovToken, "InvestmentManagerSet")
            .withArgs(investmentManager.address);
        expect(await ovToken.investmentManager()).to.eq(investmentManager.address);
    });

    it("owner can set token prices", async () => {           
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

    const exitQuoteTypes = 'tuple(uint256 expectedReserveAmount, tuple(uint256 investmentTokenAmount, address toToken, uint256 expectedToTokenAmount, bytes underlyingInvestmentQuoteData) underlyingExitQuoteData)';
    const encodeUnderlyingExitQuoteData = (expectedReserveAmount: BigNumberish, quoteData: IOrigamiInvestment.ExitQuoteDataStruct): string => {
        return ethers.utils.defaultAbiCoder.encode(
            [exitQuoteTypes], 
            [{
                expectedReserveAmount: expectedReserveAmount,
                underlyingExitQuoteData: quoteData,
            }]
        );
    }

    type UnderlyingExitQuoteData = {
        expectedReserveAmount: BigNumberish,
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
        await expect(ovToken.investQuote(0, oToken.address))
            .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
        
        // The reserve token, expected 1:1 since no reserves yet added
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.investQuote(amount, oToken.address);
            const expectedSharesAmount = await ovToken.reservesToShares(amount);
            expect(expectedSharesAmount).eq(amount);

            expect(quote.quoteData.fromToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.investFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address);
            const underlyingQuote = await oToken.investQuote(amount, underlyingInvestToken.address);
            const expectedSharesAmount = await ovToken.reservesToShares(underlyingQuote.quoteData.expectedInvestmentAmount);
            expect(expectedSharesAmount).eq(amount.mul(9_900).div(10_000));

            expect(quote.quoteData.fromToken).eq(underlyingInvestToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
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
            const quote = await ovToken.investQuote(amount, oToken.address);
            const expectedSharesAmount = await ovToken.reservesToShares(amount);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedSharesAmount).eq(amount.mul(ONE_ETH).div(reservesPerShare));

            expect(quote.quoteData.fromToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.investFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees. Now expect less shares as the price has increased
        {
            const amount = ethers.utils.parseEther("1000");
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address);
            const underlyingQuote = await oToken.investQuote(amount, underlyingInvestToken.address);
            const expectedSharesAmount = await ovToken.reservesToShares(underlyingQuote.quoteData.expectedInvestmentAmount);

            // Now expect less shares for the same amount of reserves, 
            // since there is a fee, and also the reservesPerShare has now gone up
            expect(expectedSharesAmount).eq(amount.mul(9_900).div(10_000).mul(ONE_ETH).div(reservesPerShare));

            expect(quote.quoteData.fromToken).eq(underlyingInvestToken.address);
            expect(quote.quoteData.fromTokenAmount).eq(amount);
            expect(quote.quoteData.expectedInvestmentAmount).eq(expectedSharesAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeInvestQuoteData(underlyingQuote.quoteData)
            );
            expect(quote.investFeeBps).deep.eq([100]);
        }
    });

    it("correctly wrapped exit quote", async () => {
        // Can't give quote for 0 amount        
        await expect(ovToken.exitQuote(0, oToken.address))
            .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
    
        // The reserve token, expected 0 since no shares
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, oToken.address);
            expect(quote.quoteData.expectedToTokenAmount).eq(0);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.expectedToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.exitFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            expect(quote.quoteData.expectedToTokenAmount).eq(0);
            const underlyingQuote = await oToken.exitQuote(expectedReserveAmount, underlyingExitToken.address);

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(underlyingExitToken.address);
            expect(quote.quoteData.expectedToTokenAmount).eq(underlyingQuote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeUnderlyingExitQuoteData(expectedReserveAmount, underlyingQuote.quoteData)
            );
            expect(quote.exitFeeBps).deep.eq([500]);
        }

        const reservesPerShare = await bootstrapReserves();
        expect(reservesPerShare).eq(ONE_ETH.mul(11_000).div(10_000));

        // The reserve token, expected 1:1 since no reserves yet added
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, oToken.address);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedReserveAmount).eq(amount.mul(reservesPerShare).div(ONE_ETH));

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(oToken.address).eq(await ovToken.reserveToken());
            expect(quote.quoteData.expectedToTokenAmount).eq(expectedReserveAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(EmptyBytes);
            expect(quote.exitFeeBps).deep.eq([]);
        }

        // Another allowed token, with fees
        {
            const amount = ethers.utils.parseEther("100");
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            const underlyingQuote = await oToken.exitQuote(expectedReserveAmount, underlyingExitToken.address);

            // Now expect less shares for the same amount of reserves, 
            // since the reservesPerShare has now gone up
            expect(expectedReserveAmount).eq(amount.mul(reservesPerShare).div(ONE_ETH));

            expect(quote.quoteData.investmentTokenAmount).eq(amount);
            expect(quote.quoteData.toToken).eq(underlyingExitToken.address);
            expect(quote.quoteData.expectedToTokenAmount).eq(underlyingQuote.quoteData.expectedToTokenAmount);
            expect(quote.quoteData.underlyingInvestmentQuoteData).eq(
                encodeUnderlyingExitQuoteData(expectedReserveAmount, underlyingQuote.quoteData)
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
                const quote = await ovToken.investQuote(amount, oToken.address);
                const expectedNewReserves = amount;

                await oToken.connect(operator).mint(bob.getAddress(), amount);
                await oToken.connect(bob).approve(ovToken.address, amount);

                await expectBalancesChangeBy(async () => { 
                    await expect(ovToken.connect(bob).investWithToken(quote.quoteData, 0))
                        .to.emit(ovToken, "Transfer")
                        .withArgs(ZERO_ADDRESS, await bob.getAddress(), quote.quoteData.expectedInvestmentAmount)
                        .to.emit(ovToken, "ReservesAdded")
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
            const quote = await ovToken.investQuote(amount, underlyingInvestToken.address);
            const underlyingQuoteData = decodeInvestQuoteData(quote.quoteData.underlyingInvestmentQuoteData);
            const expectedNewReserves = underlyingQuoteData.expectedInvestmentAmount as BigNumber;

            await underlyingInvestToken.connect(operator).mint(bob.getAddress(), amount);
            await underlyingInvestToken.connect(bob).approve(ovToken.address, amount);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).investWithToken(quote.quoteData, 0))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(ZERO_ADDRESS, await bob.getAddress(), quote.quoteData.expectedInvestmentAmount)
                    .to.emit(ovToken, "ReservesAdded")
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
                ...(await ovToken.investQuote(100, underlyingInvestToken.address)).quoteData,
                fromTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).investWithToken(quoteData, 0))
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

            // Add 1% to the expected amount
            let quoteData = (await ovToken.investQuote(amount, oToken.address)).quoteData;
            const expectedInvestmentAmount = quoteData.expectedInvestmentAmount;
            quoteData = {
                ...quoteData,
                expectedInvestmentAmount: expectedInvestmentAmount.mul(10_100).div(10_000),
            };

            await oToken.connect(operator).mint(bob.getAddress(), amount);
            await oToken.connect(bob).approve(ovToken.address, amount);

            // Fails with slippage
            await expect(ovToken.connect(bob).investWithToken(quoteData, 0))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(quoteData.expectedInvestmentAmount, expectedInvestmentAmount);

            // Now with 1% slippage works
            await expect(ovToken.connect(bob).investWithToken(quoteData, 100))
                .to.emit(ovToken, "Invested");
        }
    });

    it("correctly wrapped invest with native", async () => {       
        const investWithNative = async () => {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();

            const amount = ethers.utils.parseEther("1");
            const quote = await ovToken.investQuote(amount, ZERO_ADDRESS);
            const underlyingQuoteData = decodeInvestQuoteData(quote.quoteData.underlyingInvestmentQuoteData);
            const expectedNewReserves = underlyingQuoteData.expectedInvestmentAmount as BigNumber;

            const bobEthBefore = await getEthBalance(bob);
            const oTokenEthBefore = await getEthBalance(oToken);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).investWithNative(quote.quoteData, 0, {value: amount}))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(ZERO_ADDRESS, await bob.getAddress(), quote.quoteData.expectedInvestmentAmount)
                    .to.emit(ovToken, "ReservesAdded")
                    .withArgs(expectedNewReserves);
            },
                [oToken, ovToken, expectedNewReserves],
                [ovToken, bob, quote.quoteData.expectedInvestmentAmount],
            );

            const bobEthAfter = await getEthBalance(bob);
            const oTokenEthAfter = await getEthBalance(oToken);
            expect(slightlyGte(bobEthAfter.sub(bobEthBefore).mul(-1), amount, 0.0005)).true;
            expect(oTokenEthAfter.sub(oTokenEthBefore)).eq(amount);
            
            expect(await oToken.totalSupply()).eq(oTokenSupply.add(expectedNewReserves));
            expect(await ovToken.totalReserves()).eq(osReservesSupply.add(expectedNewReserves));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.add(quote.quoteData.expectedInvestmentAmount));
        };

        // Error checking
        {
            let quoteData = (await ovToken.investQuote(100, ZERO_ADDRESS)).quoteData;

            // Different amount of eth passed in
            await expect(ovToken.connect(bob).investWithNative(quoteData, 100, {value: 111}))
                .to.revertedWithCustomError(ovToken, "InvalidAmount")
                .withArgs(ZERO_ADDRESS, 111);

            // Non-zero
            quoteData = {
                ...quoteData,
                fromTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).investWithNative(quoteData, 0, {value: 0}))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");

            // non-eth token
            quoteData = {
                ...quoteData,
                fromTokenAmount: BigNumber.from(100),
                fromToken: underlyingInvestToken.address,
            };
            await expect(ovToken.connect(bob).investWithNative(quoteData, 0, {value: 100}))
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

            // Add 1% to the expected amount
            let quoteData = (await ovToken.investQuote(amount, ZERO_ADDRESS)).quoteData;
            const expectedInvestmentAmount = quoteData.expectedInvestmentAmount;
            quoteData = {
                ...quoteData,
                expectedInvestmentAmount: expectedInvestmentAmount.mul(10_100).div(10_000),
            };

            // Fails with slippage
            await expect(ovToken.connect(bob).investWithNative(quoteData, 0, {value:amount}))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(quoteData.expectedInvestmentAmount, expectedInvestmentAmount);

            // Now with 1% slippage works
            await expect(ovToken.connect(bob).investWithNative(quoteData, 100, {value:amount}))
                .to.emit(ovToken, "Invested");
        }
    });

    it("correctly wrapped exit to token", async () => {
        await bootstrapReserves();
        const amount = ethers.utils.parseEther("1000");

        // Can't get a quote for 0
        {
            const quoteData = {
                ...(await ovToken.exitQuote(100, underlyingInvestToken.address)).quoteData,
                investmentTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).exitToToken(quoteData, 0, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");
        }

        // Bob has no investment token - so it fails
        {
            const quote = await ovToken.exitQuote(amount, oToken.address);

            // Bob doesn't have any ovToken's yet
            await expect(ovToken.connect(bob).exitToToken(quote.quoteData, 0, bob.getAddress()))
                .to.be.revertedWithCustomError(ovToken, "InsufficientBalance")
                .withArgs(ovToken.address, amount, 0);
        }

        {
            // Mint oToken to bob and invest
            const reservesAmount = amount.mul(10);
            await oToken.connect(operator).mint(bob.getAddress(), reservesAmount);
            await oToken.connect(bob).approve(ovToken.address, reservesAmount);
            const quote = await ovToken.investQuote(reservesAmount, oToken.address);
            await ovToken.connect(bob).investWithToken(quote.quoteData, 0);

            // Also mint the ovToken some underlyingInvestToken so positions can exit
            await underlyingExitToken.connect(operator).mint(oToken.address, ethers.utils.parseEther("100000"));
        }

        // Sell to the reserve token
        {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            
            const quote = await ovToken.exitQuote(amount, oToken.address);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).exitToToken(quote.quoteData, 0, bob.getAddress()))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(await bob.getAddress(), ZERO_ADDRESS, amount)
                    .to.emit(ovToken, "ReservesRemoved")
                    .withArgs(quote.quoteData.expectedToTokenAmount)
                    .to.emit(ovToken, "Exited")
                    .withArgs(await bob.getAddress(), amount, oToken.address, quote.quoteData.expectedToTokenAmount, await bob.getAddress());
            },
                [oToken, bob, quote.quoteData.expectedToTokenAmount],
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
            
            const quote = await ovToken.exitQuote(amount, underlyingExitToken.address);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            const underlyingQuoteData = decodeUnderlyingExitQuoteData(quote.quoteData.underlyingInvestmentQuoteData);
            expect(underlyingQuoteData.expectedReserveAmount).eq(expectedReserveAmount);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).exitToToken(quote.quoteData, 0, bob.getAddress()))
                    .to.emit(ovToken, "Transfer")
                    .withArgs(await bob.getAddress(), ZERO_ADDRESS, amount)
                    .to.emit(ovToken, "ReservesRemoved")
                    .withArgs(expectedReserveAmount)
                    .to.emit(ovToken, "Exited")
                    .withArgs(await bob.getAddress(), amount, underlyingExitToken.address, quote.quoteData.expectedToTokenAmount, await bob.getAddress())
                    .to.emit(oToken, "Exited")
                    .withArgs(ovToken.address, expectedReserveAmount, underlyingExitToken.address, quote.quoteData.expectedToTokenAmount, await bob.getAddress())
                    .to.emit(underlyingExitToken, "Transfer")
                    .withArgs(oToken.address, await bob.getAddress(), quote.quoteData.expectedToTokenAmount);
                },
                [underlyingExitToken, bob, quote.quoteData.expectedToTokenAmount],
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
            const amount = ethers.utils.parseEther("1000");

            // Add 1% to the expected amount
            let quoteData = (await ovToken.exitQuote(amount, oToken.address)).quoteData;
            const expectedToTokenAmount = quoteData.expectedToTokenAmount;
            quoteData = {
                ...quoteData,
                expectedToTokenAmount: expectedToTokenAmount.mul(10_100).div(10_000),
            };

            // Fails with slippage
            await expect(ovToken.connect(bob).exitToToken(quoteData, 0, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(quoteData.expectedToTokenAmount, expectedToTokenAmount);

            // Now with 1% slippage works
            await expect(ovToken.connect(bob).exitToToken(quoteData, 100, bob.getAddress()))
                .to.emit(ovToken, "Exited");
        }

        // Check slippage is applied for other token
        {
            const amount = ethers.utils.parseEther("1000");

            // Add 1% to the expected amount
            let quoteData = (await ovToken.exitQuote(amount, underlyingExitToken.address)).quoteData;
            const underlyingQuoteData = decodeUnderlyingExitQuoteData(quoteData.underlyingInvestmentQuoteData);
            const expectedReserveAmount = underlyingQuoteData.expectedReserveAmount;
            const expectedReserveAmountTooHigh = BigNumber.from(expectedReserveAmount).mul(10_100).div(10_000);
            quoteData = {
                ...quoteData,
                underlyingInvestmentQuoteData: encodeUnderlyingExitQuoteData(
                    expectedReserveAmountTooHigh,
                    underlyingQuoteData.underlyingExitQuoteData
                ),
            };

            // Fails with slippage
            await expect(ovToken.connect(bob).exitToToken(quoteData, 0, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(expectedReserveAmountTooHigh, expectedReserveAmount);

            // Now with 1% slippage works
            await expect(ovToken.connect(bob).exitToToken(quoteData, 100, bob.getAddress()))
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
                ...(await ovToken.exitQuote(100, ZERO_ADDRESS)).quoteData,
                investmentTokenAmount: BigNumber.from(0),
            };
            await expect(ovToken.connect(bob).exitToNative(quoteData, 0, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "ExpectedNonZero");

            // non 0x address
            quoteData = {
                ...quoteData,
                investmentTokenAmount: BigNumber.from(100),
                toToken: underlyingExitToken.address
            };
            await expect(ovToken.connect(bob).exitToNative(quoteData, 0, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "InvalidToken")
                .withArgs(underlyingExitToken.address);
        }

        // Bob has no investment token - so it fails
        {
            const quote = await ovToken.exitQuote(amount, ZERO_ADDRESS);

            // Bob doesn't have any ovToken's yet
            await expect(ovToken.connect(bob).exitToNative(quote.quoteData, 0, bob.getAddress()))
                .to.be.revertedWithCustomError(ovToken, "InsufficientBalance")
                .withArgs(ovToken.address, amount, 0);
        }

        // First invest with ETH
        {
            const reservesAmount = ethers.utils.parseEther("500");
            const quote = await ovToken.investQuote(reservesAmount, ZERO_ADDRESS);
            await ovToken.connect(bob).investWithNative(quote.quoteData, 0, {value: reservesAmount});
            expect(await getEthBalance(oToken)).eq(reservesAmount);
            expect(await ovToken.balanceOf(bob.getAddress())).eq(quote.quoteData.expectedInvestmentAmount);
        }

        // Can now exit to ETH
        {
            const oTokenSupply = await oToken.totalSupply();
            const ovTokenSupply = await ovToken.totalSupply();
            const osReservesSupply = await ovToken.totalReserves();
            
            const quote = await ovToken.exitQuote(amount, ZERO_ADDRESS);
            const expectedReserveAmount = await ovToken.sharesToReserves(amount);
            const underlyingQuoteData = decodeUnderlyingExitQuoteData(quote.quoteData.underlyingInvestmentQuoteData);
            expect(underlyingQuoteData.expectedReserveAmount).eq(expectedReserveAmount);

            const bobEthBefore = await getEthBalance(bob);
            const oTokenEthBefore = await getEthBalance(oToken);

            await expectBalancesChangeBy(async () => { 
                await expect(ovToken.connect(bob).exitToNative(quote.quoteData, 0, bob.getAddress()))
                .to.emit(ovToken, "Transfer")
                .withArgs(await bob.getAddress(), ZERO_ADDRESS, amount)
                .to.emit(ovToken, "ReservesRemoved")
                .withArgs(expectedReserveAmount)
                .to.emit(ovToken, "Exited")
                .withArgs(await bob.getAddress(), amount, ZERO_ADDRESS, quote.quoteData.expectedToTokenAmount, await bob.getAddress())
                .to.emit(oToken, "Exited")
                .withArgs(ovToken.address, expectedReserveAmount, ZERO_ADDRESS, quote.quoteData.expectedToTokenAmount, await bob.getAddress())
            },
                [ovToken, bob, amount.mul(-1)],
                [oToken, ovToken, expectedReserveAmount.mul(-1)],
            );

            const bobEthAfter = await getEthBalance(bob);
            const oTokenEthAfter = await getEthBalance(oToken);
            expect(slightlyLte(bobEthAfter.sub(bobEthBefore), quote.quoteData.expectedToTokenAmount, 0.0005)).true;
            expect(oTokenEthAfter.sub(oTokenEthBefore).mul(-1)).eq(quote.quoteData.expectedToTokenAmount);
            
            expect(await oToken.totalSupply()).eq(oTokenSupply.sub(expectedReserveAmount));
            expect(await ovToken.totalReserves()).eq(osReservesSupply.sub(expectedReserveAmount));
            expect(await ovToken.totalSupply()).eq(ovTokenSupply.sub(amount));
        }

        // Check slippage is applied
        {
            const amount = ethers.utils.parseEther("100");

            // Add 1% to the expected amount
            let quoteData = (await ovToken.exitQuote(amount, ZERO_ADDRESS)).quoteData;
            const underlyingQuoteData = decodeUnderlyingExitQuoteData(quoteData.underlyingInvestmentQuoteData);
            const expectedReserveAmount = underlyingQuoteData.expectedReserveAmount;
            const expectedReserveAmountTooHigh = BigNumber.from(expectedReserveAmount).mul(10_100).div(10_000);
            quoteData = {
                ...quoteData,
                underlyingInvestmentQuoteData: encodeUnderlyingExitQuoteData(
                    expectedReserveAmountTooHigh,
                    underlyingQuoteData.underlyingExitQuoteData
                ),
            };

            // Fails with slippage
            await expect(ovToken.connect(bob).exitToNative(quoteData, 0, bob.getAddress()))
                .to.revertedWithCustomError(ovToken, "Slippage")
                .withArgs(expectedReserveAmountTooHigh, expectedReserveAmount);

            // Now with 1% slippage works
            await expect(ovToken.connect(bob).exitToNative(quoteData, 100, bob.getAddress()))
                .to.emit(ovToken, "Exited");
        }
    });

    it("should invest -> addReserves -> exit correctly", async () => {
        // Invest
        const startingAmount = ethers.utils.parseEther("1000");
        let numShares = BigNumber.from(0);
        {

            const quote = await ovToken.investQuote(startingAmount, underlyingInvestToken.address);
            numShares = quote.quoteData.expectedInvestmentAmount;

            await underlyingInvestToken.connect(operator).mint(bob.getAddress(), startingAmount);
            await underlyingInvestToken.connect(bob).approve(ovToken.address, startingAmount);
            await ovToken.connect(bob).investWithToken(quote.quoteData, 0);
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
            const quote = await ovToken.exitQuote(numShares, underlyingExitToken.address);
            await ovToken.connect(bob).exitToToken(quote.quoteData, 0, bob.getAddress(), {gasLimit:5000000});
        }

        const finalAmount = await underlyingExitToken.balanceOf(bob.getAddress());
        const one_eth = ethers.utils.parseEther("1");
        const expectedFinalAmount = startingAmount
            .mul(99).div(100) // 1% invest fee
            .mul(reservesPerShare).div(one_eth)
            .mul(95).div(100);  // 5% exit fee
        expect(slightlyGte(finalAmount, expectedFinalAmount, BigNumber.from(10000)));
    });

    it("Calculate APR", async () => {
        // When no shares issued, apr = 0
        expect(await ovToken.apr()).eq(0);

        // Bootstrap some reserves so the ovToken price gives us a non-zero price
        await bootstrapReserves();

        const expectedTotalRewardsInUsdPerYear = (
            (
                (2.5*30) + // rewardToken1
                (1.5*50)   // rewardToken2
            )
             * 365  // 365 days
             * 0.95 // 5% performance fee
        );
        const expectedTotalSharesInUsd = (
            10_000 * // shares
            15 * 1.1 // oToken price * reservesPerShare
        );
        const expectedApr = Math.floor(
            expectedTotalRewardsInUsdPerYear / expectedTotalSharesInUsd * 10_000
        );

        const apr = await ovToken.apr();
        expect(apr).eq(expectedApr).eq(3152); // 31.52%
    });
});
