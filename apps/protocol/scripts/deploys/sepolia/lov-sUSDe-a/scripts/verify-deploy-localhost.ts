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

async function investLov_sUSDe(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLov_sUSDe(%s, %f)", await account.getAddress(), amountBN);

  // mint USDe -> mint sUSDe
  {
    let usdeAmount = await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.previewMint(amountBN);
    // Add 1% becuase it increases every block
    usdeAmount = usdeAmount.mul(101).div(100);

    await mine(
      INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.mint(account.getAddress(), usdeAmount)
    );
    await mine(INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.connect(account).approve(
      ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, usdeAmount)
    );

    await mine(
      INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.connect(account).mint(
        amountBN, 
        await account.getAddress(),
        {gasLimit:5000000}
      ),
    );
  }

  console.log("\tsUSDe balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.connect(account).approve(
      ADDRS.LOV_SUSDE.TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_SUSDE.TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
    10,
    0
  );

  console.log("\tlov-sUSDe-5x.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_SUSDE.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lovDSR:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE.TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLov_sUSDe(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLov_sUSDe(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lov-sUSDe-5x:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of sUSDe:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  // Need a little slippage, as the liabilities increase every second which reduces
  // the share price
  const slippageBps = 1;
  const quoteData = await INSTANCES.LOV_SUSDE.TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
    slippageBps, 
    0
  );

  console.log("\tlov-sUSDe-5x.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_SUSDE.TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lov-sUSDe-5x:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE.TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of sUSDe:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  console.log("\t\tmaxExit afterwards:", ethers.utils.formatEther(
    await INSTANCES.LOV_SUSDE.TOKEN.maxExit(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN)
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
  const [assets, liabilities, ] = await INSTANCES.LOV_SUSDE.MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);

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
  const oraclePrice = await INSTANCES.ORACLES.SUSDE_DAI.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);

  // Within testnet, assume the dexPrice == oraclePrice
  const dexPrice = oraclePrice;

  const supplyAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice, oraclePrice);

  const borrowAmount = supplyAmount.mul(dexPrice).div(ONE_ETHER);

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["tuple(uint256 buyTokenAmount) swapData"], [[supplyAmount]] // DAI->sUSDe using the oracle price
  );

  const supplyCollateralSurplusThreshold = 0;

  return {
    supplyAmount,
    borrowAmount,
    swapData,
    supplyCollateralSurplusThreshold
  };
}

async function rebalanceDown(
  targetAL: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  const alRatioBefore = await INSTANCES.LOV_SUSDE.MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_SUSDE.MANAGER.rebalanceDown(
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
  const alRatioAfter = await INSTANCES.LOV_SUSDE.MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await investLov_sUSDe(bob, ethers.utils.parseEther("50000"));

  await rebalanceDown(ethers.utils.parseEther("1.25"));

  const maxExitAmount = await INSTANCES.LOV_SUSDE.TOKEN.maxExit(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN);
  await exitLov_sUSDe(bob, maxExitAmount);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
