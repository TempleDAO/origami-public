import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { impersonateAndFund, mine, runAsyncMain } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, IOrigamiOracle__factory, OrigamiCrossRateOracle, OrigamiLovToken, OrigamiLovTokenMorphoManagerMarketAL, OrigamiMorphoBorrowAndLend } from "../../../../../typechain";
import { swapExactPtForToken, swapExactTokenForPt } from "../../../swaps/pendle";
import { getDeployContext } from "../../deploy-context";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const DEPOSIT_TOKEN_WHALE = "0x8C0824fFccBE9A3CDda4c3d409A0b7447320F364";
const DAI_WHALE = "0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B";
const DEPOSIT_AMOUNT = "10000"; // PT-sUSDe-May2025
const AL_TARGET = "1.1666";     // 85.7% LTV

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiLovToken;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  DEBT_TOKEN: IERC20Metadata;
  DEBT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiLovTokenMorphoManagerMarketAL;
  BORROW_LEND: OrigamiMorphoBorrowAndLend;
  DEPOSIT_TO_DEBT_ORACLE: OrigamiCrossRateOracle;
  SWAPPER_ADDRESS: string;
  PT_MARKET_ADDRESS: string;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.PENDLE.SUSDE_MAY_2025.PT_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.PENDLE.SUSDE_MAY_2025.PT_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.LOV_PT_SUSDE_MAY_2025_A.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.LOV_PT_SUSDE_MAY_2025_A.TOKEN.decimals(),
  DEBT_TOKEN: INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN,
  DEBT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.decimals(),
  MANAGER: INSTANCES.LOV_PT_SUSDE_MAY_2025_A.MANAGER,
  BORROW_LEND: INSTANCES.LOV_PT_SUSDE_MAY_2025_A.MORPHO_BORROW_LEND,
  DEPOSIT_TO_DEBT_ORACLE: INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DAI,
  SWAPPER_ADDRESS: await INSTANCES.LOV_PT_SUSDE_MAY_2025_A.MORPHO_BORROW_LEND.swapper(),
  PT_MARKET_ADDRESS: ADDRS.EXTERNAL.PENDLE.SUSDE_MAY_2025.MARKET,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.EXTERNAL.PENDLE.SUSDE_MAY_2025.PT_TOKEN,
    ADDRS.LOV_PT_SUSDE_MAY_2025_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tDAI:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tPT sUSDe May2025:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlov-PT-sUSDe-May2025-a:", ethers.utils.formatUnits(prices[2], 30));
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
  if (fromAmount.eq(ethers.utils.parseUnits("10000.0", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("9688.66767070785", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
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
  if (fromAmount.eq(ethers.utils.parseUnits("47945.115905889208263805", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("49431.886975647667197288", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(toAmount),
      data: "0xc81f847a000000000000000000000000d3674dc273236213379207ca3ac6b0f292c47dd5000000000000000000000000b162b764044697cf03617c2efbcb1f42e31e476600000000000000000000000000000000000000000000053bda9e837eb0ce0ab400000000000000000000000000000000000000000000053bda9e837eb0ce0ab40000000000000000000000000000000000000000000024a2fa559876d5a24aec000000000000000000000000000000000000000000000a77b53d06fd619c1568000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000004be93dafc4e500000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000ce00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000a271c251c4b9126647d0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a34970000000000000000000000001e8b6ac39f8a33f46a6eb2d1acd1047b99180ad100000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a44e21fd0e900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000058000000000000000000000000000000000000000000000000000000000000007c000000000000000000000000000000000000000000000000000000000000004c0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000888888888889758f76e7103c6cbf23abbf58f946000000000000000000000000000000000000000000000000000000007fffffff0000000000000000000000000000000000000000000000000000000000000460000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000004094f1a682000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000a271c251c4b9126647d000000000000000000000000f6e72db5454dd049d0788e411b06cfaf168530420000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000004088e563110000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000667701e51b4d1ca244f17c78f7ab8744b4c99f9b0000000000000000000000000000000000000000000000000000000b29c7b9dc000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3000000000000000000000000000000000000000000000000000000000000004088e563110000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000a00000000000000000000000001dd125c32e4b5086c63cc13b3ca02c4a2a61fa9b0000000000000000000000000000000000000000000000000000000b2a64d30b000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a34970000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000020000000000000000000934654cfb195ee00000000000008c73beb9e277e010b540000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000888888888889758f76e7103c6cbf23abbf58f946000000000000000000000000000000000000000000000a271c251c4b9126647d000000000000000000000000000000000000000000000705c9894b52cb3409100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca30000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000a271c251c4b9126647d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002337b22536f75726365223a2250656e646c65222c22416d6f756e74496e555344223a2234373931322e3130393835323539353038222c22416d6f756e744f7574555344223a2234373938312e383332393332323034363536222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223431343534313531363532313835353832313434333430222c2254696d657374616d70223a313734313134303338382c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a22464c44392b6453656373727459794152577676614659442f332f735238644f2f506d7547312b4f584c4e34616c71713031575930584331366d49635343726c6333384c6c6c34786c4571714e392f4971524737713136394e5463376c573866714e2f4a6b4d4e50766a4a4477705a6e4b626f50653835586c532f797049774369796535716675745a3238526f6838384e4134696e646d38476278344d485165694c556a79664d744e595877616f3541593377646b4a4f673131787177396658416d4b54623278444557715232524e62695751412b3151764b3261776b7479377269336f4c38656c6a78577745623432346c6f48575953786d77503279744f7a7445366569516271756f63334e3568302f4c59636a776b326633716b5a5a4e364c5573785a56654d65735973544c46484d51654768682f6b50685946472f6e65714f77794b794a58547435614c6578574379314c3534413d3d227d7d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
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
        // The slippage is high here, since the PT quotes we got are way out of date
        // 0.91 (oracle @ older block time) vs 0.96 (market quote as of now)
        minNewAL: targetAL.mul(10000-1000).div(10000),
        maxNewAL: targetAL.mul(10000+1000).div(10000),
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
    await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_USDE.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_USDE.latestPrice(0, 0)
    )
  );

  console.log(
    await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DAI.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DAI.latestPrice(0, 0)
    )
  );

  console.log(
    await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DISCOUNT_TO_MATURITY.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DISCOUNT_TO_MATURITY.latestPrice(0, 0)
    )
  );

  console.log(
    await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DAI_WITH_DISCOUNT_TO_MATURITY.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.PT_SUSDE_MAY_2025_DAI_WITH_DISCOUNT_TO_MATURITY.latestPrice(0, 0)
    )
  );
}

async function supplyDaiIntoMorpho(owner: SignerWithAddress) {
  const supplyAmount = ethers.utils.parseEther("2000000");
  const signer = await impersonateAndFund(owner, DAI_WHALE);
  await mine(
    TEST_CONTRACTS.DEBT_TOKEN.connect(signer).approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON, 
      supplyAmount
    )
  );

  await mine(
    INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(signer).supply(
      await TEST_CONTRACTS.BORROW_LEND.getMarketParams(),
      supplyAmount,
      0,
      await signer.getAddress(),
      []
    )
  );
}

async function marketALTarget(owner: SignerWithAddress) {
  const morphoToMarketALPrice = IOrigamiOracle__factory.connect(await TEST_CONTRACTS.MANAGER.morphoALToMarketALOracle(), owner);
  const price = await morphoToMarketALPrice.latestPrice(0, 0);
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
  await supplyDaiIntoMorpho(owner);

  await investWithToken(bob, depositAmount);

  const MARKET_AL_TARGET = await marketALTarget(owner);
  console.log("market AL Target:", MARKET_AL_TARGET);
  await rebalanceDown(MARKET_AL_TARGET, 20, depositAmount);

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await TEST_CONTRACTS.VAULT_TOKEN.maxExit(TEST_CONTRACTS.DEPOSIT_TOKEN.address);
  await exitToToken(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}


runAsyncMain(main);
