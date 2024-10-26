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
    const toAmount = ethers.utils.parseEther("1286.012090328070383268");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ba1910bf341b00000000000000000000000000000000000000000000000000022db805f48df1933520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000004930000000000000000000000000000000004750004470004190003cf0003b500a0c9e75c480000000000000000060400000000000000000000000000000000000000000000000000038700011b00a0c9e75c48000000000000002409050000000000000000000000000000000000000000000000ed00009e00004f00a0fbb7cd0600f01b0684c98cd7ada480bfdf6e43876422fa1fc10002000000000000000005de7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0fbb7cd060093d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c27f39c581f595b53c5cb19bd0b3f8da6c935e2ca0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc202a000000000000000000000000000000000000000000000000a09de05522727dec5ee63c1e501109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa7f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a007e5c0d200000000000000000000000000000000000000000000024800005600003c41207f39c581f595b53c5cb19bd0b3f8da6c935e2ca00004de0e9a3e00000000000000000000000000000000000000000000000000000000000000000020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8400a0c9e75c480000000000000021ff110000000000000000000000000000000000000000000001c40000f40000da00a007e5c0d20000000000000000000000000000000000000000000000000000b60000b05100dc24316b9ae028f1497c275eb9192a3ea0f67022ae7ab96520de3a18e5e111b5eaab095312d7fe8400443df021240000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000071c5679a8669fc77b00206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db0512685b78aca6deae198fbf201c82daf6ca21942acc6ae7ab96520de3a18e5e111b5eaab095312d7fe8400446c08c57e000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dcde88a50245379f5000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000045b700be91be3266a400000000000000000005166b307bde4280a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&amount=1140694543730222391229&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("1140.694543730222391229"))) {
    const toAmount = ethers.utils.parseEther("975.481264173256214047");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003dd6511bdd2a315fbd00000000000000000000000000000000000000000000001a70c2d0b8dff5830f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000038d00000000000000000000000000000000000000036f0003410003130002c900a0c9e75c480000000000000000070300000000000000000000000000000000000000000000000000029b00018000a007e5c0d200000000000000000000000000000000015c0001420000f20000d800003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004160dc24316b9ae028f1497c275eb9192a3ea0f6702200443df0212400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000946b93c9e8e3059d10020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8451207f39c581f595b53c5cb19bd0b3f8da6c935e2ca0ae7ab96520de3a18e5e111b5eaab095312d7fe840004ea598cb000000000000000000000000000000000000000000000000000000000000000000020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a0c9e75c4800000000000000180e0c0000000000000000000000000000000000000000000000ed00009e00004f00a0fbb7cd0600f01b0684c98cd7ada480bfdf6e43876422fa1fc10002000000000000000005dec02aaa39b223fe8d0a0e5c4f27ead9083c756cc27f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a0fbb7cd060093d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2c02aaa39b223fe8d0a0e5c4f27ead9083c756cc27f39c581f595b53c5cb19bd0b3f8da6c935e2ca002a0000000000000000000000000000000000000000000000008e2556a318f842088ee63c1e500109830a1aaad605bbf02a9dfa7b0b92ec2fb7daac02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b667f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000034e185a171bfeb061f000000000000000000045f8c8a79916580a06c4eca277f39c581f595b53c5cb19bd0b3f8da6c935e2ca0111111125421ca6dc452d289314280a0f8842a650020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca0111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000000000053a717a"
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
