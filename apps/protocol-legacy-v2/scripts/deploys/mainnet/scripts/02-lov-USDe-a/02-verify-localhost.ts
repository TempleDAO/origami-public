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

const USDE_WHALE = "0x42862F48eAdE25661558AFE0A630b132038553D0";
const DAI_WHALE = "0xBF293D5138a2a1BA407B43672643434C43827179"; // nomad bridge exploiter

async function investLov_USDe(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLov_USDe(%s, %f)", await account.getAddress(), amountBN);

  // mint USDe
  await mine(
    INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tUSDe balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.connect(account).approve(
      ADDRS.LOV_USDE_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_USDE_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
    10,
    0
  );

  console.log("\tlov-USDe.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_USDE_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lov-USDe:", ethers.utils.formatEther(
    await INSTANCES.LOV_USDE_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_USDe(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_USDe(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-USDe:", ethers.utils.formatEther(
    await INSTANCES.LOV_USDE_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of USDe:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 2;
  const quoteData = await INSTANCES.LOV_USDE_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-USDe.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_USDE_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-USDe:", ethers.utils.formatEther(
    await INSTANCES.LOV_USDE_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of USDe:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_USDE_A.TOKEN.maxExit(ADDRS.EXTERNAL.ETHENA.USDE_TOKEN)
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
  const [assets, liabilities, ] = await INSTANCES.LOV_USDE_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&amount=200000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("200000"))) {
    const toAmount = ethers.utils.parseEther("200074.371137389635523522");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b30000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a5a058fc295ed00000000000000000000000000000000000000000000000000152f06d58f00cfffa9e10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002c40000000000000000000000000000000000000002a600027800024a00020000a007e5c0d20000000000000000000000000000000000000000000001dc0001600000b051205dc1bf6f1e983c0b21efb003c105133736fa07434c9edd5852cd905f086c759e8383e09bff1e68b300443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000153dc267a7a2afe4663c5120ce6431d21e3fb1036ce9973a3312368ed96f5ce7853d955acef822db058eb8505911ed77f175b99e00443df0212400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000137546ecce68f672022c412083f20f44975d03b1b09e64809b757c47f942beea0004ba0876520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900a0f2fa6b666b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000002a5e0dab1e019fff53c200000000000000004589a9f8f23322fa80a06c4eca276b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a650020d6bdbf786b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&amount=195800157946900697005719&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("195800.157946900697005719"))) {
    const toAmount = ethers.utils.parseEther("195624.441238815416838261");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002976590b730239cb3e970000000000000000000000000000000000000000000014b6693e25fefed4743a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002b800000000000000000000000000000000000000029a00026c00023e0001f400a007e5c0d20000000000000000000000000000000000000000000001d0000120000070512083f20f44975d03b1b09e64809b757c47f942beea6b175474e89094c44da98b954eedeac495271d0f00046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd095120ce6431d21e3fb1036ce9973a3312368ed96f5ce783f20f44975d03b1b09e64809b757c47f942beea00443df021240000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014c853154764ac73e53151205dc1bf6f1e983c0b21efb003c105133736fa0743853d955acef822db058eb8505911ed77f175b99e00443df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014b6693e25fefed4743a00a0f2fa6b664c9edd5852cd905f086c759e8383e09bff1e68b300000000000000000000000000000000000000000000296cd27c4bfdfda8e8750000000000000000456db30c0d881ead80a06c4eca274c9edd5852cd905f086c759e8383e09bff1e68b3111111125421ca6dc452d289314280a0f8842a650020d6bdbf784c9edd5852cd905f086c759e8383e09bff1e68b3111111125421ca6dc452d289314280a0f8842a650000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number
) {
  const oraclePrice = await INSTANCES.ORACLES.USDE_DAI.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(ethers.utils.parseEther("200000"));
  console.log(`1inch USDe->DAI price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much DAI do we need to borrow in order to swap to that supplyAmount of USDe
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
  slippageBps: number
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await INSTANCES.LOV_USDE_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_USDE_A.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_USDE_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

export const applySlippage = (
  expectedAmount: BigNumber, 
  slippageBps: number
) => {
return expectedAmount.mul(10_000 - slippageBps).div(10_000);
}

async function getUsde(owner: SignerWithAddress) {
  const signer = await impersonateAndFund(owner, USDE_WHALE);
  await mine(INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.connect(signer).transfer(owner.getAddress(), ethers.utils.parseEther("1000000")));
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
      await INSTANCES.LOV_USDE_A.MORPHO_BORROW_LEND.getMarketParams(),
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

  await getUsde(owner);

  await investLov_USDe(bob, ethers.utils.parseEther("50000"));

  await supplyDaiIntoMorpho(owner);

  await rebalanceDown(ethers.utils.parseEther("1.25"), 50);

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await INSTANCES.LOV_USDE_A.TOKEN.maxExit(ADDRS.EXTERNAL.ETHENA.USDE_TOKEN);
  await exitLov_USDe(bob, applySlippage(maxExitAmount, 1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
