import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, impersonateAndFund, mine } from "../../../helpers";
import { ContractInstances, connectToContracts, getDeployedContracts } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const WETH_WHALE = "0x57757E3D981446D585Af0D9Ae4d7DF6D64647806";
const WBTC_DECIMAL = 8;
const DECIMAL_DIFF = 10 ** (18 - WBTC_DECIMAL);

async function investLov_wETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvest lov-wETH/wBTC-long-a(%s, %f)", await account.getAddress(), amountBN);

  // mint wETH
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\twETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.WETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.connect(account).approve(
      ADDRS.LOV_WETH_WBTC_LONG_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    10,
    0
  );

  console.log("\tlov-wETH/wBTC-long-a.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAccount balance of lov-wETH/wBTC-long-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_wETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexit lov-wETH/wBTC-long-a(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-wETH/wBTC-long-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    slippageBps,
    0
  );

  console.log("\tlov-wETH/wBTC-long-a.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount));
  await mine(
    INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-wETH/wBTC-long-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.maxExit(ADDRS.EXTERNAL.WETH_TOKEN)
  ));
}

enum PriceType {
  SPOT_PRICE = 0,
  HISTORIC_PRICE = 1
}

enum RoundingMode {
  ROUND_DOWN = 0,
  ROUND_UP = 1
}

function inverseSubtractBps(remainderAmount: BigNumber, basisPoints: number) {
  return remainderAmount.mul(MAX_BPS).div(MAX_BPS - basisPoints);
}

async function solveRebalanceDownAmount(
  targetAL: BigNumber,
  currentAL: BigNumber,
  dexPrice: BigNumber,
  oraclePrice: BigNumber,
  slippageBps: number,
) {
  if (targetAL.lte(ONE_ETHER)) throw Error("InvalidRebalanceDownParam()");
  if (targetAL.gte(currentAL)) throw Error("InvalidRebalanceDownParam()");

  // Note there may be a difference between the DEX executed price
  // vs the observed oracle price.
  // To account for this, the amount added to the liabilities needs to be scaled
  /*
    targetAL == (assets+X) / (liabilities+X*dexPrice/oraclePrice/(1-slippage));
    targetAL*(liabilities+X*dexPrice/oraclePrice/(1-slippage)) == (assets+X)
    targetAL*liabilities + targetAL*X*dexPrice/oraclePrice/(1-slippage) == assets+X
    targetAL*liabilities + targetAL*X*dexPrice/oraclePrice/(1-slippage) - X == assets
    X*targetAL*dexPrice/oraclePrice/(1-slippage) - X == assets - targetAL*liabilities
    X * (targetAL*dexPrice/oraclePrice/(1-slippage) - 1) == assets - targetAL*liabilities
    X == (assets - targetAL*liabilities) / (targetAL*dexPrice/oraclePrice/(1-slippage) - 1)
  */
  const [assets, liabilities,] = await INSTANCES.LOV_WETH_WBTC_LONG_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
  console.log("assets:", ethers.utils.formatEther(assets));
  console.log("liabilities:", ethers.utils.formatEther(liabilities));

  const _netAssets = assets.sub(
    targetAL.mul(liabilities).div(ONE_ETHER)
  );
  const _priceScaledTargetAL = inverseSubtractBps(
    targetAL.mul(dexPrice).div(oraclePrice),
    slippageBps
  );
  return _netAssets.mul(ONE_ETHER).div(_priceScaledTargetAL.sub(ONE_ETHER));
}

function supplyTokenToDebtTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599&amount=50000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("50"))) {
    const toAmount = ethers.utils.parseEther("2.71182636");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=363723085&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("3.63723085", WBTC_DECIMAL))) {
    const toAmount = ethers.utils.parseEther("67.045758185359585707");
    return {
      toAmount,
      price: fromAmount.mul(DECIMAL_DIFF).mul(ONE_ETHER).div(toAmount),
      data: "0x83800a8e0000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000000000000000000000000000000000015adf94d000000000000000000000000000000000000000000000001d13930ec478c58d52880000000000000000000004585fe77225b41b697c938b018e2ac67ac5a20c0053a717a"
    };
  } else {
    throw Error(`Unknown debtTokenToSupplyTokenQuote amount: ${ethers.utils.formatUnits(fromAmount, WBTC_DECIMAL)}`);
  }
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  const oraclePrice = await INSTANCES.ORACLES.WETH_WBTC.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch wETH->wBTC price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much wBTC do we need to borrow in order to swap to that supplyAmount of wETH
  // Use the dex price
  let borrowAmount = supplyAmount.mul(dexPrice.price).div(ONE_ETHER).div(DECIMAL_DIFF);

  // Add slippage to the amount we actually borrow so after the swap
  // we ensure we have more collateral than supplyAmount
  borrowAmount = inverseSubtractBps(borrowAmount, slippageBps);
  console.log("borrowAmount:", ethers.utils.formatUnits(borrowAmount, WBTC_DECIMAL));

  // Get the swap data
  const oneInchQuote = debtTokenToSupplyTokenQuote(borrowAmount);
  console.log(`1inch swap price: ${ethers.utils.formatEther(oneInchQuote.price)}`);

  const supplyCollateralSurplusThreshold = ethers.utils.parseEther("1000000");

  return {
    supplyAmount,
    borrowAmount,
    swapData: oneInchQuote.data,
    swapToAmount: oneInchQuote.toAmount,
    supplyCollateralSurplusThreshold
  };
}

async function rebalanceDown(
  targetAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await INSTANCES.LOV_WETH_WBTC_LONG_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WETH_WBTC_LONG_A.MANAGER.rebalanceDown(
      {
        flashLoanAmount: params.borrowAmount,
        swapData: params.swapData,
        minExpectedReserveToken: params.swapToAmount.mul(10000 - 1000).div(10000),
        minNewAL: targetAL.mul(10000 - 500).div(10000),
        maxNewAL: targetAL.mul(10000 + 500).div(10000),
      },
      { gasLimit: 5000000 }
    )
  );
  const alRatioAfter = await INSTANCES.LOV_WETH_WBTC_LONG_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));
}

export const applySlippage = (
  expectedAmount: BigNumber,
  slippageBps: number
) => {
  return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getWETH(owner: SignerWithAddress) {
  const signer = await impersonateAndFund(owner, WETH_WHALE);
  await mine(INSTANCES.EXTERNAL.WETH_TOKEN.connect(signer).transfer(owner.getAddress(), ethers.utils.parseEther("1000")));
}

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.WBTC_TOKEN,
    ADDRS.LOV_WETH_WBTC_LONG_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\twETH:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\twBTC:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlovToken:", ethers.utils.formatUnits(prices[2], 30));
}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await dumpPrices();

  await getWETH(owner);

  await investLov_wETH(bob, ethers.utils.parseEther("50"));

  await rebalanceDown(ethers.utils.parseEther("1.6667"), 50, ethers.utils.parseEther("50"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN.maxExit(ADDRS.EXTERNAL.WETH_TOKEN);
  await exitLov_wETH(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
