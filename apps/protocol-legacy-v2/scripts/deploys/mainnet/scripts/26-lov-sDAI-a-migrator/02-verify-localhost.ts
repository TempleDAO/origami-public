import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, impersonateAndFund, mine, setExplicitAccess } from "../../../helpers";
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from "../../contract-addresses";
import { ContractAddresses } from "../../contract-addresses/types";
import { OrigamiBorrowLendMigrator, OrigamiBorrowLendMigrator__factory, OrigamiMorphoBorrowAndLend, OrigamiMorphoBorrowAndLend__factory } from "../../../../../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signer } from "ethers";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const MIGRATOR_ADDRESS = '0x38898Cc445E0A2Cd73c557A553aEDf9856249911';
const OLD_BORROW_LEND_ADDRESS = '0xDF3D394669Fe433713D170c6DE85f02E260c1c34';
const DEPOSIT_TOKEN_WHALE = "0xcD40532686B94aBc88b06B9705AAcBc14c8364D6";

async function execute(
  migrator: OrigamiBorrowLendMigrator, 
  oldBorrowLend: OrigamiMorphoBorrowAndLend, 
  newBorrowLend: OrigamiMorphoBorrowAndLend,
  multisig: Signer,
) {
  // Grant access to the migrator on the old
  await setExplicitAccess(oldBorrowLend, MIGRATOR_ADDRESS, ["repayAndWithdraw"], true);

  // Grant access to the migrator on the new
  await setExplicitAccess(newBorrowLend, MIGRATOR_ADDRESS, ["supplyAndBorrow"], true);

  // Set the position owner on the new borrow lend to be the
  // same as on the old
  await mine(newBorrowLend.setPositionOwner(await oldBorrowLend.positionOwner()));

  // Execute the migration
  await mine(migrator.execute({gasLimit: 5000000}));

  // Revoke access to the migrator on the old
  await setExplicitAccess(oldBorrowLend, MIGRATOR_ADDRESS, ["repayAndWithdraw"], false);

  // Set the borrow lend contract on the lovToken manager
  // to be the new one
  await setExplicitAccess(newBorrowLend, MIGRATOR_ADDRESS, ["supplyAndBorrow"], false);

  // Set the borrow lend contract on the lovToken manager
  // to be the new one
  await mine(INSTANCES.LOV_SDAI_A.MANAGER.connect(multisig).setBorrowLend(newBorrowLend.address));
}

async function getDepositTokens(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, DEPOSIT_TOKEN_WHALE);
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function deposit(owner: SignerWithAddress, account: SignerWithAddress, amount: BigNumber) {
  await getDepositTokens(owner, amount);
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.connect(owner).transfer(await account.getAddress(), amount));

  await mine(INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.connect(account).approve(INSTANCES.LOV_SDAI_A.TOKEN.address, amount));
  const quoteData = await INSTANCES.LOV_SDAI_A.TOKEN.connect(account).investQuote(amount, ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN, 100, 0);
  await mine(
    INSTANCES.LOV_SDAI_A.TOKEN.connect(account).investWithToken(
      quoteData.quoteData,
      {gasLimit:5000000}
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await INSTANCES.LOV_SDAI_A.TOKEN.balanceOf(account.getAddress()),
    18,
  ));
}

async function supplyIntoMorpho(owner: SignerWithAddress) {
  const supplyAmount = ethers.utils.parseUnits("1000000", 6);
  const signer = await impersonateAndFund(owner, "0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa");
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON, 
      supplyAmount
    )
  );

  await mine(
    INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(signer).supply(
      await INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND.getMarketParams(),
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
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await supplyIntoMorpho(owner);

  const multisig = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  const oldBorrowLend = OrigamiMorphoBorrowAndLend__factory.connect(OLD_BORROW_LEND_ADDRESS, multisig);
  const newBorrowLend = INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND.connect(multisig);
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

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });