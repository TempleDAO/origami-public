import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import {
  runAsyncMain,
} from '../../../helpers';
import path from 'path';
import { createSafeBatch, createSafeTransaction, setExplicitAccess, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import { OrigamiMorphoBorrowAndLend__factory } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';

const MIGRATOR_ADDRESS = '0x381D5bdBFB9cDF5D04a29EC6d035FdaDBb98b978';
const OLD_BORROW_LEND_ADDRESS = '0x3963D8D2d7AC114573c1184F4036D9A12FbDEFe6';

async function main() {
  const {owner, ADDRS, INSTANCES} = await getDeployContext(__dirname);

  const oldBorrowLend = OrigamiMorphoBorrowAndLend__factory.connect(OLD_BORROW_LEND_ADDRESS, owner);
  
  if (network.name === "localhost") return;

  const batch = createSafeBatch(
    [
      // Grant access to the migrator on the old
      setExplicitAccess(
        oldBorrowLend, 
        MIGRATOR_ADDRESS,
        ["repayAndWithdraw"],
        true
      ),

      // Grant access to the migrator on the new
      setExplicitAccess(
        INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND, 
        MIGRATOR_ADDRESS,
        ["supplyAndBorrow"],
        true
      ),

      // Execute the migration
      createSafeTransaction(
        MIGRATOR_ADDRESS, 
        "execute",
        []
      ),

      // Revoke access to the migrator on the old
      setExplicitAccess(
        oldBorrowLend, 
        MIGRATOR_ADDRESS,
        ["repayAndWithdraw"],
        false
      ),

      // Revoke access to the migrator on the new
      setExplicitAccess(
        INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND, 
        MIGRATOR_ADDRESS,
        ["supplyAndBorrow"],
        false
      ),

      createSafeTransaction(
        ADDRS.LOV_USD0pp_A.TOKEN,
        "setManager",
        [
          {
            argType: "address",
            name: "_manager",
            value: ADDRS.LOV_USD0pp_A.MANAGER
          }
        ]
      ),

    ],
  );
  
  const filename = path.join(__dirname, "./transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
