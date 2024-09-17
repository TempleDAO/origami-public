import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, impersonateAndFund, mine } from "../../../helpers";
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, OrigamiAaveV3BorrowAndLend, OrigamiLovToken, OrigamiLovTokenFlashAndBorrowManager, OrigamiLovTokenMorphoManager, OrigamiMorphoBorrowAndLend, OrigamiOracleBase } from "../../../../../typechain";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const DEPOSIT_TOKEN_WHALE = "0xcD40532686B94aBc88b06B9705AAcBc14c8364D6";
const DEPOSIT_AMOUNT = "10000"; // sDAI
const AL_TARGET = "1.1"; // 90.9% LTV

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiLovToken;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  DEBT_TOKEN: IERC20Metadata;
  DEBT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiLovTokenMorphoManager;
  BORROW_LEND: OrigamiMorphoBorrowAndLend;
  DEPOSIT_TO_DEBT_ORACLE: OrigamiOracleBase;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.LOV_SDAI_A.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.LOV_SDAI_A.TOKEN.decimals(),
  DEBT_TOKEN: INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN,
  DEBT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
  MANAGER: INSTANCES.LOV_SDAI_A.MANAGER,
  BORROW_LEND: INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND,
  DEPOSIT_TO_DEBT_ORACLE: INSTANCES.ORACLES.SDAI_USDC,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.LOV_SDAI_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tsDAI:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tUSDC:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlov-sDAI-a:", ethers.utils.formatUnits(prices[2], 30));
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
  return _netAssets.mul(ONE_ETHER).div(_priceScaledTargetAL.sub(ONE_ETHER));
}

function supplyTokenToDebtTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x83F20F44975D03b1b09e64809B757c47f942BEeA&dst=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&amount=10000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("10000", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("11033.912924", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(toAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(fromAmount),
      data: ""
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&dst=0x83F20F44975D03b1b09e64809B757c47f942BEeA&amount=108172795484&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&includeProtocols=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("108172.795484", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("98036.649941750664721392", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000192f99de5c000000000000000000000000000000000000000000000a6149e9a2cb743079f80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001300000000000000000000000000000000000000000000001120000e400009a00a007e5c0d200000000000000000000000000000000000000000000000000007600000600a0fd53121f512083f20f44975d03b1b09e64809b757c47f942beea6b175474e89094c44da98b954eedeac495271d0f00046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900a0f2fa6b6683f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000014c293d34596e860f3f000000000000000003ef451c37e16d77780a06c4eca2783f20f44975d03b1b09e64809b757c47f942beea111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000053a717a"
    };
  } else {
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
  const oraclePrice = scaleBn(
    await TEST_CONTRACTS.DEPOSIT_TO_DEBT_ORACLE.convertAmount(
      TEST_CONTRACTS.DEPOSIT_TOKEN.address, ethers.utils.parseUnits("1", 18+TEST_CONTRACTS.DEBT_TOKEN_DECIMALS),
      PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN
    ),
    TEST_CONTRACTS.DEBT_TOKEN_DECIMALS,
    18-TEST_CONTRACTS.DEBT_TOKEN_DECIMALS,
  );
  
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`1inch reserves->debt price: ${ethers.utils.formatEther(dexPrice.price)}`);

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

  const alRatioBefore = await TEST_CONTRACTS.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    TEST_CONTRACTS.MANAGER.rebalanceDown(
      {
        supplyAmount: params.supplyAmount.mul(10000-10).div(10000),
        borrowAmount: params.borrowAmount, 
        swapData: params.swapData, 
        supplyCollateralSurplusThreshold: params.supplyCollateralSurplusThreshold,
        minNewAL: targetAL.mul(10000-100).div(10000),
        maxNewAL: targetAL.mul(10000+100).div(10000),
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

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);
  TEST_CONTRACTS = await getContracts();

  await dumpPrices();

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

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });