import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, impersonateAndFund, mine } from "../../../helpers";
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, OrigamiAaveV3BorrowAndLend, OrigamiLovToken, OrigamiLovTokenFlashAndBorrowManager, OrigamiOracleBase } from "../../../../../typechain";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const DEPOSIT_TOKEN_WHALE = "0x3c22ec75ea5D745c78fc84762F7F1E6D82a2c5BF";

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiLovToken;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  DEBT_TOKEN: IERC20Metadata;
  DEBT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiLovTokenFlashAndBorrowManager;
  BORROW_LEND: OrigamiAaveV3BorrowAndLend;
  DEPOSIT_TO_DEBT_ORACLE: OrigamiOracleBase;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.LIDO.WSTETH_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.LOV_WSTETH_B.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.LOV_WSTETH_B.TOKEN.decimals(),
  DEBT_TOKEN: INSTANCES.EXTERNAL.WETH_TOKEN,
  DEBT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.WETH_TOKEN.decimals(),
  MANAGER: INSTANCES.LOV_WSTETH_B.MANAGER,
  BORROW_LEND: INSTANCES.LOV_WSTETH_B.SPARK_BORROW_LEND,
  DEPOSIT_TO_DEBT_ORACLE: INSTANCES.ORACLES.WSTETH_WETH,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
    ADDRS.EXTERNAL.LIDO.STETH_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.LOV_WSTETH_B.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\twstETH:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tstETH:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tWETH:", ethers.utils.formatUnits(prices[2], 30));
  console.log("\tlov-wstETH-b:", ethers.utils.formatUnits(prices[3], 30));
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=1100000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("1100", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("1291.124311095544009780", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&amount=1493247257661580157297&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseUnits("1493.247257661580157297", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("1271.864607077424279190", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000050f2f7f547b8aea171000000000000000000000000000000000000000000000022795564c134d2d74b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002930000000000000000000000000000000000000000000002750002470001fd00a0c9e75c48000000000000000009010000000000000000000000000000000000000000000000000001cf00018000a007e5c0d200000000000000000000000000000000015c0001420000f20000d800003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004160dc24316b9ae028f1497c275eb9192a3ea0f6702200443df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040c4efa578e13c9070020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8451207f39c581f595b53c5cb19bd0b3f8da6c935e2ca0ae7ab96520de3a18e5e111b5eaab095312d7fe840004ea598cb000000000000000000000000000000000000000000000000000000000000000000020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca002a000000000000000000000000000000000000000000000001f06cc5d5dbff6523cee63c1e500109830a1aaad605bbf02a9dfa7b0b92ec2fb7daac02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b667f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000044f2aac98269a5ae96000000000000000000048fca0501ed5480a06c4eca277f39c581f595b53c5cb19bd0b3f8da6c935e2ca0111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000053a717a"
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
        flashLoanAmount: params.borrowAmount,
        swapData: params.swapData, 
        minExpectedReserveToken: params.supplyAmount.mul(10000-100).div(10000),
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

  await getDepositTokens(owner, ethers.utils.parseUnits("150", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS));

  await investWithToken(bob, ethers.utils.parseUnits("100", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS));

  await rebalanceDown(ethers.utils.parseEther("1.0769"), 20, ethers.utils.parseEther("1100"));

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