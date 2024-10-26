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

async function investLov_wETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvest lov-wETH/DAI-long-a(%s, %f)", await account.getAddress(), amountBN);

  // mint wETH
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\twETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.WETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.connect(account).approve(
      ADDRS.LOV_WETH_DAI_LONG_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    10,
    0
  );

  console.log("\tlov-wETH/DAI-long-a.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAccount balance of lov-wETH/DAI-long-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_wETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexit lov-wETH/DAI-long-a(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-wETH/DAI-long-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    slippageBps,
    0
  );

  console.log("\tlov-wETH/DAI-long-a.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount));
  await mine(
    INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-wETH/DAI-long-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.WETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.maxExit(ADDRS.EXTERNAL.WETH_TOKEN)
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
  const [assets, liabilities,] = await INSTANCES.LOV_WETH_DAI_LONG_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
  console.log("assets:", ethers.utils.formatEther(assets));
  console.log("liabilities:", ethers.utils.formatEther(liabilities));

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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&amount=50000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("50"))) {
    const toAmount = ethers.utils.parseEther("171503.145251127829415378");
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=177753333244510854314612&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&parts=1" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("177753.333244510854314612"))) {
    const toAmount = ethers.utils.parseEther("50.434924774260348697");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000025a4070a785c3e95fa740000000000000000000000000000000000000000000000015df66c6ee9ab0b8c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002a800000000000000000000000000000000000000028a00025c00022e0001e400a0c9e75c48000000000000000005050000000000000000000000000000000000000000000000000001b600007900a007e5c0d200000000000000000000000000000000000000000000000000005500000600a03dd5cfd102a0000000000000000000000000000000000000000000000000aefa706a53ae1a60ee63c1e50188e6a0c2ddd26feeb64f039a2c41296fcb3f5640a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800a007e5c0d20000000000000000000000000000000000000000000001190000ca0000b05120bebc44782c7db0a1a60cb6fe97d0b483032ff1c76b175474e89094c44da98b954eedeac495271d0f00443df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a5a3a5b310020d6bdbf78dac17f958d2ee523a2206206994597c13d831ec702a0000000000000000000000000000000000000000000000000aefbfc0495fcf12cee63c1e50011b815efb8f581194ae79006d24e0d814b7697f6dac17f958d2ee523a2206206994597c13d831ec700a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000002bbecd8ddd3561719000000000000000000050a67e957fab580a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000053a717a"
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
  const oraclePrice = await INSTANCES.ORACLES.WETH_DAI.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch wETH->DAI price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much DAI do we need to borrow in order to swap to that supplyAmount of wETH
  // Use the dex price
  let borrowAmount = supplyAmount.mul(dexPrice.price).div(ONE_ETHER);

  // Add slippage to the amount we actually borrow so after the swap
  // we ensure we have more collateral than supplyAmount
  borrowAmount = inverseSubtractBps(borrowAmount, slippageBps);
  console.log("borrowAmount:", ethers.utils.formatEther(borrowAmount));

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

  const alRatioBefore = await INSTANCES.LOV_WETH_DAI_LONG_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WETH_DAI_LONG_A.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_WETH_DAI_LONG_A.MANAGER.assetToLiabilityRatio();
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
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.LOV_WETH_DAI_LONG_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\twETH:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tDAI:", ethers.utils.formatUnits(prices[1], 30));
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

  await rebalanceDown(ethers.utils.parseEther("2"), 50, ethers.utils.parseEther("50"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN.maxExit(ADDRS.EXTERNAL.WETH_TOKEN);
  await exitLov_wETH(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
