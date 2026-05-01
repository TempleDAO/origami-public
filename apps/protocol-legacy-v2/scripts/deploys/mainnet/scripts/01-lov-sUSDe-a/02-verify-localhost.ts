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

const SUSDE_WHALE = "0xb99a2c4C1C4F1fc27150681B740396F6CE1cBcF5";
const DAI_WHALE = "0xBF293D5138a2a1BA407B43672643434C43827179"; // nomad bridge exploiter

async function investLov_sUSDe(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLov_sUSDe(%s, %f)", await account.getAddress(), amountBN);

  // Transfer tokens to the account
  await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.transfer(await account.getAddress(), amountBN);

  console.log("\tsUSDe balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.connect(account).approve(
      ADDRS.LOV_SUSDE_A.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_SUSDE_A.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
    10,
    0
  );
  console.log(quoteData);

  console.log("\tlov-sUSDe.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_SUSDE_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lov-sUSDe:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE_A.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_sUSDe(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_sUSDe(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-sUSDe:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of sUSDe:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.balanceOf(account.getAddress())
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 1;
  const quoteData = await INSTANCES.LOV_SUSDE_A.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-sUSDe.exitToToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedToTokenAmount));
  await mine(
    INSTANCES.LOV_SUSDE_A.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-sUSDe:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE_A.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of sUSDe:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.balanceOf(account.getAddress())
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE_A.TOKEN.maxExit(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN)
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
  const [assets, liabilities, ] = await INSTANCES.LOV_SUSDE_A.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);
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
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x9D39A5DE30e57443BfF2A8307A4256c8797A3497&dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&amount=200000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("200000"))) {
    const toAmount = ethers.utils.parseEther("215565.699937558358987510");
    return {
      toAmount,
      price: toAmount.mul(ONE_ETHER).div(fromAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a34970000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a5a058fc295ed0000000000000000000000000000000000000000000000000016d2eb856c975182897b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002140000000000000000000000000000000000000001f60001c800019a00015000a007e5c0d200000000000000000000000000000000000000000000000000012c0000b05120167478921b907422f8e88b43c4af2b8bea278d3a9d39a5de30e57443bff2a8307a4256c8797a349700443df021240000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014f6f9abcc0adbc4c0e7412083f20f44975d03b1b09e64809b757c47f942beea0004ba0876520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900a0f2fa6b666b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000002da5d70ad92ea30512f60000000000000000456474e4d73e068780a06c4eca276b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a650020d6bdbf786b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a65000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

function debtTokenToSupplyTokenQuote(fromAmount: BigNumber) {
  /*
    curl -X GET \
    "https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0x9D39A5DE30e57443BfF2A8307A4256c8797A3497&amount=211003991277475582629995&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
    -H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
    -H "accept: application/json" \
    -H "content-type: application/json"
  */

  if (fromAmount.eq(ethers.utils.parseEther("211003.991277475582629995"))) {
    const toAmount = ethers.utils.parseEther("195680.314247254943221999");
    return {
      toAmount,
      price: fromAmount.mul(ONE_ETHER).div(toAmount),
      data: "0x07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cae8c9e17ce21fed86b0000000000000000000000000000000000000000000014b7ecf08c91ec0424770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001b000000000000000000000000000000000000000000000000000019200016400a007e5c0d2000000000000000000000000000000000000000000000000000140000070512083f20f44975d03b1b09e64809b757c47f942beea6b175474e89094c44da98b954eedeac495271d0f00046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd095120167478921b907422f8e88b43c4af2b8bea278d3a83f20f44975d03b1b09e64809b757c47f942beea0044ddc1f59d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014b7ecf08c91ec042477000000000000000000000000111111125421ca6dc452d289314280a0f8842a650020d6bdbf789d39a5de30e57443bff2a8307a4256c8797a3497111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000053a717a"
    };
  } else {
    throw Error(`Unknown swap amount: ${ethers.utils.formatEther(fromAmount)}`);
  }
}

enum RouteType {
  VIA_DEX_AGGREGATOR_ONLY = 0,
  VIA_DEX_AGGREGATOR_THEN_DEPOSIT_IN_VAULT
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber,
  slippageBps: number
) {
  const oraclePrice = await INSTANCES.ORACLES.SUSDE_DAI.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  console.log("oraclePrice:", ethers.utils.formatEther(oraclePrice));

  const dexPrice = supplyTokenToDebtTokenQuote(ethers.utils.parseEther("200000"));
  console.log(`1inch sUSDe->DAI price: ${ethers.utils.formatEther(dexPrice.price)}`);

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice.price, oraclePrice, slippageBps);
  console.log("supplyAmount:", ethers.utils.formatEther(supplyAmount));

  // How much DAI do we need to borrow in order to swap to that supplyAmount of sUSDe
  // Use the dex price
  let borrowAmount = supplyAmount.mul(dexPrice.price).div(ONE_ETHER);

  // Add slippage to the amount we actually borrow so after the swap
  // we ensure we have more collateral than supplyAmount
  borrowAmount = inverseSubtractBps(borrowAmount, slippageBps);
  console.log("borrowAmount:", ethers.utils.formatEther(borrowAmount));

  // Get the swap data
  const oneInchQuote = debtTokenToSupplyTokenQuote(borrowAmount);
  console.log(`1inch swap price: ${ethers.utils.formatEther(oneInchQuote.price)}`);

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ['uint8', 'bytes'],
    [RouteType.VIA_DEX_AGGREGATOR_ONLY, oneInchQuote.data]
  );

  const supplyCollateralSurplusThreshold = ethers.utils.parseEther("1000000");

  return {
    supplyAmount,
    borrowAmount,
    swapData,
    supplyCollateralSurplusThreshold
  };
}

async function rebalanceDown(
  targetAL: BigNumber,
  slippageBps: number
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await INSTANCES.LOV_SUSDE_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore, slippageBps);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_SUSDE_A.MANAGER.rebalanceDown(
      {
        supplyAmount: params.supplyAmount,
        borrowAmount: params.borrowAmount, 
        swapData: params.swapData, 
        supplyCollateralSurplusThreshold: params.supplyCollateralSurplusThreshold,
        minNewAL: targetAL.mul(MAX_BPS-100).div(MAX_BPS),
        maxNewAL: targetAL.mul(MAX_BPS+100).div(MAX_BPS),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await INSTANCES.LOV_SUSDE_A.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

async function getSUsde(owner: SignerWithAddress) {
  const signer = await impersonateAndFund(owner, SUSDE_WHALE);
  await mine(INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.connect(signer).transfer(owner.getAddress(), ethers.utils.parseEther("1000000")));
}

async function increaseMaxSupply(investAmount: BigNumber) {
  await INSTANCES.LOV_SUSDE_A.TOKEN.setMaxTotalSupply(investAmount);
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
      await INSTANCES.LOV_SUSDE_A.MORPHO_BORROW_LEND.getMarketParams(),
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

  await getSUsde(owner);

  const investAmount = ethers.utils.parseEther("50000");
  await increaseMaxSupply(investAmount);

  await investLov_sUSDe(bob, investAmount);

  // await supplyDaiIntoMorpho(owner);

  await rebalanceDown(ethers.utils.parseEther("1.25"), 50);

  const maxExitAmount = await INSTANCES.LOV_SUSDE_A.TOKEN.maxExit(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN);
  await exitLov_sUSDe(bob, maxExitAmount);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
