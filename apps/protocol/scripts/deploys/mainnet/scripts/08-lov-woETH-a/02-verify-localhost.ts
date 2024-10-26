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

const WOETH_WHALE = "0xC460B0b6c9b578A4Cb93F99A691e16dB96Ee5833";
const WETH_WHALE = "0x8eb8a3b98659cce290402893d0123abb75e3ab28"; // avalanche bridge

async function investLov_woETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLov_woETH(%s, %f)", await account.getAddress(), amountBN);

  // mint woETH
  await mine(
    INSTANCES.EXTERNAL.ORIGIN.WOETH_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\twoETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ORIGIN.WOETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.ORIGIN.WOETH_TOKEN.connect(account).approve(
      ADDRS.LOV_WOETH_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WOETH_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN,
    10,
    0
  );

  console.log("\tlov-woETH.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WOETH_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lov-woETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WOETH_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_woETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_woETH(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-woETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WOETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of woETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ORIGIN.WOETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WOETH_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-woETH.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_WOETH_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-woETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WOETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of woETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ORIGIN.WOETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WOETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN)
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
  return remainderAmount.mul(MAX_BPS).div(MAX_BPS-basisPoints);
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
  const [assets, liabilities, ] = await INSTANCES.LOV_WOETH_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xDcEe70654261AF21C44c093C300eD3Bb97b78192&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=1100000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0xDcEe70654261AF21C44c093C300eD3Bb97b78192" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("1100"))) {
    const toAmount = ethers.utils.parseEther("1200.539860307003308642");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000dcee70654261af21c44c093c300ed3bb97b78192000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ba1910bf341b000000000000000000000000000000000000000000000000000208a6b311bb401fd310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002340000000000000000000000000000000000000002160001e80001ba00017000a007e5c0d200000000000000000000000000000000000000014c00013200012c00007c4120dcee70654261af21c44c093c300ed3bb97b781920004ba0876520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09512094b17476a93b3262d87b9a326965d1e91f9c13e7856c4efb76c1d1ae02e20ceb03a2a6a08b0b8dc300443df021240000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000208a6b311bb401fd3100206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db000a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000004114d662376803fa620000000000000000000516a1d0c46ad980a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a65000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0xDcEe70654261AF21C44c093C300eD3Bb97b78192&amount=430946836546107915699&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0xDcEe70654261AF21C44c093C300eD3Bb97b78192" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("430.946836546107915699"))) {
    const toAmount = ethers.utils.parseEther("394.240074747657790107");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dcee70654261af21c44c093c300ed3bb97b78192000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000175c96b895a116bdb300000000000000000000000000000000000000000000000aaf970d9ad2cb914d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000024f00000000000000000000000000000000000000000000000000023100020300a007e5c0d20000000000000000000000000000000000000000000001df00016f00015500a0c9e75c480000000000000031000100000000000000000000000000000000000000000000012700008b00004f02a00000000000000000000000000000000000000000000000003bcda47eaa6377a3ee63c1e50052299416c469843f4e0d54688099966a6c7d720fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc24101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d0000000000000000000000000000000000000000000000000000000000000000416094b17476a93b3262d87b9a326965d1e91f9c13e700443df0212400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b71fd74ca884c76900020d6bdbf78856c4efb76c1d1ae02e20ceb03a2a6a08b0b8dc35120dcee70654261af21c44c093c300ed3bb97b78192856c4efb76c1d1ae02e20ceb03a2a6a08b0b8dc300046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111125421ca6dc452d289314280a0f8842a650020d6bdbf78dcee70654261af21c44c093c300ed3bb97b78192111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000053a717a"
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
  const oraclePrice = await INSTANCES.ORACLES.WOETH_WETH.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch woETH->wETH price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much wETH do we need to borrow in order to swap to that supplyAmount of woETH
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
    supplyCollateralSurplusThreshold
  };
}

async function rebalanceDown(
  targetAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await INSTANCES.LOV_WOETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WOETH_A.MANAGER.rebalanceDown(
      {
        supplyAmount: params.supplyAmount.mul(10000-100).div(10000),
        borrowAmount: params.borrowAmount, 
        swapData: params.swapData, 
        supplyCollateralSurplusThreshold: params.supplyCollateralSurplusThreshold,
        minNewAL: targetAL.mul(10000-100).div(10000),
        maxNewAL: targetAL.mul(10000+100).div(10000),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await INSTANCES.LOV_WOETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

async function supplyDebtTokenIntoMorpho(owner: SignerWithAddress, supplyAmount: BigNumber) {
  const signer = await impersonateAndFund(owner, WETH_WHALE);
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.connect(signer).approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON, 
      supplyAmount
    )
  );

  await mine(
    INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(signer).supply(
      await INSTANCES.LOV_WOETH_A.MORPHO_BORROW_LEND.getMarketParams(),
      supplyAmount,
      0,
      await signer.getAddress(),
      []
    )
  );
}

export const applySlippage = (
  expectedAmount: BigNumber, 
  slippageBps: number
) => {
return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getWoETH(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, WOETH_WHALE);
  await mine(INSTANCES.EXTERNAL.ORIGIN.WOETH_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V1.tokenPrices([
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.ORIGIN.OETH_TOKEN,
    ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN,
    ADDRS.LOV_WOETH_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\twETH:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\toETH:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\twoETH:", ethers.utils.formatUnits(prices[2], 30));
  console.log("\tlov-woETH-a:", ethers.utils.formatUnits(prices[3], 30));
}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await dumpPrices();

  await getWoETH(owner, ethers.utils.parseEther("150"));

  await investLov_woETH(bob, ethers.utils.parseEther("100"));

  await supplyDebtTokenIntoMorpho(owner, ethers.utils.parseEther("10000"));

  await rebalanceDown(ethers.utils.parseEther("1.25"), 50, ethers.utils.parseEther("1100"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WOETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN);
  await exitLov_woETH(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
