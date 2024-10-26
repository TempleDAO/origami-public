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

const WEETH_WHALE = "0x267ed5f71ee47d3e45bb1569aa37889a2d10f91e";
const WETH_WHALE = "0x8eb8a3b98659cce290402893d0123abb75e3ab28"; // avalanche bridge

async function investLov_weETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLov_weETH(%s, %f)", await account.getAddress(), amountBN);

  // mint weETH
  await mine(
    INSTANCES.EXTERNAL.ETHERFI.WEETH_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tweETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ETHERFI.WEETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.ETHERFI.WEETH_TOKEN.connect(account).approve(
      ADDRS.LOV_WEETH_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WEETH_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN,
    10,
    0
  );

  console.log("\tlov-weETH.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WEETH_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lov-weETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WEETH_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_weETH(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_weETH(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-weETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WEETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of weETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ETHERFI.WEETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WEETH_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-weETH.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_WEETH_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-weETH:", ethers.utils.formatEther(
    await INSTANCES.LOV_WEETH_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of weETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ETHERFI.WEETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WEETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN)
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
  const [assets, liabilities, ] = await INSTANCES.LOV_WEETH_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=400000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("400"))) {
    const toAmount = ethers.utils.parseEther("415.771420088145504916");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015af1d78b58c40000000000000000000000000000000000000000000000000000b44fe67dc00cfb54a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000002220001f40001c600017c00a0c9e75c48000000000000002d040100000000000000000000000000000000000000000000014e0000ff00004f00a0fbb7cd0600b9debddf1d894c79d2b2d09f819ff9b856fca55200000000000000000000062acd5fe23c85820f7b72d0926fc9b05b43e359b7eec02aaa39b223fe8d0a0e5c4f27ead9083c756cc25100db74dfdd3bb46be8ce6c33dc9d82777bcfc3ded5cd5fe23c85820f7b72d0926fc9b05b43e359b7ee00443df02124000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e6de4cfe1adec82802a000000000000000000000000000000000000000000000000a2467819ed302876bee63c1e5007a415b19932c0105c82fdb6b720bb01b0cc2cae3cd5fe23c85820f7b72d0926fc9b05b43e359b7ee00a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000001689fccfb8019f6a9400000000000000000005166b307bde4280a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a65053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee&amount=310156954377872875966&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("310.156954377872875966"))) {
    const toAmount = ethers.utils.parseEther("298.094493982871941901");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x83800a8e000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000010d04adab9862621be00000000000000000000000000000000000000000000000814723173da7339862880000000000000000000007a415b19932c0105c82fdb6b720bb01b0cc2cae3053a717a"
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
  const oraclePrice = await INSTANCES.ORACLES.WEETH_WETH.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch weETH->WETH price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much WETH do we need to borrow in order to swap to that supplyAmount of weETH
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

  const alRatioBefore = await INSTANCES.LOV_WEETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WEETH_A.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_WEETH_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

export const applySlippage = (
  expectedAmount: BigNumber, 
  slippageBps: number
) => {
return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getWeEth(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, WEETH_WHALE);
  await mine(INSTANCES.EXTERNAL.ETHERFI.WEETH_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
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
      await INSTANCES.LOV_WEETH_A.MORPHO_BORROW_LEND.getMarketParams(),
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

  await getWeEth(owner, ethers.utils.parseEther("150"));

  await investLov_weETH(bob, ethers.utils.parseEther("100"));

  await supplyIntoMorpho(owner, ethers.utils.parseEther("500"));

  await rebalanceDown(ethers.utils.parseEther("1.3334"), 20, ethers.utils.parseEther("400"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WEETH_A.TOKEN.maxExit(ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN);
  await exitLov_weETH(bob, applySlippage(maxExitAmount, 1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
