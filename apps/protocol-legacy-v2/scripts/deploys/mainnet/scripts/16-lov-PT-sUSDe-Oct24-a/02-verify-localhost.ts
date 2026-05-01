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

const PT_WHALE = "0xB587606Ca8ce0B7aa9D978b9c2308610644c6526";
const DAI_WHALE = "0xBF293D5138a2a1BA407B43672643434C43827179";

async function investLov(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvest lovToken(%s, %f)", await account.getAddress(), amountBN);

  await mine(
    INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tPT balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.connect(account).approve(
      ADDRS.LOV_PT_SUSDE_OCT24_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
    10,
    0
  );

  console.log("\tlovToken::investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAccount balance of lovToken:", ethers.utils.formatEther(
    await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexit lovToken(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lovToken:", ethers.utils.formatEther(
    await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of PT:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
    slippageBps,
    0
  );

  console.log("\tlovToken::exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount));
  await mine(
    INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      { gasLimit: 5000000 }
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lovToken:", ethers.utils.formatEther(
    await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of PT:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.maxExit(ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN)
  ));
}

function inverseSubtractBps(remainderAmount: BigNumber, basisPoints: number) {
  return remainderAmount.mul(MAX_BPS).div(MAX_BPS - basisPoints);
}

async function solveRebalanceDownAmount(
  targetMorphoLTV: BigNumber,
  marketPtToDaiPrice: BigNumber,
  morphoPtToDaiPrice: BigNumber,
) {
  /*
    Solving for the new PT we need to add:
      targetRatio = (currentDebt + (newAssets * morphoPrice)) / ((currentAssets + newAssets) * marketPrice)
      targetRatio * marketPrice * (currentAssets + newAssets) = currentDebt + (newAssets * morphoPrice)
      targetRatio * marketPrice * currentAssets + targetRatio * newAssets = currentDebt + newAssets * morphoPrice
      targetRatio * marketPrice * currentAssets - currentDebt = newAssets * morphoPrice - targetRatio * newAssets
      targetRatio * marketPrice * currentAssets - currentDebt = newAssets * (morphoPrice - targetRatio)
      newAssets[PT] = 
          (targetRatio[] * marketPrice[DAI/PT] * currentAssets[PT] - currentDebt[DAI])
          / (morphoPrice[DAI/PT] - targetRatio[])
  */
  const currentDebt = await INSTANCES.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND.debtBalance();
  const currentAssets = await INSTANCES.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND.suppliedBalance();

  const marketDaiToPtPrice = ONE_ETHER.mul(ONE_ETHER).div(marketPtToDaiPrice);
  const morphoDaiToPtPrice = ONE_ETHER.mul(ONE_ETHER).div(morphoPtToDaiPrice);

  const numerator = targetMorphoLTV
    .mul(marketDaiToPtPrice).div(ONE_ETHER)
    .mul(currentAssets).div(ONE_ETHER)
    .sub(currentDebt);
  const denominator = ONE_ETHER.sub(targetMorphoLTV);

  const newAssets = numerator.mul(ONE_ETHER).div(denominator); 
  return newAssets;
}

function supplyTokenToDebtTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X 'GET' \
      'https://api-v2.pendle.finance/sdk/api/v1/swapExactPtForToken?chainId=1&receiverAddr=0x2550d6424b46f78F4E31F1CCf88Da26dda7826C6&marketAddr=0xd1D7D99764f8a52Aff007b7831cc02748b2013b5&amountPtIn=35000000000000000000000&tokenOutAddr=0x6B175474E89094C44Da98b954EedeAC495271d0F&slippage=0.99' \
      -H 'accept: application/json' | jq
  */

  if (fromAmount.eq(ethers.utils.parseEther("35000"))) {
    const toAmount = ethers.utils.parseEther("33856.206104000000000000");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x"
    };
  } else {
    throw Error(`Unknown supplyTokenToDebtTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X 'GET' \
      'https://api-v2.pendle.finance/sdk/api/v1/swapExactTokenForPt?chainId=1&receiverAddr=0x2550d6424b46f78F4E31F1CCf88Da26dda7826C6&marketAddr=0xd1D7D99764f8a52Aff007b7831cc02748b2013b5&tokenInAddr=0x6B175474E89094C44Da98b954EedeAC495271d0F&amountTokenIn=40004000400040003965986&slippage=0.99' \
      -H 'accept: application/json' | jq
  */

  if (fromAmount.eq(ethers.utils.parseEther("40004.000400040003965986"))) {
    const toAmount = ethers.utils.parseEther("41287.757361335891327442");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0xc81f847a000000000000000000000000335796f7A0F72368D1588839e38f163d90C92C80000000000000000000000000d1d7d99764f8a52aff007b7831cc02748b2013b500000000000000000000000000000000000000000000001661d3cdaea57396fa00000000000000000000000000000000000000000000045f1b5e2c1c50937ce90000000000000000000000000000000000000000000034055f470cea8ba7e8070000000000000000000000000000000000000000000008be36bc5838a126f9d2000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000005afefce90e5600000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000be00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000008789f076d8ef8e514220000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a34970000000000000000000000001e8b6ac39f8a33f46a6eb2d1acd1047b99180ad100000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000944e21fd0e90000000000000000000000000000000000000000000000000000000000000020000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd67000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000048000000000000000000000000000000000000000000000000000000000000006c000000000000000000000000000000000000000000000000000000000000003c0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000888888888889758f76e7103c6cbf23abbf58f946000000000000000000000000000000000000000000000000000000007fffffff0000000000000000000000000000000000000000000000000000000000000360000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000004095d02f7d0000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000008789f076d8ef8e51422000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd670000000000000000000000000000000000000000000000000000000000000040d90ce491000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000100000000000000000000000000167478921b907422f8e88b43c4af2b8bea278d3a00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000007b99b620660db94c36000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000082b8993c61736e00000000000007caa5403195fb9a4fcc0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000888888888889758f76e7103c6cbf23abbf58f9460000000000000000000000000000000000000000000008789f076d8ef8e5142200000000000000000000000000000000000000000000063bb7668e1196150ca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000f081470f5c6fbccf48cc4e5b82dd926409dcdd6700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000008789f076d8ef8e5142200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002327b22536f75726365223a2250656e646c65222c22416d6f756e74496e555344223a2234303036352e3238373138353630343439222c22416d6f756e744f7574555344223a2233393636352e3335333532363939343433222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223336373934373135323534393131383534353936303434222c2254696d657374616d70223a313732313131393035362c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a224b4d2b6c326e7a513953764f4565556b76397637437632647a5244746d7166424b6c6b36714e2f3348454b384343616b52704b665563715370316f7a59526d74414c426f77426b6b6632444c6e7646734c54766a776b577330474635706548646d595a34425a355a7479525169506f77312f6d724a32522f544845782b3062625a4d5956426e48736649535a4e594f586e51414d4d5641384c46765444786c57633945394c462f46595168726d6f4e53707456664c666232796d6355717551694e756866566f457369356c305633573559356e6f4e58374c63455762357946362b2b354a4f3038735a4757364a73336e4e667a4669706b6e2b64487a2b706c6d356c7a2f2f5444557534505564726b746a527843627a4e306a727133574e4e7a436d4b344a704b3065796e2b315a545a56547838786c37414a434b7878507356376c3279344843496962644f336f4b6c74554b6878673d3d227d7d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    };
  } else {
    throw Error(`Unknown debtTokenToSupplyTokenQuote amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function dummySwapperEncoder(buyTokenAmount: BigNumber) {
  return ethers.utils.defaultAbiCoder.encode(
    ["tuple(uint256 buyTokenAmount) swapData"], [[buyTokenAmount]]
  );
}

async function rebalanceDownParams(
  targetMorphoLTV: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  console.log("SWAPPER ADDRESS:", ADDRS.SWAPPERS.DIRECT_SWAPPER);
  
  // This gives the PT -> USDe price.
  const oraclePrice = await INSTANCES.ORACLES.PT_SUSDE_OCT24_DAI.latestPrice(0, 0);
  console.log(`Oracle PT->USDe price: ${ethers.utils.formatEther(oraclePrice)}`);

  const marketPrice = supplyTokenToDebtTokenQuote(dexPriceQuoteAmount);
  console.log(`Pendle PT->DAI price: ${ethers.utils.formatEther(marketPrice.price)}`);

  // For this pool, maker are assuming 1 PT === 1 DAI
  const morphoPrice = ONE_ETHER;

  const supplyAmount = await solveRebalanceDownAmount(targetMorphoLTV, marketPrice.price, morphoPrice);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much DAI do we need to borrow in order to swap to that supplyAmount of PT
  // Use the dex price
  const fullBorrowAmount = supplyAmount.mul(marketPrice.price).div(ONE_ETHER);
  console.log("full borrowAmount:", ethers.utils.formatEther(fullBorrowAmount));

  // Add slippage to the amount we actually borrow so after the swap
  // we ensure we have more collateral than supplyAmount
  const borrowAmount = inverseSubtractBps(fullBorrowAmount, slippageBps);
  console.log("borrowAmount:", ethers.utils.formatEther(borrowAmount));

  // Get the swap data
  const pendleQuote = debtTokenToSupplyTokenQuote(borrowAmount);
  console.log(`Pendle swap DAI->PT price: ${ethers.utils.formatEther(pendleQuote.price)}`);

  const supplyCollateralSurplusThreshold = ethers.utils.parseEther("1000000");

  return {
    supplyAmount,
    borrowAmount,
    swapData: pendleQuote.data,
    swapToAmount: pendleQuote.toAmount,
    swapPrice: pendleQuote.price,
    supplyCollateralSurplusThreshold
  };
}

async function rebalanceDown(
  targetMorphoLTV: BigNumber,
  slippageBps: number,
  dexPriceQuoteAmount: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetMorphoLTV));

  const [existingAssets, existingLiabilities, alRatioBefore] = await INSTANCES.LOV_PT_SUSDE_OCT24_A.MANAGER.assetsAndLiabilities(0);
  console.log(`Existing (market) A/L: existingAssets=${existingAssets} existingLiabilities=${existingLiabilities} alRatioBefore=${alRatioBefore}`);

  const params = await rebalanceDownParams(targetMorphoLTV, slippageBps, dexPriceQuoteAmount);
  console.log("params:", params);

  const newAssets = existingAssets.add(params.supplyAmount);
  const newLiabilities = existingLiabilities.add(params.borrowAmount.mul(ONE_ETHER).div(params.swapPrice));
  const targetAL = newAssets.mul(ONE_ETHER).div(newLiabilities);
  console.log(`Expected new (market) A/L: newAssets=${newAssets} newLiabilities=${newLiabilities} targetAL=${targetAL}`);
  console.log(`minNewAL=${ethers.utils.formatEther(targetAL.mul(10000-100).div(10000))}`);
  console.log(`maxNewAL=${ethers.utils.formatEther(targetAL.mul(10000+100).div(10000))}`);

  await mine(
    INSTANCES.LOV_PT_SUSDE_OCT24_A.MANAGER.rebalanceDown(
      {
        supplyAmount: params.supplyAmount, //.mul(10000-5).div(10000),
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

  const [afterAssets, afterLiabilities, alRatioAfter] = await INSTANCES.LOV_PT_SUSDE_OCT24_A.MANAGER.assetsAndLiabilities(0);
  console.log(`New (market) A/L: afterAssets=${afterAssets} afterLiabilities=${afterLiabilities} alRatioAfter=${alRatioAfter}`);
}

export const applySlippage = (
  expectedAmount: BigNumber,
  slippageBps: number
) => {
  return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getPt(owner: SignerWithAddress) {
  const signer = await impersonateAndFund(owner, PT_WHALE);
  await mine(INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.connect(signer).transfer(owner.getAddress(), ethers.utils.parseEther("20000000")));
}

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.LOV_PT_SUSDE_OCT24_A.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tPT-sUSDe-Oct24:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tDAI:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tlovToken:", ethers.utils.formatUnits(prices[2], 30));
}

async function supplyDaiIntoMorpho(owner: SignerWithAddress) {
  const supplyAmount = ethers.utils.parseEther("2000000");
  const signer = await impersonateAndFund(owner, DAI_WHALE);
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.connect(signer).approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON, 
      supplyAmount
    )
  );

  await mine(
    INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(signer).supply(
      await INSTANCES.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND.getMarketParams(),
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

  await dumpPrices();

  await getPt(owner);
  await supplyDaiIntoMorpho(owner);

  await investLov(bob, ethers.utils.parseEther("10000"));

  await rebalanceDown(
    ethers.utils.parseEther("0.8"),
    1,
    ethers.utils.parseEther("35000")
  );

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN.maxExit(ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN);
  await exitLov(bob, applySlippage(maxExitAmount, 1));

  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
