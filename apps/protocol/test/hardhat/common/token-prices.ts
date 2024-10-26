import { ethers } from "hardhat";
import { BigNumber, BigNumberish, Signer, utils } from "ethers";
import { expect } from "chai";
import { 
    DummyOracle__factory,
    DummyRepricingToken,
    DummyRepricingToken__factory,
    GMX_GlpManager__factory,
    MintableToken,
    DummyMintableToken__factory,
    TokenPrices, TokenPrices__factory, DummyOracle,
    MockSDaiToken__factory,
    MockStEthToken__factory,
    OrigamiVolatileChainlinkOracle__factory,
} from "../../../typechain";
import { 
    blockTimestamp, 
    forkMainnet, 
    mineForwardSeconds, 
    setExplicitAccess, 
    shouldRevertNotOwner,
    ZERO_ADDRESS
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployGmx } from "../investments/gmx/gmx-helpers";
import { getSigners } from "../signers";

const AVAX_RPC = "https://api.avax.network/ext/bc/C/rpc";
const ARBITRUM_RPC = "https://rpc.ankr.com/arbitrum";

describe("Token Prices", async () => {
    let owner: Signer;
    let alan: Signer;
    let tokenPrices: TokenPrices;
    let tokenPricesInterface: utils.Interface;
    let gmxVaultAddr: string;

    const pricePrecision = 30;
    const repricingTokenVestingDuration = 86400;

    before( async () => {
        [owner, alan] = await getSigners();
        tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
    });

    type TokenPricesArg = string | boolean | BigNumberish;

    const toPrecision = (v: string, dp: number = pricePrecision) => ethers.utils.parseUnits(v, dp);

    const encodeFunction = (fn: string, ...args: TokenPricesArg[]): string => {
        return tokenPricesInterface.encodeFunctionData(fn, args);
    }

    enum PriceType {
        SPOT_PRICE,
        HISTORIC_PRICE
    }
      
    enum RoundingMode {
        ROUND_DOWN,
        ROUND_UP
    }
      
    const encodedOraclePrice = (oracle: string, stalenessThreshold: number): string => encodeFunction("oraclePrice", oracle, stalenessThreshold);
    const encodedGmxVaultPrice = (vault: string, token: string): string => encodeFunction("gmxVaultPrice", vault, token);
    const encodedGlpPrice = (glpManager: string): string => encodeFunction("glpPrice", glpManager);
    const encodedUniV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("univ3Price", pool, inQuotedOrder);
    const encodedTraderJoeBestPrice = (joeQuoter: string, sellToken: string, buyToken: string): string => encodeFunction("traderJoeBestPrice", joeQuoter, sellToken, buyToken);
    const encodedMulPrice = (v1Bytes: string, v2Bytes: string): string => encodeFunction("mul", v1Bytes, v2Bytes);
    const encodedDivPrice = (numerator: string, denominator: string): string => encodeFunction("div", numerator, denominator);
    const encodedScalar = (amount: BigNumberish): string => encodeFunction("scalar", amount);
    const encodedAliasFor = (sourceToken: string): string => encodeFunction("aliasFor", sourceToken);
    const encodedRepricingTokenPrice = (repricingToken: string): string => encodeFunction("repricingTokenPrice", repricingToken);
    const encodedErc4626TokenPrice = (vault: string): string => encodeFunction("erc4626TokenPrice", vault);
    const encodedWstEthRatio = (stEthToken: string): string => encodeFunction("wstEthRatio", stEthToken);
    const encodedOrigamiOraclePrice = (oracleAddress: string, priceType: PriceType, roundingMode: RoundingMode): string => 
        encodeFunction("origamiOraclePrice", oracleAddress, priceType, roundingMode);

    describe("Arbitrum", async () => {
        const addresses = {
            weth: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
            ethUsdOracle: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
            gmx: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
            glp: "0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258",
            ethGmxUniV3Pool: '0x80A9ae39310abf666A87C743d6ebBD0E8C42158E',
            glpManager: "0x321F653eED006AD1C29D174e17d96351BDe22649",
        };

        async function setup() {
            forkMainnet(38187290, ARBITRUM_RPC);
            tokenPrices = await new TokenPrices__factory(owner).deploy(pricePrecision);
            gmxVaultAddr = await GMX_GlpManager__factory.connect(addresses.glpManager, owner).vault();
            
            return {
                tokenPrices,
                gmxVaultAddr,
            };
        }

        beforeEach(async () => {
            ({
                tokenPrices,
                gmxVaultAddr,
            } = await loadFixture(setup));
        });

        it("admin", async () => {
            await shouldRevertNotOwner(tokenPrices.connect(alan).setTokenPriceFunction(ZERO_ADDRESS, ZERO_ADDRESS));
        });

        it("eth price", async () => {
            const encodedEthUsd = encodedOraclePrice(addresses.ethUsdOracle, 600);
            await expect(tokenPrices.setTokenPriceFunction(addresses.weth, encodedEthUsd))
                .to.emit(tokenPrices, "TokenPriceFunctionSet")
                .withArgs(addresses.weth, encodedEthUsd);

            const price = await tokenPrices.tokenPrice(addresses.weth);
            expect(price).to.eq(toPrecision("1259.44226268"));
        });

        it("GMX Vault Price", async () => {
            const encodedEthUsd = encodedGmxVaultPrice(gmxVaultAddr, addresses.weth);
            await tokenPrices.setTokenPriceFunction(addresses.weth, encodedEthUsd);

            const price = await tokenPrices.tokenPrice(addresses.weth);
            expect(price).to.eq(toPrecision("1259.64"));
        });

        it("GLP Price", async () => {
            const encodedGlpUsd = encodedGlpPrice(addresses.glpManager);
            await tokenPrices.setTokenPriceFunction(addresses.glp, encodedGlpUsd);

            const price = await tokenPrices.tokenPrice(addresses.glp);
            expect(price).to.eq(toPrecision("0.857773867014654178652699835936"));
        });

        it("GLP price with empty setup", async () => {
            // The non-forked gmx contracts has no assets in the pool - so AUM = 0
            const rewardsPerSec = BigNumber.from("0");
            const gmxContracts = await deployGmx(owner, rewardsPerSec, rewardsPerSec, rewardsPerSec, rewardsPerSec);

            const price = await tokenPrices.glpPrice(await gmxContracts.glpRewardRouter.glpManager());
            expect(price).to.eq(toPrecision("1.0"));
        });

        it("Uniswap V3 Price", async () => {
            // In quoted order
            const encodedEthGmx = encodedUniV3Price(addresses.ethGmxUniV3Pool, true);
            await tokenPrices.setTokenPriceFunction(addresses.ethGmxUniV3Pool, encodedEthGmx);

            const price = await tokenPrices.tokenPrice(addresses.ethGmxUniV3Pool);
            expect(price).to.eq(toPrecision("29.226347253209534068851077259622"));

            // Not in quoted order
            const encodedEthGmxInverse = encodedUniV3Price(addresses.ethGmxUniV3Pool, false);
            await tokenPrices.setTokenPriceFunction(addresses.ethGmxUniV3Pool, encodedEthGmxInverse);

            const priceInverse = await tokenPrices.tokenPrice(addresses.ethGmxUniV3Pool);
            expect(priceInverse).to.eq(toPrecision("0.034215702404965558514726581213"));
        });

        it("mul() - ", async () => {
            // Not in quoted order
            const encodedEthGmx = encodedUniV3Price(addresses.ethGmxUniV3Pool, false);
            const encodedEthUsd = encodedGmxVaultPrice(gmxVaultAddr, addresses.weth);
            const encodedGmxUsd = encodedMulPrice(encodedEthGmx, encodedEthUsd);

            await tokenPrices.setTokenPriceFunction(addresses.gmx, encodedGmxUsd);

            const price = await tokenPrices.tokenPrice(addresses.gmx);
            expect(price).to.eq(toPrecision("43.099467377390816127490190759143"));
        });

        it("div() - ", async () => {
            // In quoted order
            const encodedEthGmx = encodedUniV3Price(addresses.ethGmxUniV3Pool, true);
            const encodedEthUsd = encodedGmxVaultPrice(gmxVaultAddr, addresses.weth);
            const encodedGmxUsd = encodedDivPrice(encodedEthUsd, encodedEthGmx);

            await tokenPrices.setTokenPriceFunction(addresses.gmx, encodedGmxUsd);

            const price = await tokenPrices.tokenPrice(addresses.gmx);
            expect(price).to.eq(toPrecision("43.099467377390816127490190759359"));
        });

        it("scalar()", async () => {
            // In quoted order
            const amount = ethers.utils.parseEther("1.234567123123567");
            const encoded = encodedScalar(amount);
            await tokenPrices.setTokenPriceFunction(addresses.gmx, encoded);

            const price = await tokenPrices.tokenPrice(addresses.gmx);
            expect(price).to.eq(amount);
        });
    
        it("aliasFor()", async () => {
            // Add $GMX price        
            const encodedEthGmx = encodedUniV3Price(addresses.ethGmxUniV3Pool, true);
            const encodedEthUsd = encodedGmxVaultPrice(gmxVaultAddr, addresses.weth);
            const encodedGmxUsd = encodedDivPrice(encodedEthUsd, encodedEthGmx);
            await tokenPrices.setTokenPriceFunction(addresses.gmx, encodedGmxUsd);

            // Add alias
            const encodedAliasTokenUsd = encodedAliasFor(addresses.gmx);
            const aliasToken = ethers.Wallet.createRandom();
            await tokenPrices.setTokenPriceFunction(aliasToken.address, encodedAliasTokenUsd);

            const gmxPrice = await tokenPrices.tokenPrice(addresses.gmx);
            const aliasPrice = await tokenPrices.tokenPrice(aliasToken.address);
            expect(gmxPrice).to.eq(aliasPrice).eq(toPrecision("43.099467377390816127490190759359"));
        });

        it("Unknown token", async () => {
            await expect(tokenPrices.tokenPrice(addresses.ethUsdOracle)).to.be.revertedWithCustomError(tokenPrices, "FailedPriceLookup");
        });

        it("multi price", async () => {
            // ETH
            const encodedEthUsdOracle = encodedOraclePrice(addresses.ethUsdOracle, 600);
            await tokenPrices.setTokenPriceFunction(addresses.weth, encodedEthUsdOracle);

            // GLP
            const encodedGlpUsd = encodedGlpPrice(addresses.glpManager);
            await tokenPrices.setTokenPriceFunction(addresses.glp, encodedGlpUsd);

            // GMX
            const encodedEthGmx = encodedUniV3Price(addresses.ethGmxUniV3Pool, true);
            const encodedEthUsdGmx = encodedGmxVaultPrice(gmxVaultAddr, addresses.weth);
            const encodedGmxUsd = encodedDivPrice(encodedEthUsdGmx, encodedEthGmx);
            await tokenPrices.setTokenPriceFunction(addresses.gmx, encodedGmxUsd);

            const price = await tokenPrices.tokenPrices([addresses.glp, addresses.weth, addresses.gmx]);
            expect(price).to.deep.eq(
                [
                    toPrecision("0.857773867014654178652699835936"),
                    toPrecision("1259.44226268"),
                    toPrecision("43.099467377390816127490190759359"),
                ]
            );
        });

        it("lower precision", async () => {
            const tokenPricesLower = await new TokenPrices__factory(owner).deploy(6);

            // ETH
            const encodedEthUsdOracle = encodedOraclePrice(addresses.ethUsdOracle, 600);
            await tokenPricesLower.setTokenPriceFunction(addresses.weth, encodedEthUsdOracle);

            // GLP
            const encodedGlpUsd = encodedGlpPrice(addresses.glpManager);
            await tokenPricesLower.setTokenPriceFunction(addresses.glp, encodedGlpUsd);

            // GMX
            const encodedEthGmx = encodedUniV3Price(addresses.ethGmxUniV3Pool, true);
            const encodedEthUsdGmx = encodedGmxVaultPrice(gmxVaultAddr, addresses.weth);
            const encodedGmxUsd = encodedDivPrice(encodedEthUsdGmx, encodedEthGmx);
            await tokenPricesLower.setTokenPriceFunction(addresses.gmx, encodedGmxUsd);
            
            const price = await tokenPricesLower.tokenPrices([addresses.glp, addresses.weth, addresses.gmx]);
            expect(price).to.deep.eq(
                [
                    toPrecision("0.857773", 6),
                    toPrecision("1259.442262", 6),
                    toPrecision("43.099467", 6),
                ]
            );
        });
    });
    
    describe("Avalanche", async () => {
        const addresses = {
            wavax: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
            traderJoeQuoter: '0x9dbf1706577636941ab5f443d2aebe251ccd1648',
            glpManager: '0xe1ae4d4b06A5Fe1fc288f6B4CD72f9F8323B107F',
            gmx: '0x62edc0692BD897D2295872a9FFCac5425011c661',
            usdc: '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
        };

        async function setup() {
            forkMainnet(26276626, AVAX_RPC);
            tokenPrices = await new TokenPrices__factory(owner).deploy(pricePrecision);
            gmxVaultAddr = await GMX_GlpManager__factory.connect(addresses.glpManager, owner).vault();
            
            return {
                tokenPrices,
                gmxVaultAddr,
            };
        }

        beforeEach(async () => {
            ({
                tokenPrices,
                gmxVaultAddr,
            } = await loadFixture(setup));
        });

        it("Trader Joe V2 Price", async () => {           
            const gmxWavaxPrice = await tokenPrices.traderJoeBestPrice(addresses.traderJoeQuoter, addresses.gmx, addresses.wavax);
            expect(gmxWavaxPrice).to.eq(toPrecision("4.206218032836104331131753600091"));

            const wavaxGmxPrice = await tokenPrices.traderJoeBestPrice(addresses.traderJoeQuoter, addresses.wavax, addresses.gmx);
            expect(wavaxGmxPrice).to.eq(toPrecision("0.237985638774157491474423269809"));

            const wavaxUsdcPrice = await tokenPrices.traderJoeBestPrice(addresses.traderJoeQuoter, addresses.wavax, addresses.usdc);
            expect(wavaxUsdcPrice).to.eq(toPrecision("18.060913827678474919538505458814"));
            
            const usdcWavaxPrice = await tokenPrices.traderJoeBestPrice(addresses.traderJoeQuoter, addresses.usdc, addresses.wavax);
            expect(usdcWavaxPrice).to.eq(toPrecision("0.055368183825892921736394525445"));

            const aliasAddr = alan.getAddress();
            const encodedWavaxGmx = encodedTraderJoeBestPrice(addresses.traderJoeQuoter, addresses.wavax, addresses.gmx);
            await tokenPrices.setTokenPriceFunction(aliasAddr, encodedWavaxGmx);

            const lookupPrice = await tokenPrices.tokenPrice(aliasAddr);
            expect(lookupPrice).eq(wavaxGmxPrice);

            // And get the derived $GMX price from [AVAX_USD / AVAX_GMX]
            const encodedAvaxUsd = encodedGmxVaultPrice(gmxVaultAddr, addresses.wavax);
            const encodedGmxUsd = encodedDivPrice(encodedAvaxUsd, encodedWavaxGmx);
            await tokenPrices.setTokenPriceFunction(aliasAddr, encodedGmxUsd);
            const gmxPrice = await tokenPrices.tokenPrice(aliasAddr);
            expect(gmxPrice).to.eq(toPrecision("75.886932056175436282845046092983"));
        });
    });

    describe("Local", async () => {
        let repricingToken: DummyRepricingToken;
        let reserveToken: MintableToken;

        async function setup() {
            tokenPrices = await new TokenPrices__factory(owner).deploy(30);
            reserveToken = await new DummyMintableToken__factory(owner).deploy(owner.getAddress(), "oToken", "oToken", 18);
            repricingToken = await new DummyRepricingToken__factory(owner).deploy(owner.getAddress(), "ovToken", "ovToken", reserveToken.address, repricingTokenVestingDuration);
            await setExplicitAccess(
                repricingToken,
                await owner.getAddress(),
                ["addPendingReserves"],
                true
            );

            await reserveToken.addMinter(owner.getAddress());
            await reserveToken.mint(owner.getAddress(), 225);
            await reserveToken.approve(repricingToken.address, 225);

            return {
                tokenPrices,
                reserveToken,
                repricingToken,
            };
        }

        beforeEach(async () => {
            ({
                tokenPrices,
                reserveToken,
                repricingToken,
            } = await loadFixture(setup));
        });

        it("repricing token price", async () => {
            // Set $reserveToken == 30
            const reserveTokenPrice = 30;
            const nonStaleAnswer: DummyOracle.AnswerStruct = {
                roundId: 10,
                answer: ethers.utils.parseUnits(reserveTokenPrice.toString(), 8),
                startedAt: await blockTimestamp(),
                updatedAtLag: 10,
                answeredInRound: 5
            };
            const reserveTokenOracle = await new DummyOracle__factory(owner).deploy(nonStaleAnswer, 8);
            const encodedReserveTokenOracle = encodedOraclePrice(reserveTokenOracle.address, 60);
            await tokenPrices.setTokenPriceFunction(reserveToken.address, encodedReserveTokenOracle);

            const encodedUsd = encodedRepricingTokenPrice(repricingToken.address);
            await tokenPrices.setTokenPriceFunction(repricingToken.address, encodedUsd);

            // If the repricing token has no reserves, then the price is zero
            const price = await tokenPrices.tokenPrice(repricingToken.address);
            expect(price).to.eq(ethers.utils.parseUnits(reserveTokenPrice.toString(), 30));

            // 1/2 way through the vesting period, it's 1:2 reservesPerShare
            await repricingToken.mint(owner.getAddress(), 100);
            await repricingToken.addPendingReserves(100);
            await mineForwardSeconds(repricingTokenVestingDuration/2);
            const price2 = await tokenPrices.tokenPrice(repricingToken.address);
            expect(price2).to.eq(ethers.utils.parseUnits(reserveTokenPrice.toString(), 30).div(2));

            // Fully vested it's 1:1 reservesPerShare
            await mineForwardSeconds(repricingTokenVestingDuration/2);
            const price2b = await tokenPrices.tokenPrice(repricingToken.address);
            expect(price2b).to.eq(ethers.utils.parseUnits(reserveTokenPrice.toString(), 30));

            // > 1:1 reservesPerShare
            await repricingToken.mint(owner.getAddress(), 100);
            await repricingToken.addPendingReserves(125);
            await mineForwardSeconds(repricingTokenVestingDuration);
            const price3 = await tokenPrices.tokenPrice(repricingToken.address);
            const updatedPrice = reserveTokenPrice * (225 / 200);
            expect(price3).to.eq(ethers.utils.parseUnits(updatedPrice.toString(), 30));
        });

        it("ERC-4626 token price", async () => {
            const daiToken = await new DummyMintableToken__factory(owner).deploy(owner.getAddress(), "DAI", "DAI", 18);
            const sDaiToken = await new MockSDaiToken__factory(owner).deploy(daiToken.address);

            const daiPrice = 1.00123;
            const nonStaleAnswer: DummyOracle.AnswerStruct = {
                roundId: 10,
                answer: ethers.utils.parseUnits(daiPrice.toString(), 8),
                startedAt: await blockTimestamp(),
                updatedAtLag: 10,
                answeredInRound: 5
            };
            const daiOracle = await new DummyOracle__factory(owner).deploy(nonStaleAnswer, 8);
            const encodedDaiOracle = encodedOraclePrice(daiOracle.address, 60);
            await tokenPrices.setTokenPriceFunction(daiToken.address, encodedDaiOracle);

            const encodedUsd = encodedErc4626TokenPrice(sDaiToken.address);
            await tokenPrices.setTokenPriceFunction(sDaiToken.address, encodedUsd);

            // If sDAI has no supply and zero rate, then the price is the same
            const price = await tokenPrices.tokenPrice(sDaiToken.address);
            expect(price).to.eq(ethers.utils.parseUnits(daiPrice.toString(), 30));

            // Deposit and set the IR
            {
                await daiToken.addMinter(owner.getAddress());
                const depositAmount = ethers.utils.parseEther("10000");
                await daiToken.mint(alan.getAddress(), depositAmount);
                await daiToken.connect(alan).approve(sDaiToken.address, depositAmount);
                await sDaiToken.connect(alan).deposit(depositAmount, alan.getAddress());
                const interestRate = ethers.utils.parseEther("0.05");
                await sDaiToken.setInterestRate(interestRate);               
            }

            // After one year, then the sDAI price has increased
            await mineForwardSeconds(365 * 86400);
            const price2 = await tokenPrices.tokenPrice(sDaiToken.address);
            const expected = 1.05 * daiPrice;
            expect(price2).to.eq(ethers.utils.parseUnits(expected.toString(), 30));
        });

        it("negative oracle price", async () => {
            const price = ethers.utils.parseUnits("15.1", 8).mul(-1);
            const nonStaleAnswer: DummyOracle.AnswerStruct = {
                roundId: 10,
                answer: price,
                startedAt: await blockTimestamp(),
                updatedAtLag: 10,
                answeredInRound: 5
            };
            const reserveTokenOracle = await new DummyOracle__factory(owner).deploy(
                nonStaleAnswer, 8);
            const encodedReserveTokenOracle = encodedOraclePrice(reserveTokenOracle.address, 60);
            await tokenPrices.setTokenPriceFunction(reserveToken.address, encodedReserveTokenOracle);
            await expect(tokenPrices.tokenPrice(reserveToken.address))
                .to.revertedWithCustomError(tokenPrices, "FailedPriceLookup");

            await expect(tokenPrices.oraclePrice(reserveTokenOracle.address, 60))
                .to.revertedWithCustomError(tokenPrices, "InvalidPrice")
                .withArgs(price);
        });

        it("stale oracle price", async () => {
            const price = ethers.utils.parseUnits("15.1", 8);
            const staleAnswer: DummyOracle.AnswerStruct = {
                roundId: 10,
                answer: price,
                startedAt: await blockTimestamp(),
                updatedAtLag: 100,
                answeredInRound: 5
            };
            const reserveTokenOracle = await new DummyOracle__factory(owner).deploy(
                staleAnswer, 8);

            // The staleness threshold is 10 seconds, whereas the answer was updated 100 seconds ago.
            const encodedReserveTokenOracle = encodedOraclePrice(reserveTokenOracle.address, 10);
            await tokenPrices.setTokenPriceFunction(reserveToken.address, encodedReserveTokenOracle);
            await expect(tokenPrices.tokenPrice(reserveToken.address))
                .to.revertedWithCustomError(tokenPrices, "FailedPriceLookup");

            await expect(tokenPrices.oraclePrice(reserveTokenOracle.address, 10))
                .to.revertedWithCustomError(tokenPrices, "InvalidPrice")
                .withArgs(price);

            // Works if at the threshold
            expect(await tokenPrices.oraclePrice(reserveTokenOracle.address, 100))
                .to.eq(ethers.utils.parseUnits(ethers.utils.formatUnits(price.toString(), 8), 30));
        });

        it("wstEth/ETH ratio", async () => {
            const stEth = await new MockStEthToken__factory(owner).deploy(
                await owner.getAddress(),
                ethers.utils.parseEther("0.04") // 4%
            );

            await stEth.connect(alan).submit(ZERO_ADDRESS, {value: ethers.utils.parseEther("10")});
            await mineForwardSeconds(365 * 86400);
            const wstEthRatioToken = "0x1000000000000000000000000000000000000001";

            await tokenPrices.setTokenPriceFunction(
                wstEthRatioToken,
                encodedWstEthRatio(stEth.address)
            );
            expect(await tokenPrices.tokenPrice(wstEthRatioToken))
                .to.eq(ethers.utils.parseUnits("1.040810775512543952", 30));
        });

        it("wstEth/USD price", async () => {
            const stEth = await new MockStEthToken__factory(owner).deploy(
                await owner.getAddress(),
                ethers.utils.parseEther("0.04") // 4%
            );

            const stEthToEthOracle = await new DummyOracle__factory(owner).deploy(
                {
                    roundId: 10,
                    answer: ethers.utils.parseUnits("0.9998", 18),
                    startedAt: await blockTimestamp(),
                    updatedAtLag: 1,
                    answeredInRound: 10
                }, 
                18
            );
            const ethToUsdOracle = await new DummyOracle__factory(owner).deploy(
                {
                    roundId: 10,
                    answer: ethers.utils.parseUnits("2500", 18),
                    startedAt: await blockTimestamp(),
                    updatedAtLag: 1,
                    answeredInRound: 10
                }, 
                18
            );

            await stEth.connect(alan).submit(ZERO_ADDRESS, {value: ethers.utils.parseEther("10")});
            await mineForwardSeconds(365 * 86400);
            const wstEthToken = "0x1000000000000000000000000000000000000001";
            
            await tokenPrices.setTokenPriceFunction(
                wstEthToken,
                encodedMulPrice(
                    encodedWstEthRatio(stEth.address),
                    encodedMulPrice(
                        encodedOraclePrice(stEthToEthOracle.address, 86400 * 365 * 10),
                        encodedOraclePrice(ethToUsdOracle.address, 86400 * 365 * 10),
                    ),
                )
            );
            expect(await tokenPrices.tokenPrice(wstEthToken))
                .to.eq(
                    ethers.utils.parseUnits("1.040810775512543952", 18).mul(
                        ethers.utils.parseUnits("0.9998", 6).mul(
                            ethers.utils.parseUnits("2500", 6)
                        )
                    )
                );
        });

        it("Origami oracle price", async () => {
            const ETH_ADDRESS = ZERO_ADDRESS;
            const clEthToUsdOracle = await new DummyOracle__factory(owner).deploy(
                {
                    roundId: 10,
                    answer: ethers.utils.parseUnits("2500", 18),
                    startedAt: await blockTimestamp(),
                    updatedAtLag: 1,
                    answeredInRound: 10
                }, 
                18
            );

            const origamiOracle = await new OrigamiVolatileChainlinkOracle__factory(owner).deploy(
                {
                    description: "ETH/USD",
                    baseAssetAddress: ETH_ADDRESS,
                    baseAssetDecimals: 18,
                    quoteAssetAddress: "0x000000000000000000000000000000000000115d",
                    quoteAssetDecimals: 18,
                },
                clEthToUsdOracle.address,
                86400 * 365,
                false,
                true
            );

            await tokenPrices.setTokenPriceFunction(
                ETH_ADDRESS,
                encodedOrigamiOraclePrice(origamiOracle.address, PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN)
            );
            expect(await tokenPrices.tokenPrice(ETH_ADDRESS))
                .to.eq(ethers.utils.parseUnits("2500", 30));
        });
    });

});
