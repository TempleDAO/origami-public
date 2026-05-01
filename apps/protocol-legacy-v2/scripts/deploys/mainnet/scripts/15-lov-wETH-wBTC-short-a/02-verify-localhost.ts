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

const WBTC_WHALE = "0x6daB3bCbFb336b29d06B9C793AEF7eaA57888922";
const WBTC_DECIMAL = 8;
const DECIMAL_DIFF = 10 ** (18 - WBTC_DECIMAL);

async function investLov_wBTC(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvest lov-wETH/wBTC-short-a(%s, %f)", await account.getAddress(), amountBN);

  // mint wBTC
  await mine(
    INSTANCES.EXTERNAL.WBTC_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\twBTC balance:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WBTC_TOKEN.balanceOf(account.getAddress()),
    WBTC_DECIMAL
  ));
  await mine(
    INSTANCES.EXTERNAL.WBTC_TOKEN.connect(account).approve(
      ADDRS.LOV_WETH_WBTC_SHORT_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.WBTC_TOKEN,
    10,
    0
  );

  console.log("\tlov-wETH/wBTC-short-a.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAccount balance of lov-wETH/wBTC-short-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_wBTC(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexit lov-wETH/wBTC-short-a(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-wETH/wBTC-short-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wBTC:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WBTC_TOKEN.balanceOf(account.getAddress()),
    WBTC_DECIMAL
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.WBTC_TOKEN,
    slippageBps,
    0
  );

  console.log("\tlov-wETH/wBTC-short-a.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, WBTC_DECIMAL));
  await mine(
    INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-wETH/wBTC-short-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wBTC:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WBTC_TOKEN.balanceOf(account.getAddress()),
    WBTC_DECIMAL
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.maxExit(ADDRS.EXTERNAL.WBTC_TOKEN)
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
  const [assets, liabilities,] = await INSTANCES.LOV_WETH_WBTC_SHORT_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
  console.log("assets:", ethers.utils.formatUnits(assets, WBTC_DECIMAL));
  console.log("liabilities:", ethers.utils.formatUnits(liabilities, WBTC_DECIMAL));

  const _netAssets = assets.sub(
    targetAL.mul(liabilities).div(ONE_ETHER)
  );
  const _priceScaledTargetAL = inverseSubtractBps(
    targetAL.mul(dexPrice).div(oraclePrice),
    slippageBps
  );
  console.log("price scaled target A/L", ethers.utils.formatEther(_priceScaledTargetAL));
  return _netAssets.mul(ONE_ETHER).div(_priceScaledTargetAL.sub(ONE_ETHER));
}

function supplyTokenToDebtTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=100000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&allowPartialFill=false&parts=1" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("1", WBTC_DECIMAL))) {
    const toAmount = ethers.utils.parseEther("18.451614833130363630");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount).div(DECIMAL_DIFF),
      data: "0x"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599&amount=30642360313089019590&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&&allowPartialFill=false&parts=1" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("30.642360313089019590"))) {
    const toAmount = ethers.utils.parseUnits("1.66160347", WBTC_DECIMAL);
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount).div(DECIMAL_DIFF),
      data: "0x83800a8e000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000001a93f885ac532cec60000000000000000000000000000000000000000000000000000000004f3b3ed2800000000000000000000004585fe77225b41b697c938b018e2ac67ac5a20c0053a717a"
    };
  } else {
    throw Error(`Unknown debtTokenToSupplyTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  const oraclePrice = await INSTANCES.ORACLES.WETH_WBTC.convertAmount(
    ADDRS.EXTERNAL.WBTC_TOKEN,
    ONE_ETHER.div(DECIMAL_DIFF),
    PriceType.SPOT_PRICE, 
    RoundingMode.ROUND_DOWN
  );
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch wBTC->wETH price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatUnits(supplyAmount, WBTC_DECIMAL));

  // How much wETH do we need to borrow in order to swap to that supplyAmount of wBTC
  // Use the dex price
  let borrowAmount = supplyAmount.mul(dexPrice.price).mul(DECIMAL_DIFF).div(ONE_ETHER);

  // Add slippage to the amount we actually borrow so after the swap
  // we ensure we have more collateral than supplyAmount
  borrowAmount = inverseSubtractBps(borrowAmount, slippageBps);
  console.log("borrowAmount:", ethers.utils.formatUnits(borrowAmount));

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

  const alRatioBefore = await INSTANCES.LOV_WETH_WBTC_SHORT_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WETH_WBTC_SHORT_A.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_WETH_WBTC_SHORT_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));
}

export const applySlippage = (
  expectedAmount: BigNumber,
  slippageBps: number
) => {
  return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getWBTC(owner: SignerWithAddress) {
  const signer = await impersonateAndFund(owner, WBTC_WHALE);
  await mine(INSTANCES.EXTERNAL.WBTC_TOKEN.connect(signer).transfer(owner.getAddress(), ethers.utils.parseUnits("10", WBTC_DECIMAL)));
}

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.WBTC_TOKEN,
    ADDRS.LOV_WETH_WBTC_SHORT_A.TOKEN,
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

  await getWBTC(owner);

  await investLov_wBTC(bob, ethers.utils.parseUnits("1", WBTC_DECIMAL));

  await rebalanceDown(ethers.utils.parseEther("1.6667"), 50, ethers.utils.parseUnits("1", WBTC_DECIMAL));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN.maxExit(ADDRS.EXTERNAL.WBTC_TOKEN);
  await exitLov_wBTC(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });