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

const WSTETH_WHALE = "0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d"; // Jump Trading
const WETH_WHALE = "0x8eb8a3b98659cce290402893d0123abb75e3ab28"; // avalanche bridge

async function investLovWstEth(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLovWstEth(%s, %f)", await account.getAddress(), amountBN);

  // mint wstETH
  await mine(
    INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\twstETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.connect(account).approve(
      ADDRS.LOV_WSTETH_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WSTETH_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
    10,
    0
  );

  console.log("\tlov-wstETH.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WSTETH_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lov-wstETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WSTETH_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLovWstEth(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLovWstEth(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-wstETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WSTETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wstETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WSTETH_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-wstETH.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_WSTETH_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-wstETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WSTETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wstETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WSTETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN)
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
  const [assets, liabilities, ] = await INSTANCES.LOV_WSTETH_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=1100000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("1100"))) {
    const toAmount = ethers.utils.parseEther("1281.813707961531063993");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ba1910bf341b00000000000000000000000000000000000000000000000000022be5e8c0684adaf5c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000006930000000000000000000000000000000006750006470006190005cf0005b500a0c9e75c480000000000000000060400000000000000000000000000000000000000000000000000058700031b00a0c9e75c4800000000001e0a0503020000000000000000000000000000000002ed00029e00024f0002000000f051124370e48e610d2e02d3d091a9d79c8eb9a54c5b1c7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0004475d39ecb000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000276a40000000000000000000000000000000000000000000000008e51f52d66168bf000000000000000000000000000000000000000000000000000000000663ed7e55100d17b3c9784510e33cd5b87b490e79253bcd81e2e7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0004458d30ac90000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d577e81624358a280000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000663ed7e500a0fbb7cd0600f01b0684c98cd7ada480bfdf6e43876422fa1fc10002000000000000000005de7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0fbb7cd060093d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c27f39c581f595b53c5cb19bd0b3f8da6c935e2ca0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc202a0000000000000000000000000000000000000000000000008569c7e9527d52a2aee63c1e501109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa7f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a007e5c0d200000000000000000000000000000000000000000000024800005600003c41207f39c581f595b53c5cb19bd0b3f8da6c935e2ca00004de0e9a3e00000000000000000000000000000000000000000000000000000000000000000020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8400a0c9e75c480000000000000016ff1c0000000000000000000000000000000000000000000001c40000f40000da00a007e5c0d20000000000000000000000000000000000000000000000000000b60000b05120dc24316b9ae028f1497c275eb9192a3ea0f67022ae7ab96520de3a18e5e111b5eaab095312d7fe8400443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bac8cbe6a448dc6a000206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db0510685b78aca6deae198fbf201c82daf6ca21942acc6ae7ab96520de3a18e5e111b5eaab095312d7fe8400446c08c57e000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000092c18930f66310476000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000457cbd180d095b5eb900000000000000000005a55a16ba4c0180a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&amount=1094766876178696457000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("1094.766876178696457"))) {
    const toAmount = ethers.utils.parseEther("939.235985192209567636");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b58f1418f9f414b280000000000000000000000000000000000000000000000197542441f96d9a7ca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000006bd00000000000000000000000000000000069f0006710006430005f90005df00a0c9e75c48000000000000000009010000000000000000000000000000000000000000000000000005b100016600a007e5c0d20000000000000000000000000000000000000001420000f20000d800003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004160dc24316b9ae028f1497c275eb9192a3ea0f6702200443df02124000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f7b9c4bfcb8e81750020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8451207f39c581f595b53c5cb19bd0b3f8da6c935e2ca0ae7ab96520de3a18e5e111b5eaab095312d7fe840004ea598cb0000000000000000000000000000000000000000000000000000000000000000000a0c9e75c48000000001f0a0601010100000000000000000000000000041d0003ce00037f0003300002000000f051104370e48e610d2e02d3d091a9d79c8eb9a54c5b1cc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2004475d39ecb000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d25000000000000000000000000000000000000000000000000754fed67dcf8cfdf00000000000000000000000000000000000000000000000000000000663ed81f5100d17b3c9784510e33cd5b87b490e79253bcd81e2ec02aaa39b223fe8d0a0e5c4f27ead9083c756cc2004458d30ac9000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007553a2ccb5c5b7dd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000663ed81f51004a585e0f7c18e2c414221d6402652d5e0990e5f8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a4a5dcbcdf000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000eb1c92f9f5ec9d817968afddb4b46c564cdedbe000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0fbb7cd0600f01b0684c98cd7ada480bfdf6e43876422fa1fc10002000000000000000005dec02aaa39b223fe8d0a0e5c4f27ead9083c756cc27f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a0fbb7cd060093d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2c02aaa39b223fe8d0a0e5c4f27ead9083c756cc27f39c581f595b53c5cb19bd0b3f8da6c935e2ca002a000000000000000000000000000000000000000000000000e34a1fe72b8ae886bee63c1e500109830a1aaad605bbf02a9dfa7b0b92ec2fb7daac02aaa39b223fe8d0a0e5c4f27ead9083c756cc20020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a0f2fa6b667f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000032ea84883f2db34f9400000000000000000004d7dadc87626d80a06c4eca277f39c581f595b53c5cb19bd0b3f8da6c935e2ca0111111125421ca6dc452d289314280a0f8842a650020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca0111111125421ca6dc452d289314280a0f8842a65000000053a717a"
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
  const oraclePrice = await INSTANCES.ORACLES.WSTETH_WETH.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch wstETH->WETH price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much WETH do we need to borrow in order to swap to that supplyAmount of wstETH
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

  const alRatioBefore = await INSTANCES.LOV_WSTETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.rebalanceDown(
      {
        flashLoanAmount: params.borrowAmount,
        swapData: params.swapData, 
        minExpectedReserveToken: params.supplyAmount.mul(10000-100).div(10000),
        minNewAL: targetAL.mul(10000-100).div(10000),
        maxNewAL: targetAL.mul(10000+100).div(10000),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await INSTANCES.LOV_WSTETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

export const applySlippage = (
  expectedAmount: BigNumber, 
  slippageBps: number
) => {
return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getWstEth(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, WSTETH_WHALE);
  await mine(INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await getWstEth(owner, ethers.utils.parseEther("150"));

  await investLovWstEth(bob, ethers.utils.parseEther("100"));

  await rebalanceDown(ethers.utils.parseEther("1.1"), 20, ethers.utils.parseEther("1100"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WSTETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN);
  await exitLovWstEth(bob, applySlippage(maxExitAmount, 1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
