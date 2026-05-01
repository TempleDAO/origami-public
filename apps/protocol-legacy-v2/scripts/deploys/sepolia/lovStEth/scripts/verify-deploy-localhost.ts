import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, mine } from "../../../helpers";
import { ContractInstances, connectToContracts, getDeployedContracts } from "../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../contract-addresses/types";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
const ONE_ETHER = ethers.utils.parseEther("1");

async function investLovStEth(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLovStEth(%s, %f)", await account.getAddress(), amountBN);

  await mine(
    INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.mint(account.getAddress(), amountBN)
  );

  console.log("\twstETH balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.connect(account).approve(
      ADDRS.LOV_STETH.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_STETH.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.LIDO.WST_ETH_TOKEN,
    10,
    0
  );

  console.log("\tlovStEth.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_STETH.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lovDSR:", ethers.utils.formatEther(
    await INSTANCES.LOV_STETH.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLovStEth(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLovStEth(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lovStEth:", ethers.utils.formatEther(
    await INSTANCES.LOV_STETH.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wstETH:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 1;
  const quoteData = await INSTANCES.LOV_STETH.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.LIDO.WST_ETH_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlovStEth.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_STETH.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lovStEth:", ethers.utils.formatEther(
    await INSTANCES.LOV_STETH.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of wstEth:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.balanceOf(account.getAddress()),
    18
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

async function solveRebalanceDownAmount(
  targetAL: BigNumber, 
  currentAL: BigNumber,
  dexPrice: BigNumber,
  oraclePrice: BigNumber,
) {
  if (targetAL.lte(ONE_ETHER)) throw Error("InvalidRebalanceDownParam()");
  if (targetAL.gte(currentAL)) throw Error("InvalidRebalanceDownParam()");

  // Note there may be a difference between the DEX executed price
  // vs the observed oracle price.
  // To account for this, the amount added to the liabilities needs to be scaled
  /*
    targetAL == (assets+X) / (liabilities+X*dexPrice/oraclePrice);
    targetAL*(liabilities+X*dexPrice/oraclePrice) == (assets+X)
    targetAL*liabilities + targetAL*X*dexPrice/oraclePrice == assets+X
    targetAL*liabilities + targetAL*X*dexPrice/oraclePrice - X == assets
    X*targetAL*dexPrice/oraclePrice - X == assets - targetAL*liabilities
    X * (targetAL*dexPrice/oraclePrice - 1) == assets - targetAL*liabilities
    X == (assets - targetAL*liabilities) / (targetAL*dexPrice/oraclePrice - 1)
  */
  const [assets, liabilities, ] = await INSTANCES.LOV_STETH.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);

  const _netAssets = assets.sub(
    targetAL.mul(liabilities).div(ONE_ETHER)
  );
  const _priceScaledTargetAL = targetAL.mul(dexPrice).div(oraclePrice);
  return _netAssets.mul(ONE_ETHER).div(_priceScaledTargetAL.sub(ONE_ETHER));
}

async function rebalanceDownParams(
  targetAL: BigNumber,
  currentAL: BigNumber
) {
  const oraclePrice = await INSTANCES.ORACLES.WSTETH_ETH.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);

  // Within testnet, assume the dexPrice == oraclePrice
  const dexPrice = oraclePrice;

  const reservesAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice, oraclePrice);

  const flashLoanAmount = reservesAmount.mul(dexPrice).div(ONE_ETHER);

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["tuple(uint256 buyTokenAmount) swapData"], [[reservesAmount]] // wETH->wstETH using the oracle price
  );

  return {
    reservesAmount,
    flashLoanAmount,
    swapData,
  };
}

async function rebalanceDown(
  targetAL: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await INSTANCES.LOV_STETH.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_STETH.MANAGER.rebalanceDown(
      {
        flashLoanAmount: params.flashLoanAmount, 
        swapData: params.swapData, 
        minExpectedReserveToken: params.reservesAmount.mul(10000-100).div(10000),
        minNewAL: targetAL.mul(10000-100).div(10000),
        maxNewAL: targetAL.mul(10000+100).div(10000),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await INSTANCES.LOV_STETH.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await investLovStEth(bob, ethers.utils.parseEther("50"));

  await rebalanceDown(ethers.utils.parseEther("1.125"));

  const maxExitAmount = await INSTANCES.LOV_STETH.TOKEN.maxExit(ADDRS.EXTERNAL.LIDO.WST_ETH_TOKEN);
  await exitLovStEth(bob, maxExitAmount);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
