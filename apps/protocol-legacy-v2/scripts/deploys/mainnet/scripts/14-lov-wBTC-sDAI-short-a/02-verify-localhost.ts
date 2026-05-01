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

const SDAI_WHALE = "0x6337f2366E6f47FB26Ec08293867a607BCc7A0dB";
const WBTC_DECIMAL = 8;
const DECIMAL_DIFF = 10 ** (18 - WBTC_DECIMAL);

async function investLov_sDAI(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvest lov-wBTC/sDAI-short-a(%s, %f)", await account.getAddress(), amountBN);

  // mint sDAI
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tsDAI balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.connect(account).approve(
      ADDRS.LOV_WBTC_SDAI_SHORT_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    10,
    0
  );

  console.log("\tlov-wBTC/sDAI-short-a.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAccount balance of lov-wBTC/sDAI-short-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_sDAI(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_wBTC(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-wBTC/sDAI-short-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of sDAI:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.balanceOf(account.getAddress())
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    slippageBps,
    0
  );

  console.log("\tlov-wBTC/sDAI-short-a.exitToToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedToTokenAmount));
  await mine(
    INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-wBTC/sDAI-short-a:", ethers.utils.formatEther(
    await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of sDAI:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.balanceOf(account.getAddress())
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.maxExit(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN)
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
  const [assets, liabilities,] = await INSTANCES.LOV_WBTC_SDAI_SHORT_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x83F20F44975D03b1b09e64809B757c47f942BEeA&dst=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599&amount=50000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&allowPartialFill=false" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("50000"))) {
    const toAmount = ethers.utils.parseUnits("0.84214773", WBTC_DECIMAL);
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).mul(DECIMAL_DIFF).div(fromAmount),
      data: "0x"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599&dst=0x83F20F44975D03b1b09e64809B757c47f942BEeA&amount=77368498&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&allowPartialFill=false&parts=1&excludedProtocols=PMM15,PMM11,BALANCER_V2,DODO_V2&includeProtocols=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("0.77368498", WBTC_DECIMAL))) {
    const toAmount = ethers.utils.parseEther("44598.662069602260074174");
    return {
      toAmount,
      price: fromAmount.mul(DECIMAL_DIFF).mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000049c8cb20000000000000000000000000000000000000000000004b8d962653b7531df5f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001ad00000000000000000000000000000000000000018f0001610001330000e900a007e5c0d20000000000000000000000000000000000000000000000c500005500004f02a000000000000000000000000000000000000000000000000000000005aaaf2424ee63c1e50199ac8ca7087fa4a2a1fb6357269965a2014abc352260fac5e5542a773aa44fbcfedf7c193bc2c59900a0fd53121f512083f20f44975d03b1b09e64809b757c47f942beea6b175474e89094c44da98b954eedeac495271d0f00046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900a0f2fa6b6683f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000000971b2c4ca76ea63bebe00000000000000003fa0a1f8cefc2af580a06c4eca2783f20f44975d03b1b09e64809b757c47f942beea111111125421ca6dc452d289314280a0f8842a650020d6bdbf7883f20f44975d03b1b09e64809b757c47f942beea111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000000000053a717a"
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
  const oraclePrice = await INSTANCES.ORACLES.WBTC_SDAI.convertAmount(
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    ONE_ETHER.mul(DECIMAL_DIFF),
    PriceType.SPOT_PRICE, 
    RoundingMode.ROUND_DOWN
  );
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch sDAI->wBTC price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much wBTC do we need to borrow in order to swap to that supplyAmount of sDAI
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

  const alRatioBefore = await INSTANCES.LOV_WBTC_SDAI_SHORT_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_WBTC_SDAI_SHORT_A.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_WBTC_SDAI_SHORT_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));
}

export const applySlippage = (
  expectedAmount: BigNumber,
  slippageBps: number
) => {
  return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getSDAI(owner: SignerWithAddress) {
  const signer = await impersonateAndFund(owner, SDAI_WHALE);
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.connect(signer).transfer(owner.getAddress(), ethers.utils.parseEther("100000")));
}

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.WBTC_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    ADDRS.LOV_WBTC_SDAI_SHORT_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\twBTC:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tsDAI:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlovToken:", ethers.utils.formatUnits(prices[2], 30));
}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await dumpPrices();

  await getSDAI(owner);

  await investLov_sDAI(bob, ethers.utils.parseEther("50000"));

  await rebalanceDown(ethers.utils.parseEther("2"), 50, ethers.utils.parseEther("50000"));

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN.maxExit(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN);
  await exitLov_sDAI(bob, applySlippage(maxExitAmount, 1));
  
  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
