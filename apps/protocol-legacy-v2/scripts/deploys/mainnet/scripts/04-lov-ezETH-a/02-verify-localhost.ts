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

const EZETH_WHALE = "0x22162DbBa43fE0477cdC5234E248264eC7C6EA7c";
const WETH_WHALE = "0x8eb8a3b98659cce290402893d0123abb75e3ab28"; // avalanche bridge

async function investLov_ezETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLov_ezETH(%s, %f)", await account.getAddress(), amountBN);

  // mint ezETH
  await mine(
    INSTANCES.EXTERNAL.RENZO.EZETH_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tezETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.RENZO.EZETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.RENZO.EZETH_TOKEN.connect(account).approve(
      ADDRS.LOV_EZETH_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_EZETH_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.RENZO.EZETH_TOKEN,
    10,
    0
  );

  console.log("\tlov-ezETH.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_EZETH_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lov-ezETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_EZETH_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_ezETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_ezETH(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-ezETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_EZETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of ezETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.RENZO.EZETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_EZETH_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.RENZO.EZETH_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-ezETH.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_EZETH_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-ezETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_EZETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of ezETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.RENZO.EZETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_EZETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.RENZO.EZETH_TOKEN)
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
  const [assets, liabilities, ] = await INSTANCES.LOV_EZETH_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xbf5495Efe5DB9ce00f80364C8B423567e58d2110&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=400000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("400"))) {
    const toAmount = ethers.utils.parseEther("397.691110657210472558");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015af1d78b58c40000000000000000000000000000000000000000000000000000ac789530adecc2c370000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000004210000000000000000000000000000000000000004030003d50003a700035d00a0c9e75c480000000000000000090100000000000000000000000000000000000000000000000000032f0001b300a007e5c0d200000000000000000000000000000000018f0001750000a500008b00004f02a0000000000000000000000000000000000000000000000000ebdc41b8a9918d77ee63c1e5001b9d58bea5ed5d935cc2e818dde1d796abff0bc0bf5495efe5db9ce00f80364c8b423567e58d211041207f39c581f595b53c5cb19bd0b3f8da6c935e2ca00004de0e9a3e00000000000000000000000000000000000000000000000000000000000000000020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe84512685b78aca6deae198fbf201c82daf6ca21942acc6ae7ab96520de3a18e5e111b5eaab095312d7fe8400446c08c57e000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000113c2b42c9809a0e4000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0c9e75c4800000000000000240c0200000000000000000000000000000000000000000000014e0000ff00004f02a0000000000000000000000000000000000000000000000000635f8f86a3fe2685ee63c1e501be80225f09645f172b079394312220637c440a63bf5495efe5db9ce00f80364c8b423567e58d2110510085de3add465a219ee25e04d22c39ab027cf5c12ebf5495efe5db9ce00f80364c8b423567e58d211000443df0212400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000254353e2716210cff00a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659bf5495efe5db9ce00f80364c8b423567e58d2110c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000158f12a615bd98586e00000000000000000005166b307bde4280a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000000000000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0xbf5495Efe5DB9ce00f80364C8B423567e58d2110&amount=402848125647449047274&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("402.848125647449047274"))) {
    const toAmount = ethers.utils.parseEther("403.873220954227389008");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015d6a40be5402140ea00000000000000000000000000000000000000000000000af26ef552aac9592800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000043d00000000000000000000000000000000000000041f0003f10003c300037900a0c9e75c480000000000000000090100000000000000000000000000000000000000000000000000034b0001cf00a007e5c0d20000000000000000000000000001ab00015c0001420000f20000d800003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004160dc24316b9ae028f1497c275eb9192a3ea0f6702200443df02124000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001179091f9519c634f0020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8451207f39c581f595b53c5cb19bd0b3f8da6c935e2ca0ae7ab96520de3a18e5e111b5eaab095312d7fe840004ea598cb000000000000000000000000000000000000000000000000000000000000000000020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca002a0000000000000000000000000000000000000000000000001183048188acf3aabee63c1e5011b9d58bea5ed5d935cc2e818dde1d796abff0bc07f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a0c9e75c4800000000000000200a0800000000000000000000000000000000000000000000014e0000ff00004f02a00000000000000000000000000000000000000000000000019393676ac5b1f5c7ee63c1e500be80225f09645f172b079394312220637c440a63c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2510085de3add465a219ee25e04d22c39ab027cf5c12ec02aaa39b223fe8d0a0e5c4f27ead9083c756cc200443df02124000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001f86bd04dddca6fb800a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bf5495efe5db9ce00f80364c8b423567e58d211000a0f2fa6b66bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000000000000000000000000015e4ddeaa55592b250000000000000000000052321676658a080a06c4eca27bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650020d6bdbf78bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a65000000053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  const oraclePrice = await INSTANCES.ORACLES.EZETH_WETH.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch ezETH->WETH price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much WETH do we need to borrow in order to swap to that supplyAmount of ezETH
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

  const alRatioBefore = await INSTANCES.LOV_EZETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_EZETH_A.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_EZETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

export const applySlippage = (
  expectedAmount: BigNumber, 
  slippageBps: number
) => {
return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getEzEth(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, EZETH_WHALE);
  await mine(INSTANCES.EXTERNAL.RENZO.EZETH_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function supplyIntoMorpho(owner: SignerWithAddress, supplyAmount: BigNumber) {
  const signer = await impersonateAndFund(owner, WETH_WHALE);

  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.connect(signer).approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON, 
      supplyAmount
    )
  );

  await mine(
    INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(signer).supply(
      await INSTANCES.LOV_EZETH_A.MORPHO_BORROW_LEND.getMarketParams(),
      supplyAmount,
      0,
      await signer.getAddress(),
      []
    )
  );
}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Currently depegged, so needs to be set higher than the deployment scripts
  await INSTANCES.ORACLES.EZETH_WETH.setMaxRelativeToleranceBps(150);

  await getEzEth(owner, ethers.utils.parseEther("150"));

  await investLov_ezETH(bob, ethers.utils.parseEther("100"));

  await supplyIntoMorpho(owner, ethers.utils.parseEther("500"));

  await rebalanceDown(ethers.utils.parseEther("1.25"), 20, ethers.utils.parseEther("400"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_EZETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.RENZO.EZETH_TOKEN);
  await exitLov_ezETH(bob, applySlippage(maxExitAmount, 1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
