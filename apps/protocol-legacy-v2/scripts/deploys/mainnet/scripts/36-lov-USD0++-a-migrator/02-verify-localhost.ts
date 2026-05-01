import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { impersonateAndFund, mine, runAsyncMain, setExplicitAccess } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { ContractAddresses } from "../../contract-addresses/types";
import { OrigamiBorrowLendMigrator, OrigamiBorrowLendMigrator__factory, OrigamiMorphoBorrowAndLend, OrigamiMorphoBorrowAndLend__factory } from "../../../../../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signer } from "ethers";
import { getDeployContext } from "../../deploy-context";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const MIGRATOR_ADDRESS = '0xf975A646FCa589Be9fc4E0C28ea426A75645fB1f';
const OLD_BORROW_LEND_ADDRESS = '0x3963D8D2d7AC114573c1184F4036D9A12FbDEFe6';
const DEPOSIT_TOKEN_WHALE = "0x9295bd6ce26E5896dC21Feda84EF65d2472070dC";

async function execute(
  migrator: OrigamiBorrowLendMigrator, 
  oldBorrowLend: OrigamiMorphoBorrowAndLend, 
  newBorrowLend: OrigamiMorphoBorrowAndLend,
  multisig: Signer,
) {
  await mine(INSTANCES.LOV_USD0pp_A.MANAGER.connect(multisig).acceptOwner());
  await mine(INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.connect(multisig).acceptOwner());

  // Grant access to the migrator on the old
  await setExplicitAccess(oldBorrowLend, MIGRATOR_ADDRESS, ["repayAndWithdraw"], true);

  // Grant access to the migrator on the new
  await setExplicitAccess(newBorrowLend, MIGRATOR_ADDRESS, ["supplyAndBorrow"], true);

  // Execute the migration
  await mine(migrator.execute({gasLimit: 5000000}));

  // Revoke access to the migrator on the old
  await setExplicitAccess(oldBorrowLend, MIGRATOR_ADDRESS, ["repayAndWithdraw"], false);

  // Set the borrow lend contract on the lovToken manager
  // to be the new one
  await setExplicitAccess(newBorrowLend, MIGRATOR_ADDRESS, ["supplyAndBorrow"], false);

  // Set the manager on the token to be the new one
  await mine(INSTANCES.LOV_USD0pp_A.TOKEN.connect(multisig).setManager(ADDRS.LOV_USD0pp_A.MANAGER));
}

async function getDepositTokens(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, DEPOSIT_TOKEN_WHALE);
  await mine(INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function deposit(owner: SignerWithAddress, account: SignerWithAddress, amount: BigNumber) {
  await getDepositTokens(owner, amount);
  await mine(INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.connect(owner).transfer(await account.getAddress(), amount));

  await mine(INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.connect(account).approve(INSTANCES.LOV_USD0pp_A.TOKEN.address, amount));
  const quoteData = await INSTANCES.LOV_USD0pp_A.TOKEN.connect(account).investQuote(amount, ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN, 100, 0);
  await mine(
    INSTANCES.LOV_USD0pp_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await INSTANCES.LOV_USD0pp_A.TOKEN.balanceOf(account.getAddress()),
    18,
  ));
}

async function supplyIntoMorpho(owner: SignerWithAddress) {
  const supplyAmount = ethers.utils.parseUnits("20000000", 6);
  const signer = await impersonateAndFund(owner, "0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341");
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON, 
      supplyAmount
    )
  );

  await mine(
    INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(signer).supply(
      await INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.getMarketParams(),
      supplyAmount,
      0,
      await signer.getAddress(),
      []
    )
  );
}

async function dumpOracles() {
  console.log(
    await INSTANCES.ORACLES.USD0pp_USDC_FLOOR_PRICE.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.USD0pp_USDC_FLOOR_PRICE.latestPrice(0, 0)
    )
  );

  console.log(
    await INSTANCES.ORACLES.USD0pp_USDC_MARKET_PRICE.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.USD0pp_USDC_MARKET_PRICE.latestPrice(0, 0)
    )
  );

  console.log(
    await INSTANCES.ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION.description(),
    ethers.utils.formatEther(
      await INSTANCES.ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION.latestPrice(0, 0)
    )
  );
}

async function main() {
  ({ ADDRS, INSTANCES } = await getDeployContext(__dirname));
  const [owner, bob] = await ethers.getSigners();
  
  await dumpOracles();

  await supplyIntoMorpho(owner);

  const multisig = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  const oldBorrowLend = OrigamiMorphoBorrowAndLend__factory.connect(OLD_BORROW_LEND_ADDRESS, multisig);
  const newBorrowLend = INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.connect(multisig);
  const migrator = OrigamiBorrowLendMigrator__factory.connect(MIGRATOR_ADDRESS, multisig);

  const oldSuppliedBefore = await oldBorrowLend.suppliedBalance();
  const oldDebtBefore = await oldBorrowLend.debtBalance();
  const newSuppliedBefore = await newBorrowLend.suppliedBalance();
  const newDebtBefore = await newBorrowLend.debtBalance();
  console.log("oldSuppliedBefore:", oldSuppliedBefore);
  console.log("oldDebtBefore:", oldDebtBefore);
  console.log("newSuppliedBefore:", newSuppliedBefore);
  console.log("newDebtBefore:", newDebtBefore);

  await execute(migrator, oldBorrowLend, newBorrowLend, multisig);

  const oldSuppliedAfter = await oldBorrowLend.suppliedBalance();
  const oldDebtAfter = await oldBorrowLend.debtBalance();
  const newSuppliedAfter = await newBorrowLend.suppliedBalance();
  const newDebtAfter = await newBorrowLend.debtBalance();
  console.log("oldSuppliedAfter:", oldSuppliedAfter);
  console.log("oldDebtAfter:", oldDebtAfter);
  console.log("newSuppliedAfter:", newSuppliedAfter);
  console.log("newDebtAfter:", newDebtAfter);

  // Unpause deposits - will be done manually by multisig
  await mine(INSTANCES.LOV_USD0pp_A.MANAGER.connect(multisig).setPaused({
    investmentsPaused: false, 
    exitsPaused: false
  }));

  await deposit(owner, bob, ethers.utils.parseEther("100"));
  const oldSuppliedAfter2 = await oldBorrowLend.suppliedBalance();
  const oldDebtAfter2 = await oldBorrowLend.debtBalance();
  const newSuppliedAfter2 = await newBorrowLend.suppliedBalance();
  const newDebtAfter2 = await newBorrowLend.debtBalance();
  console.log("oldSuppliedAfter2:", oldSuppliedAfter2);
  console.log("oldDebtAfter2:", oldDebtAfter2);
  console.log("newSuppliedAfter2:", newSuppliedAfter2);
  console.log("newDebtAfter2:", newDebtAfter2);
}

runAsyncMain(main);
