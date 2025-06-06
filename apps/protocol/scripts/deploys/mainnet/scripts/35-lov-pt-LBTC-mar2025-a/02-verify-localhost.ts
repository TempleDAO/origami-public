import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { impersonateAndFund, mine, runAsyncMain } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, OrigamiLovToken, OrigamiLovTokenMorphoManager, OrigamiMorphoBorrowAndLend, OrigamiPendlePtToAssetOracle } from "../../../../../typechain";
import { swapExactPtForToken, swapExactTokenForPt } from "../../../swaps/pendle";
import { getDeployContext } from "../../deploy-context";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const DEPOSIT_TOKEN_WHALE = "0xEd0C6079229E2d407672a117c22b62064f4a4312";
const DEPOSIT_AMOUNT = "1"; // PT-LBTC-Mar2025-a
const AL_TARGET = "1.25";     // 80% LTV

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiLovToken;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  DEBT_TOKEN: IERC20Metadata;
  DEBT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiLovTokenMorphoManager;
  BORROW_LEND: OrigamiMorphoBorrowAndLend;
  DEPOSIT_TO_DEBT_ORACLE: OrigamiPendlePtToAssetOracle;
  SWAPPER_ADDRESS: string;
  PT_MARKET_ADDRESS: string;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.LOV_PT_LBTC_MAR_2025_A.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.LOV_PT_LBTC_MAR_2025_A.TOKEN.decimals(),
  DEBT_TOKEN: INSTANCES.EXTERNAL.LOMBARD.LBTC_TOKEN,
  DEBT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.LOMBARD.LBTC_TOKEN.decimals(),
  MANAGER: INSTANCES.LOV_PT_LBTC_MAR_2025_A.MANAGER,
  BORROW_LEND: INSTANCES.LOV_PT_LBTC_MAR_2025_A.MORPHO_BORROW_LEND,
  DEPOSIT_TO_DEBT_ORACLE: INSTANCES.ORACLES.PT_LBTC_MAR_2025_LBTC,
  SWAPPER_ADDRESS: await INSTANCES.LOV_PT_LBTC_MAR_2025_A.MORPHO_BORROW_LEND.swapper(),
  PT_MARKET_ADDRESS: ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.MARKET,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN,
    ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN,
    ADDRS.LOV_PT_LBTC_MAR_2025_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tLBTC:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tPT LBTC Mar2025:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlov-PT-LBTC-Mar2025-a:", ethers.utils.formatUnits(prices[2], 30));
}

async function investWithToken(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvest(%s, %f)", await account.getAddress(), amountBN);

  await mine(
    TEST_CONTRACTS.DEPOSIT_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.DEPOSIT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS
  ));
  await mine(
    TEST_CONTRACTS.DEPOSIT_TOKEN.connect(account).approve(
      TEST_CONTRACTS.VAULT_TOKEN.address,
      amountBN
    )
  );

  const quoteData = await TEST_CONTRACTS.VAULT_TOKEN.investQuote(
    amountBN,
    TEST_CONTRACTS.DEPOSIT_TOKEN.address,
    10,
    0
  );

  console.log("\tinvestWithToken. Expect:", ethers.utils.formatUnits(
    quoteData.quoteData.expectedInvestmentAmount,
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS,
  ));
  await mine(
    TEST_CONTRACTS.VAULT_TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS,
  ));
}

async function exitToToken(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexit(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of vault:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS
  ));
  console.log("\t\tAccount balance of deposit token:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.DEPOSIT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await TEST_CONTRACTS.VAULT_TOKEN.exitQuote(
    amountBN,
    TEST_CONTRACTS.DEPOSIT_TOKEN.address,
    slippageBps, 
    0
  );

  console.log("\texitToToken. Expect:", ethers.utils.formatUnits(
    quoteData.quoteData.expectedToTokenAmount,
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS,
  ));
  await mine(
    TEST_CONTRACTS.VAULT_TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of vault:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS
  ));
  console.log("\t\tAccount balance of deposit token:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.DEPOSIT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.maxExit(TEST_CONTRACTS.DEPOSIT_TOKEN.address),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS,
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
  const [assets, liabilities, ] = await TEST_CONTRACTS.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
  console.log("assets:", ethers.utils.formatUnits(assets, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS));
  console.log("liabilities:", ethers.utils.formatUnits(liabilities, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS));

  const _netAssets = assets.sub(
    targetAL.mul(liabilities).div(ONE_ETHER)
  );
  const _priceScaledTargetAL = inverseSubtractBps(
    targetAL.mul(dexPrice).div(oraclePrice),
    slippageBps
  );
  console.log(targetAL.toString(), dexPrice.toString(), oraclePrice.toString());

  return _netAssets.mul(ONE_ETHER).div(_priceScaledTargetAL.sub(ONE_ETHER));
}

async function supplyTokenToDebtTokenQuote(fromAmount: BigNumber) {
  if (fromAmount.eq(ethers.utils.parseUnits(DEPOSIT_AMOUNT, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("0.98049704", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(toAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(fromAmount),
      data: ""
    };
  } else {
    const swapData = await swapExactPtForToken({
      chainId: 1,
      receiverAddr: TEST_CONTRACTS.SWAPPER_ADDRESS,
      marketAddr: TEST_CONTRACTS.PT_MARKET_ADDRESS,
      amountPtIn: fromAmount.toString(),
      tokenOutAddr: TEST_CONTRACTS.DEBT_TOKEN.address,
      slippage: 0.5, // in pct
    });
    console.log("\n*** SUBSTITUTE THESE INTO supplyTokenToDebtTokenQuote(): ***");
    console.log(`\tfromAmount=${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
    console.log(`\ttoAmount=${ethers.utils.formatUnits(swapData.data.amountTokenOut, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);
    console.log(`\tdata=${swapData.transaction.data}`);

    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
  }
}

async function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  if (fromAmount.eq(ethers.utils.parseUnits("4.01404373", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("4.09053715", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(toAmount),
      data: "0xc81f847a000000000000000000000000d3674dc273236213379207ca3ac6b0f292c47dd500000000000000000000000070b70ac0445c3ef04e314dfda6caafd825428221000000000000000000000000000000000000000000000000000000000c30d50900000000000000000000000000000000000000000000000000000000097e757c000000000000000000000000000000000000000000000000000000005553ef380000000000000000000000000000000000000000000000000000000012fceaf9000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000094c11beb634000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002800000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000000000000000000000000000000000000017ecf1d50000000000000000000000008236a87084f8b84306f72007f36f2618a5634494000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c9b3e2c3ec88b1b4c0cd853f4321000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000003800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000001a4f341fc14c5c643ee2b540e3f4c879348f890303f63dad2bc4caa904987f413a94bb00000000000000000000000000000000000000000000000000000000676d9753000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000008236a87084f8b84306f72007f36f2618a56344940000000000000000000000001e30afeb27c0544f335f8aa21e0a9599c273823a0000000000000000000000001c4f216efa7f7702e12e5133c2001d1a82c82d0e0000000000000000000000001c4f216efa7f7702e12e5133c2001d1a82c82d0e00000000000000000000000000000000000000000000000000000000001a4f34000000000000000000000000000000000000000000000000010637eb2f11a5ec0000000000000000000000000000000000000000000000000c7d713b49da000000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004152f0a45de5e1b8e91ccb4f5b898719a68f2a28831715093b899db8ce350885f63d0da88008ea2d8c6e287b5c32c6571b7da8a29aea04f0fe33fb03b9ce45edff1c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    };
  } else {
    const swapData = await swapExactTokenForPt({
      chainId: 1,
      receiverAddr: TEST_CONTRACTS.SWAPPER_ADDRESS,
      marketAddr: TEST_CONTRACTS.PT_MARKET_ADDRESS,
      amountTokenIn: fromAmount.toString(),
      tokenInAddr: TEST_CONTRACTS.DEBT_TOKEN.address,
      slippage: 0.5, // in pct
    });
    console.log("\n*** SUBSTITUTE THESE INTO debtTokenToSupplyTokenQuote(): ***");
    console.log(`\tfromAmount=${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);
    console.log(`\ttoAmount=${ethers.utils.formatUnits(swapData.data.amountPtOut, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
    console.log(`\tdata=${swapData.transaction.data}`);

    throw Error(`Unknown debtTokenToSupplyTokenQuote amount: ${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);
  }
}

function scaleBn(
  amount: BigNumber,
  fromDecimals: number,
  toDecimals: number
): BigNumber {
  if (toDecimals > fromDecimals) {
    return amount.mul(BigNumber.from(10).pow(toDecimals-fromDecimals));
  } else if (toDecimals < fromDecimals) {
    return amount.div(BigNumber.from(10).pow(fromDecimals-toDecimals));
  } else {
    return amount;
  }
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  // Scale such that the origami oracle price and market quoted price are 
  // 18 decimal BigNumber's
  const oraclePrice = scaleBn(
    await TEST_CONTRACTS.DEPOSIT_TO_DEBT_ORACLE.convertAmount(
      TEST_CONTRACTS.DEPOSIT_TOKEN.address, ethers.utils.parseUnits("1", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS+TEST_CONTRACTS.DEBT_TOKEN_DECIMALS),
      PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN
    ),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS+TEST_CONTRACTS.DEBT_TOKEN_DECIMALS,
    18,
  );
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = await supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`Pendle reserves->debt price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatUnits(supplyAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS));

  // How much debt token do we need to borrow in order to swap to that supplyAmount of reserve token
  // Use the dex price
  let borrowAmount = scaleBn(
    supplyAmount.mul(dexPrice.price).div(ONE_ETHER), 
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS, 
    TEST_CONTRACTS.DEBT_TOKEN_DECIMALS
  );

  // Add slippage to the amount we actually borrow so after the swap
  // we ensure we have more collateral than supplyAmount
  borrowAmount = inverseSubtractBps(borrowAmount, slippageBps);
  console.log("borrowAmount:", ethers.utils.formatUnits(borrowAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS));

  // Get the swap data
  const oneInchQuote = await debtTokenToSupplyTokenQuote(borrowAmount);
  console.log(`Pendle swap price: ${ethers.utils.formatEther(oneInchQuote.price)}`);

  const supplyCollateralSurplusThreshold = ethers.utils.parseEther("1000000");

  return {
    supplyAmount,
    borrowAmount,
    swapData: encodeSwapData(ADDRS.EXTERNAL.PENDLE.ROUTER, oneInchQuote.data),
    supplyCollateralSurplusThreshold
  };
}

function encodeSwapData(routerAddress: string, oneinchSwapData: string): string {
  return ethers.utils.defaultAbiCoder.encode(
    ['tuple(address router, bytes data)'],
    [{router: routerAddress, data: oneinchSwapData}]
  );
}

async function rebalanceDown(
  targetAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await TEST_CONTRACTS.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    TEST_CONTRACTS.MANAGER.rebalanceDown(
      {
        supplyAmount: params.supplyAmount,
        borrowAmount: params.borrowAmount, 
        swapData: params.swapData, 
        supplyCollateralSurplusThreshold: params.supplyCollateralSurplusThreshold,
        // The slippage is high here, since the PT quotes we got are way out of date
        // 0.91 (oracle @ older block time) vs 0.96 (market quote as of now)
        minNewAL: targetAL.mul(10000-3000).div(10000),
        maxNewAL: targetAL.mul(10000+3000).div(10000),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await TEST_CONTRACTS.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));
}

export const applySlippage = (
  expectedAmount: BigNumber, 
  slippageBps: number
) => {
return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getDepositTokens(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, DEPOSIT_TOKEN_WHALE);
  await mine(TEST_CONTRACTS.DEPOSIT_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function dumpOracles() {
  console.log(
    await INSTANCES.ORACLES.PT_LBTC_MAR_2025_LBTC.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.PT_LBTC_MAR_2025_LBTC.latestPrice(0, 0)
    )
  );
}

async function main() {
  ({ ADDRS, INSTANCES } = await getDeployContext(__dirname));
  const [owner, bob] = await ethers.getSigners();
  TEST_CONTRACTS = await getContracts();

  await dumpPrices();
  await dumpOracles();

  const depositAmount = ethers.utils.parseUnits(DEPOSIT_AMOUNT, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
  await getDepositTokens(owner, depositAmount);

  await investWithToken(bob, depositAmount);

  await rebalanceDown(ethers.utils.parseEther(AL_TARGET), 20, depositAmount);

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await TEST_CONTRACTS.VAULT_TOKEN.maxExit(TEST_CONTRACTS.DEPOSIT_TOKEN.address);
  await exitToToken(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}


runAsyncMain(main);
