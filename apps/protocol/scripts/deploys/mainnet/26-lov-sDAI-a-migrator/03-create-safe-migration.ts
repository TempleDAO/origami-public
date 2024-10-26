import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
} from '../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../contract-addresses';
import path from 'path';
import { createSafeBatch, createSafeTransaction, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import { OrigamiMorphoBorrowAndLend__factory } from '../../../../typechain';
import { Contract } from 'ethers';

let INSTANCES: ContractInstances;

const MIGRATOR_ADDRESS = '0x38898Cc445E0A2Cd73c557A553aEDf9856249911';
const OLD_BORROW_LEND_ADDRESS = '0xDF3D394669Fe433713D170c6DE85f02E260c1c34';

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  const oldBorrowLend = OrigamiMorphoBorrowAndLend__factory.connect(OLD_BORROW_LEND_ADDRESS, owner);
  
  if (network.name === "localhost") return;

  const batch = createSafeBatch(
    1,
    [
      // Grant access to the migrator on the old
      setExplicitAccess(
        oldBorrowLend, 
        MIGRATOR_ADDRESS,
        oldBorrowLend.interface.getSighash(oldBorrowLend.interface.getFunction("repayAndWithdraw")),
        true
      ),

      // Grant access to the migrator on the new
      setExplicitAccess(
        INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND, 
        MIGRATOR_ADDRESS,
        oldBorrowLend.interface.getSighash(oldBorrowLend.interface.getFunction("supplyAndBorrow")),
        true
      ),

      // Set the position owner on the new borrow lend to be the
      // same as on the old
      createSafeTransaction(
        ADDRS.LOV_SDAI_A.MORPHO_BORROW_LEND, 
        "setPositionOwner",
        [{
          argType: "address",
          name: "account",
          value: await oldBorrowLend.positionOwner()
        }]
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
        oldBorrowLend.interface.getSighash(oldBorrowLend.interface.getFunction("repayAndWithdraw")),
        false
      ),

      // Revoke access to the migrator on the new
      setExplicitAccess(
        INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND, 
        MIGRATOR_ADDRESS,
        oldBorrowLend.interface.getSighash(oldBorrowLend.interface.getFunction("supplyAndBorrow")),
        false
      ),

      // Set the borrow lend contract on the lovToken manager
      // to be the new one
      createSafeTransaction(
        ADDRS.LOV_SDAI_A.MANAGER, 
        "setBorrowLend",
        [{
          argType: "address",
          name: "_address",
          value: ADDRS.LOV_SDAI_A.MORPHO_BORROW_LEND
        }]
      ),
    ],
  );
  
  const filename = path.join(__dirname, "./transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

function setExplicitAccess(
  contract: Contract,
  allowedCallerAddress: string,
  fnSelector: string,
  allowed: boolean,
): SafeTransaction {
  return {
    to: contract.address,
    value: "0",
    data: null,
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "allowedCaller",
          type: "address"
        },
        {
          components: [
            {
              internalType: "bytes4",
              name: "fnSelector",
              type: "bytes4"
            },
            {
              internalType: "bool",
              name: "allowed",
              type: "bool"
            }
          ],
          internalType: "struct IOrigamiElevatedAccess.ExplicitAccess[]",
          name: "access",
          type: "tuple[]"
        }
      ],
      name: "setExplicitAccess",
      payable: false
    },
    contractInputsValues: {
      allowedCaller: allowedCallerAddress,
      access: `[["${fnSelector}",${allowed}]]`
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
