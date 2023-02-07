import { ethers } from "hardhat";
import { BigNumber, BigNumberish, Signer, utils } from "ethers";
import { expect } from "chai";
import { 
    DummyOracle__factory,
    DummyRepricingToken,
    DummyRepricingToken__factory,
    GMX_GlpManager__factory,
    IUniswapV3Pool__factory,
    MintableToken,
    MintableToken__factory,
    TokenPrices, TokenPrices__factory,
} from "../../typechain";
import { forkMainnet, shouldRevertNotOwner, ZERO_ADDRESS } from "../helpers";
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

    before( async () => {
        [owner, alan] = await getSigners();
        tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
    });

    type TokenPricesArg = string | boolean | BigNumberish;

    const toPrecision = (v: string, dp: number = pricePrecision) => ethers.utils.parseUnits(v, dp);

    const encodeFunction = (fn: string, ...args: TokenPricesArg[]): string => {
        return tokenPricesInterface.encodeFunctionData(fn, args);
    }

    const encodedOraclePrice = (oracle: string): string => encodeFunction("oraclePrice", oracle);
    const encodedGmxVaultPrice = (vault: string, token: string): string => encodeFunction("gmxVaultPrice", vault, token);
    const encodedGlpPrice = (glpManager: string): string => encodeFunction("glpPrice", glpManager);
    const encodedUniV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("univ3Price", pool, inQuotedOrder);
    const encodedTraderJoePrice = (joePair: string, inQuotedOrder: boolean): string => encodeFunction("traderJoePrice", joePair, inQuotedOrder);
    const encodedMulPrice = (v1Bytes: string, v2Bytes: string): string => encodeFunction("mul", v1Bytes, v2Bytes);
    const encodedDivPrice = (numerator: string, denominator: string): string => encodeFunction("div", numerator, denominator);
    const encodedScalar = (amount: BigNumberish): string => encodeFunction("scalar", amount);
    const encodedAliasFor = (sourceToken: string): string => encodeFunction("aliasFor", sourceToken);
    const encodedRepricingTokenPrice = (repricingToken: string): string => encodeFunction("repricingTokenPrice", repricingToken);
    
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
            const encodedEthUsd = encodedOraclePrice(addresses.ethUsdOracle);
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
            const encodedEthUsdOracle = encodedOraclePrice(addresses.ethUsdOracle);
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
            const encodedEthUsdOracle = encodedOraclePrice(addresses.ethUsdOracle);
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
            avaxGmxTraderJoePool: '0x0c91a070f862666bBcce281346BE45766d874D98',
            glpManager: '0xe1ae4d4b06A5Fe1fc288f6B4CD72f9F8323B107F',
            gmx: '0x62edc0692BD897D2295872a9FFCac5425011c661',
        };

        async function setup() {
            forkMainnet(22474880, AVAX_RPC);
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

        it("Trader Joe Price", async () => {           
            const encodedAvaxGmx = encodedTraderJoePrice(addresses.avaxGmxTraderJoePool, true);
            await tokenPrices.setTokenPriceFunction(addresses.avaxGmxTraderJoePool, encodedAvaxGmx);

            const price = await tokenPrices.tokenPrice(addresses.avaxGmxTraderJoePool);
            expect(price).to.eq(toPrecision("0.329496599958896575"));

            // Not in quoted order
            const encodedAvaxGmxInverse = encodedTraderJoePrice(addresses.avaxGmxTraderJoePool, false);
            await tokenPrices.setTokenPriceFunction(addresses.avaxGmxTraderJoePool, encodedAvaxGmxInverse);

            const priceInverse = await tokenPrices.tokenPrice(addresses.avaxGmxTraderJoePool);
            expect(priceInverse).to.eq(toPrecision("3.034932682536773149"));

            // And get the derived $GMX price from [AVAX_USD / AVAX_GMX]
            const encodedAvaxUsd = encodedGmxVaultPrice(gmxVaultAddr, addresses.wavax);
            const encodedGmxUsd = encodedDivPrice(encodedAvaxUsd, encodedAvaxGmx);
            await tokenPrices.setTokenPriceFunction(addresses.gmx, encodedGmxUsd);

            const gmxPrice = await tokenPrices.tokenPrice(addresses.gmx);
            expect(gmxPrice).to.eq(toPrecision("39.960412343078835446899346402600"));
        });
    });

    describe("Local", async () => {
        let repricingToken: DummyRepricingToken;
        let reserveToken: MintableToken;

        async function setup() {
            tokenPrices = await new TokenPrices__factory(owner).deploy(30);
            reserveToken = await new MintableToken__factory(owner).deploy("oToken", "oToken");
            repricingToken = await new DummyRepricingToken__factory(owner).deploy("ovToken", "ovToken", reserveToken.address);
            await repricingToken.addOperator(owner.getAddress());

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
            const reserveTokenOracle = await new DummyOracle__factory(owner).deploy(ethers.utils.parseUnits(reserveTokenPrice.toString(), 8), 8);
            const encodedReserveTokenOracle = encodedOraclePrice(reserveTokenOracle.address);
            await tokenPrices.setTokenPriceFunction(reserveToken.address, encodedReserveTokenOracle);

            const encodedUsd = encodedRepricingTokenPrice(repricingToken.address);
            await tokenPrices.setTokenPriceFunction(repricingToken.address, encodedUsd);

            // If the repricing token has no reserves, then the price is zero
            const price = await tokenPrices.tokenPrice(repricingToken.address);
            expect(price).to.eq(0);

            // Exactly 1:1 reservesPerShare

            await repricingToken.addReserves(100);
            await repricingToken.mint(owner.getAddress(), 100);
            const price2 = await tokenPrices.tokenPrice(repricingToken.address);
            expect(price2).to.eq(ethers.utils.parseUnits(reserveTokenPrice.toString(), 30));

            // > 1:1 reservesPerShare
            await repricingToken.addReserves(125);
            await repricingToken.mint(owner.getAddress(), 100);
            const price3 = await tokenPrices.tokenPrice(repricingToken.address);
            const updatedPrice = reserveTokenPrice * (225 / 200);
            expect(price3).to.eq(ethers.utils.parseUnits(updatedPrice.toString(), 30));
        });

        it("negative oracle price", async () => {
            const price = ethers.utils.parseUnits("15.1", 8).mul(-1);
            const reserveTokenOracle = await new DummyOracle__factory(owner).deploy(
                price, 8);
            const encodedReserveTokenOracle = encodedOraclePrice(reserveTokenOracle.address);
            await tokenPrices.setTokenPriceFunction(reserveToken.address, encodedReserveTokenOracle);
            await expect(tokenPrices.tokenPrice(reserveToken.address))
                .to.revertedWithCustomError(tokenPrices, "FailedPriceLookup");

            await expect(tokenPrices.oraclePrice(reserveTokenOracle.address))
                .to.revertedWithCustomError(tokenPrices, "InvalidPrice")
                .withArgs(price);
        });
    });

});
