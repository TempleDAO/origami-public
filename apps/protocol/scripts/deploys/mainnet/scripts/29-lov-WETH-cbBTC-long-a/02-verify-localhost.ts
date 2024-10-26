import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, impersonateAndFund, mine } from "../../../helpers";
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, OrigamiAaveV3BorrowAndLend, OrigamiLovToken, OrigamiLovTokenFlashAndBorrowManager, OrigamiOracleBase } from "../../../../../typechain";
import { getSwap } from "../swaps/kyberswap";


let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");
const MAX_BPS = 10_000;

const DEPOSIT_TOKEN_WHALE = "0x741AA7CFB2c7bF2A1E7D4dA2e3Df6a56cA4131F3";
const DEPOSIT_AMOUNT = "30"; // WETH
const AL_TARGET = "1.5"; // 66.67% LTV

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
  SWAPPER_ADDRESS: string;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.WETH_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.WETH_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN.decimals(),
  DEBT_TOKEN: INSTANCES.EXTERNAL.COINBASE.CBBTC_TOKEN,
  DEBT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.COINBASE.CBBTC_TOKEN.decimals(),
  MANAGER: INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER,
  BORROW_LEND: INSTANCES.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND,
  DEPOSIT_TO_DEBT_ORACLE: INSTANCES.ORACLES.WETH_CBBTC,
  SWAPPER_ADDRESS: await INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.swapper(),
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.COINBASE.CBBTC_TOKEN,
    ADDRS.LOV_WETH_CBBTC_LONG_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tWETH:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tcbBTC:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlov-weth-cbbtc-long-a:", ethers.utils.formatUnits(prices[2], 30));
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

async function supplyTokenToDebtTokenQuote(fromAmount: BigNumber) {
  if (fromAmount.eq(ethers.utils.parseUnits("30", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("1.17455863", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(toAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(fromAmount),
      data: ""
    };
  } else {
    const swapData = await getSwap(
      1, // chain id
      {
        tokenIn: TEST_CONTRACTS.DEPOSIT_TOKEN.address,
        tokenOut: TEST_CONTRACTS.DEBT_TOKEN.address,
        amountIn: fromAmount.toString(),
        gasInclude: false,
        source: '', // client id
        slippageTolerance: 1,
        sender: TEST_CONTRACTS.SWAPPER_ADDRESS,
        recipient: TEST_CONTRACTS.SWAPPER_ADDRESS,
      },
    );
    console.log("\n*** SUBSTITUTE THESE INTO supplyTokenToDebtTokenQuote(): ***");
    console.log(`\tfromAmount=${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
    console.log(`\ttoAmount=${ethers.utils.formatUnits(swapData.data.amountOut, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);
    console.log(`\tdata=${swapData.data.data}`);

    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
  }
}

async function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  if (fromAmount.eq(ethers.utils.parseUnits("2.36442168", TEST_CONTRACTS.DEBT_TOKEN_DECIMALS))) {
    const toAmount = ethers.utils.parseUnits("60.260794824463797334", TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
    return {
      toAmount,
      price: scaleBn(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS).mul(ONE_ETHER).div(toAmount),
      data: "0xe21fd0e90000000000000000000000000000000000000000000000000000000000000020000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd67000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000052000000000000000000000000000000000000000000000000000000000000007600000000000000000000000000000000000000000000000000000000000000460000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000d3674dc273236213379207ca3ac6b0f292c47dd500000000000000000000000000000000000000000000000000000000670c6bd20000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000040d90ce491000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000100000000000000000000000000839d6bdedff886404a6d7a788ef241e4e28f4802000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf0000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c59900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000e17d23800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004063407a490000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd670000000000000000000000004585fe77225b41b697c938b018e2ac67ac5a20c00000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000e1d23330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000036ce8f44f70f00000000000000034449599e12dccc56000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000d3674dc273236213379207ca3ac6b0f292c47dd5000000000000000000000000000000000000000000000000000000000e17d2380000000000000000000000000000000000000000000000034433f0ee1bec4a2a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd670000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000e17d238000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022a7b22536f75726365223a22222c22416d6f756e74496e555344223a223134373433342e3033353733313334313334222c22416d6f756e744f7574555344223a223134373837382e31313739373638393933222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223630323630373934383234343633373937333334222c2254696d657374616d70223a313732383836363038322c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a2243736d6e347354536f352f6b784d7036534856662b646641413472385a4f5a4c30647052427576566f3446672f564a42482b6e496a687245656c7876774a4848356547646f576a43484b704b4d5751477971645265314467396b527375694c37695152516f46394158616243716f4d79794b7143676d373141646637506e2b65642b6856416d37346d6d7151336762766656745263364d494348554f41462b55587a6b6e39794f6e376f6e664a49365370485063794570796f6e39554d4c4742627932616d726674374f637942745836356e4c6168304d4d515a784f794e6b6a4736416a6c556a35737a69455447356e344d72427754374c6d3736794b356e69436467614c37526432686f61517050502b2f77486578714b46546c5a425a2b415059425a5361496c716a56546b32784a53586e34784836376b6876347a704b4a4b624e6f75794546533865683831704e7644314d79513d3d227d7d00000000000000000000000000000000000000000000"
    };
  } else {
    const swapData = await getSwap(
      1, // chain id
      {
        tokenIn: TEST_CONTRACTS.DEBT_TOKEN.address,
        tokenOut: TEST_CONTRACTS.DEPOSIT_TOKEN.address,
        amountIn: fromAmount.toString(),
        gasInclude: false,
        source: '', // client id
        slippageTolerance: 1,
        sender: TEST_CONTRACTS.SWAPPER_ADDRESS,
        recipient: TEST_CONTRACTS.SWAPPER_ADDRESS,
      },
    );
    console.log("\n*** SUBSTITUTE THESE INTO debtTokenToSupplyTokenQuote(): ***");
    console.log(`\tfromAmount=${ethers.utils.formatUnits(fromAmount, TEST_CONTRACTS.DEBT_TOKEN_DECIMALS)}`);
    console.log(`\ttoAmount=${ethers.utils.formatUnits(swapData.data.amountOut, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS)}`);
    console.log(`\tdata=${swapData.data.data}`);

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

// 18+8
// 18+8
// weth -> wbtc: 0.0392738100000000
// 
async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  // Same as Chainlink::scalingFactor()
  const scalar = ethers.utils.parseUnits("1", 18+TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS-TEST_CONTRACTS.DEBT_TOKEN_DECIMALS);
  const oraclePrice = await TEST_CONTRACTS.DEPOSIT_TO_DEBT_ORACLE.convertAmount(
    TEST_CONTRACTS.DEPOSIT_TOKEN.address, scalar,
    PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN
  );
  
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = await supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`Kyberswap reserves->debt price: ${ethers.utils.formatEther(dexPrice.price)}`);

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
  console.log(`Kyberswap price: ${ethers.utils.formatEther(oneInchQuote.price)}`);

  const supplyCollateralSurplusThreshold = ethers.utils.parseEther("1000000");

  return {
    supplyAmount,
    borrowAmount,
    swapData: encodeSwapData(ADDRS.EXTERNAL.KYBERSWAP.ROUTER_V2, oneInchQuote.data),
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
  await mine(TEST_CONTRACTS.DEPOSIT_TOKEN.connect(signer).transfer(owner.getAddress(), amount, {gasLimit:5000000}));
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