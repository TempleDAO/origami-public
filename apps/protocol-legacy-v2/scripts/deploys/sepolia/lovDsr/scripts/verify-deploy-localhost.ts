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

async function investOvUsdc_usdc(
  account: SignerWithAddress,
  amount: number
) {
  console.log("\ninvestOvUsdc_usdc(%s, %f)", await account.getAddress(), amount);

  const amountBN = ethers.utils.parseUnits(amount.toString(), 6);
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.mint(account.getAddress(), amountBN)
  );

  console.log("\tUSDC balance:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(account.getAddress()),
    6
  ));
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(account).approve(
      ADDRS.OV_USDC.TOKENS.OV_USDC_TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    0,
    0
  );

  console.log("\tovUSDC.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.connect(account).investWithToken(
      quoteData.quoteData
    )
  );

  console.log("\tAccount balance of ovUSDC:", ethers.utils.formatEther(
    await INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitOvUsdc_usdc(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitOvUsdc_usdc(%s, %f)", await account.getAddress(), ethers.utils.formatEther(amountBN));

  console.log("\tBefore:");
  console.log("\t\tAccount balance of ovUSDC:", ethers.utils.formatEther(
    await INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of USDC:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(account.getAddress()),
    6
  ));

  const quoteData = await INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    0,
    0
  );

  console.log("\tovUSDC.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of ovUSDC:", ethers.utils.formatEther(
    await INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of USDC:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(account.getAddress()),
    6
  ));

}

async function investLovDsr_dai(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ninvestLovDsr_dai(%s, %f)", await account.getAddress(), amountBN);

  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.mint(account.getAddress(), amountBN)
  );

  console.log("\tDAI balance:", ethers.utils.formatEther(
    await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.balanceOf(account.getAddress()),
  ));
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.connect(account).approve(
      ADDRS.LOV_DSR.LOV_DSR_TOKEN,
      amountBN
    )
  );

  const quoteData = await INSTANCES.LOV_DSR.LOV_DSR_TOKEN.investQuote(
    amountBN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    10,
    0
  );

  console.log("\tlovDSR.investWithToken. Expect:", ethers.utils.formatEther(quoteData.quoteData.expectedInvestmentAmount));
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of lovDSR:", ethers.utils.formatEther(
    await INSTANCES.LOV_DSR.LOV_DSR_TOKEN.balanceOf(account.getAddress())
  ));
}

async function exitLovDsr_dai(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\nexitLovDsr_dai(%s, %f)", await account.getAddress(), amountBN);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of lovDSR:", ethers.utils.formatEther(
    await INSTANCES.LOV_DSR.LOV_DSR_TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of DAI:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.balanceOf(account.getAddress()),
    18
  ));

  const quoteData = await INSTANCES.LOV_DSR.LOV_DSR_TOKEN.exitQuote(
    amountBN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    0,
    0
  );

  console.log("\tlovDSR.exitToToken. Expect:", ethers.utils.formatUnits(quoteData.quoteData.expectedToTokenAmount, 6));
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_TOKEN.connect(account).exitToToken(
      quoteData.quoteData,
      account.getAddress(),
      {gasLimit:5000000}
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of lovDSR:", ethers.utils.formatEther(
    await INSTANCES.LOV_DSR.LOV_DSR_TOKEN.balanceOf(account.getAddress())
  ));
  console.log("\t\tAccount balance of DAI:", ethers.utils.formatUnits(
    await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.balanceOf(account.getAddress()),
    18
  ));
}

/// @dev Since there are large time jumps between calls, the debt needs
/// to be checkpoint between runs
async function checkpointBorrowers() {
  INSTANCES.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN.checkpointDebtorsInterest(
    [
      ADDRS.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER,
      ADDRS.LOV_DSR.LOV_DSR_MANAGER,
    ]
  );
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
  const [assets, liabilities, ] = await INSTANCES.LOV_DSR.LOV_DSR_MANAGER.assetsAndLiabilities(PriceType.SPOT_PRICE);

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
  const oraclePrice = await INSTANCES.ORACLES.DAI_USD.latestPrice(PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);

  // Within testnet, assume the dexPrice == oraclePrice
  const dexPrice = oraclePrice;

  const reservesAmount = await solveRebalanceDownAmount(targetAL, currentAL, dexPrice, oraclePrice);

  // How much DAI to get that much reserves
  const daiDepositAmount = await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.previewMint(reservesAmount);

  // Assume the swap gets executed at the oracle price
  // and scale down to 6dp (USDC)
  let usdcBorrowAmount = await INSTANCES.ORACLES.DAI_IUSDC.convertAmount(ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN, daiDepositAmount, PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN);
  usdcBorrowAmount = usdcBorrowAmount.div(1e12);

  // Fund the swapper
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.mint(ADDRS.CORE.SWAPPER_1INCH, daiDepositAmount));

  const swapData = ethers.utils.defaultAbiCoder.encode(
    ["tuple(uint256 buyTokenAmount) swapData"], [[daiDepositAmount]] // USDC->DAI using the oracle price
  );
  return {
    usdcBorrowAmount,
    swapData,
    reservesAmount
  };
}

async function rebalanceDown(
  targetAL: BigNumber
) {
  console.log("\nrebalanceDown(%s)", ethers.utils.formatEther(targetAL));

  // Given the time jump, checkpoint the current borrower debt first so we calculate the right rebalance amounts and bounds
  await checkpointBorrowers();
  const alRatioBefore = await INSTANCES.LOV_DSR.LOV_DSR_MANAGER.assetToLiabilityRatio();
  console.log("alRatioBefore:", ethers.utils.formatEther(alRatioBefore));

  const params = await rebalanceDownParams(targetAL, alRatioBefore);
  console.log("params:", params);

  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.rebalanceDown(
      {
        borrowAmount: params.usdcBorrowAmount, 
        swapData: params.swapData, 
        minReservesOut: params.reservesAmount.mul(10_000-20).div(10_000),
        minNewAL: targetAL.mul(10000-100).div(10000),
        maxNewAL: targetAL.mul(10000+100).div(10000),
      },
      {gasLimit:5000000}
    )
  );
  const alRatioAfter = await INSTANCES.LOV_DSR.LOV_DSR_MANAGER.assetToLiabilityRatio();
  console.log("alRatioAfter:", ethers.utils.formatEther(alRatioAfter));

}

async function main() {
  ensureExpectedEnvvars();
  const [owner, alice, bob] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Add owner as valid minter
  {
    const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
    const walletToImpersonate = await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.owner();
    await provider.send('anvil_impersonateAccount', [walletToImpersonate]);
    const signer = provider.getSigner(walletToImpersonate);
    await mine(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).addMinter(owner.getAddress()));
    await mine(INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.connect(signer).addMinter(owner.getAddress()));
  }
  
  // For testing only
  {
    await mine(INSTANCES.OV_USDC.BORROW.CIRCUIT_BREAKER_USDC_BORROW.updateCap(ethers.utils.parseEther("100000000")));
    await mine(INSTANCES.OV_USDC.BORROW.CIRCUIT_BREAKER_OUSDC_EXIT.updateCap(ethers.utils.parseEther("100000000")));
    await mine(INSTANCES.OV_USDC.BORROW.LENDING_CLERK.setBorrowerDebtCeiling(
      ADDRS.LOV_DSR.LOV_DSR_MANAGER,
      ethers.utils.parseEther("200000000")
    ));
  }

  await investOvUsdc_usdc(alice, 5_000_000);

  await exitOvUsdc_usdc(alice, ethers.utils.parseEther("5000"));

  await investLovDsr_dai(bob, ethers.utils.parseEther("100000"));

  await rebalanceDown(ethers.utils.parseEther("1.11"));

  await exitLovDsr_dai(bob, ethers.utils.parseEther("10000"));

  const maxExitAmount = await INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.maxExit(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN);
  await exitOvUsdc_usdc(alice, maxExitAmount);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
