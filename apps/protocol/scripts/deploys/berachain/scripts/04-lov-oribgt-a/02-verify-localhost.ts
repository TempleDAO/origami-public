import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { impersonateAndFund, mine, runAsyncMain } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, IOrigamiOracle__factory, OrigamiErc4626Oracle, OrigamiEulerV2BorrowAndLend, OrigamiLovToken, OrigamiLovTokenMorphoManagerMarketAL } from "../../../../../typechain";
import { getDeployContext } from "../../deploy-context";
import { getSwap } from "../../../swaps/oogabooga";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const DEPOSIT_TOKEN_WHALE = "0x5286bC17220D51a36e55F5664d63A61Bf9b127A6";
const DEPOSIT_AMOUNT = "1000";  // oriBGT
const AL_TARGET = "1.3889";     // 82% LTV

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiLovToken;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  DEBT_TOKEN: IERC20Metadata;
  DEBT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiLovTokenMorphoManagerMarketAL;
  BORROW_LEND: OrigamiEulerV2BorrowAndLend;
  DEPOSIT_TO_DEBT_ORACLE: OrigamiErc4626Oracle;
  SWAPPER_ADDRESS: string;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.VAULTS.ORIBGT.TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.VAULTS.ORIBGT.TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.LOV_ORIBGT_A.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.LOV_ORIBGT_A.TOKEN.decimals(),
  DEBT_TOKEN: INSTANCES.EXTERNAL.BERACHAIN.WBERA_TOKEN,
  DEBT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.BERACHAIN.WBERA_TOKEN.decimals(),
  MANAGER: INSTANCES.LOV_ORIBGT_A.MANAGER,
  BORROW_LEND: INSTANCES.LOV_ORIBGT_A.EULER_V2_BORROW_LEND,
  DEPOSIT_TO_DEBT_ORACLE: INSTANCES.ORACLES.ORIBGT_WBERA,
  SWAPPER_ADDRESS: await INSTANCES.LOV_ORIBGT_A.EULER_V2_BORROW_LEND.swapper(),
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V5.tokenPrices([
    ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
    ADDRS.LOV_ORIBGT_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tiBGT:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\toriBGT:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tWBERA:", ethers.utils.formatUnits(prices[2], 30));
  console.log("\tlov-oriBGT-a:", ethers.utils.formatUnits(prices[3], 30));
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
  if (fromAmount.eq(ethers.utils.parseUnits("1000.0", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("1816.243906115057895893", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(toAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(fromAmount),
      data: ""
    };
  } else {
    const swapData = await getSwap(
      process.env.OOGA_BOOGA_API_KEY || "",
      {
        tokenIn: TEST_CONTRACTS.DEPOSIT_TOKEN.address,
        tokenOut: TEST_CONTRACTS.DEBT_TOKEN.address,
        to: TEST_CONTRACTS.SWAPPER_ADDRESS,
        amount: fromAmount.toString(),
        slippage: 1,
    });
    if (swapData.status != 'Success') throw new Error("Ooga booga quote failed");

    console.log("\n*** SUBSTITUTE THESE INTO supplyTokenToDebtTokenQuote(): ***");
    console.log(`\tfromAmount=${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
    console.log(`\ttoAmount=${ethers.utils.formatUnits(swapData.assumedAmountOut, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);

    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
  }
}

async function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  if (fromAmount.eq(ethers.utils.parseUnits("3626.726180873874733653", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("1980.05946147261055645", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(toAmount),
      data: "0xd46cadbc00000000000000000000000069696969696969696969696969696969696969690000000000000000000000000000000000000000000000c49aefb64934647a5500000000000000000000000069f1e971257419b1e9c405a553f252c64a29a30a00000000000000000000000000000000000000000000006b56d855679a361a220000000000000000000000000000000000000000000000000000000000000001000000000000000000000000c6e7df5e7b4f2a278906862b61205850344d4e7d00000000000000000000000000000000000000000000000000000000000001200000000000000000000000000e29ad2925079f313817d09fcadbdf3a911256540000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000034269f1E971257419B1E9C405A553f252c64A29A30a0100000000000000000000000000000000000000000000006b56d855679a361a220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001696969696969696969696969696969696969696905022201d890aB8Fa2FbD4c8adaeda4C7ea270d94eFffb4a000e29aD2925079f313817D09Fcadbdf3A91125654067401FCB24b3b7E87E3810b150d25D5964c566D9A2B6F010e29aD2925079f313817D09Fcadbdf3A911256541612094Be03f781C497A489E3cB0287833452cA9B9E80B62c030b29a6fef1b32677499e4a1f1852a8808c00000000000000000000000c69b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe50e29aD2925079f313817D09Fcadbdf3A91125654fb2a0112bf773F18cEC56F14e7cb91d82984eF5A3148EE010e29aD2925079f313817D09Fcadbdf3A91125654ffff0101ad86d9946C04917970578Ff50f6AE4822214dA010e29aD2925079f313817D09Fcadbdf3A91125654019b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe50213b1018Fef9a691Fd602A5C751E241Aa96DDed1Aad06CB010e29aD2925079f313817D09Fcadbdf3A91125654ffff013Bc7D023Ed3bd4e3CAEC29fdfe1b19Df28B202e8010e29aD2925079f313817D09Fcadbdf3A9112565401D2C41BF4033A83C0FC3A7F58a392Bf37d6dCDb5801ffff17e5CAB105E2dC57bf0c27670D1aED543Dd526B68b0e29aD2925079f313817D09Fcadbdf3A911256540001549943e04f40284185054145c6E4e9568C1D324101ffff094Be03f781C497A489E3cB0287833452cA9B9E80Bf961a8f6d8c69e7321e78d254ecafbcc3a637621000000000000000000000001FCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce0e29aD2925079f313817D09Fcadbdf3A9112565401FCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce01ffff01861B8b3772494bA8cC7d14D66bb7F643E8671dcB000e29aD2925079f313817D09Fcadbdf3A9112565401ac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b01ffff1369f1E971257419B1E9C405A553f252c64A29A30a0e29aD2925079f313817D09Fcadbdf3A91125654000000000000000000000000000000000000000000000000000000000000"
    };
  } else {
    const swapData = await getSwap(
      process.env.OOGA_BOOGA_API_KEY || "",
      {
        tokenIn: TEST_CONTRACTS.DEBT_TOKEN.address,
        tokenOut: TEST_CONTRACTS.DEPOSIT_TOKEN.address,
        to: TEST_CONTRACTS.SWAPPER_ADDRESS,
        amount: fromAmount.toString(),
        slippage: 1,
      },
    );
    if (swapData.status != 'Success') throw new Error("Ooga booga quote failed");
    console.log("\n*** SUBSTITUTE THESE INTO debtTokenToSupplyTokenQuote(): ***");
    console.log(`\tfromAmount=${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);
    console.log(`\ttoAmount=${ethers.utils.formatUnits(swapData.assumedAmountOut, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
    console.log(`\tdata=${swapData.tx?.data}`);

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
    18+TEST_CONTRACTS.DEBT_TOKEN_DECIMALS,
    18,
  );
  
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = await supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`OogaBooga reserves->debt price: ${ethers.utils.formatEther(dexPrice.price)}`);

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
  const quote = await debtTokenToSupplyTokenQuote(borrowAmount);
  console.log(`OogaBooga price: ${ethers.utils.formatEther(quote.price)}`);

  const supplyCollateralSurplusThreshold = ethers.utils.parseEther("0");

  return {
    supplyAmount,
    borrowAmount,
    swapData: encodeSwapData(ADDRS.EXTERNAL.OOGABOOGA.ROUTER, quote.data),
    supplyCollateralSurplusThreshold
  };
}

function encodeSwapData(routerAddress: string, swapData: string): string {
  return ethers.utils.defaultAbiCoder.encode(
    ['tuple(address router, bytes data)'],
    [{router: routerAddress, data: swapData}]
  );
}

async function rebalanceDown(
  targetAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await TEST_CONTRACTS.MANAGER.assetToLiabilityRatio();
  console.log("MARKET alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  await mine(
    TEST_CONTRACTS.MANAGER.rebalanceDown(
      {
        supplyAmount: params.supplyAmount,
        borrowAmount: params.borrowAmount, 
        swapData: params.swapData, 
        supplyCollateralSurplusThreshold: params.supplyCollateralSurplusThreshold,
        // These are always specified in terms of the borrow/lend terms
        minNewAL: ethers.utils.parseEther(AL_TARGET).mul(10000-100).div(10000),
        maxNewAL: ethers.utils.parseEther(AL_TARGET).mul(10000+100).div(10000),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await TEST_CONTRACTS.MANAGER.assetToLiabilityRatio();
  console.log("MARKET alRatioAfter:", ethers.utils.formatEther(alRatioAfter));
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
    await INSTANCES.ORACLES.IBGT_WBERA.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.IBGT_WBERA.latestPrice(0, 0)
    )
  );

  console.log(
    await INSTANCES.ORACLES.ORIBGT_WBERA.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.ORIBGT_WBERA.latestPrice(0, 0)
    )
  );
}

async function marketALTarget(owner: SignerWithAddress) {
  const morphoToMarketALPrice = IOrigamiOracle__factory.connect(await TEST_CONTRACTS.MANAGER.morphoALToMarketALOracle(), owner);
  const price = await morphoToMarketALPrice.latestPrice(0, 0);
  console.log(`MORPHO A/L to MARKET A/L conversion = ${ethers.utils.formatEther(price)}`);
  return ethers.utils.parseEther(AL_TARGET).mul(price).div(ONE_ETHER);
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

  const MARKET_AL_TARGET = await marketALTarget(owner);
  console.log("market AL Target:", MARKET_AL_TARGET);
  await rebalanceDown(MARKET_AL_TARGET, 100, depositAmount);

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await TEST_CONTRACTS.VAULT_TOKEN.maxExit(TEST_CONTRACTS.DEPOSIT_TOKEN.address);
  await exitToToken(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}


runAsyncMain(main);
