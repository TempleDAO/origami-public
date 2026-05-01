import '@nomiclabs/hardhat-ethers';
import { impersonateAndFund2, runAsyncMain, setExplicitAccess as setExplicitAccessDirect } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { network } from 'hardhat';
import { OrigamiSuperSkyManager } from '../../../../../typechain';
import { createSafeBatch, createSafeTransaction, setExplicitAccess as setExplicitAccessSafe, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import { BigNumber } from 'ethers';
import path from 'path';

function addFarm(
  manager: OrigamiSuperSkyManager,
  newFarm: string,
  referralCode: BigNumber
) {
  return createSafeTransaction(
    manager.address, 
    "addFarm", 
    [
      {
        argType: "address",
        name: "stakingAddress",
        value: newFarm,
      },
      {
        argType: "uint16",
        name: "referralCode",
        value: referralCode.toString(),
      }
    ]
  );
}

function switchFarms(
  manager: OrigamiSuperSkyManager,
  newFarmIndex: BigNumber
) {
  return createSafeTransaction(
    manager.address, 
    "switchFarms", 
    [
      {
        argType: "uint32",
        name: "newFarmIndex",
        value: newFarmIndex.toString(),
      }
    ]
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const manager = INSTANCES.VAULTS.SKYp.MANAGER;

  // For mainnet the access is created directly via Safe
  // as it bundles adding the new vault
  if (network.name === 'localhost') {
    const msig = await impersonateAndFund2(ADDRS.CORE.MULTISIG);
    await setExplicitAccessDirect(
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.connect(msig), 
      ADDRS.VAULTS.SKYp.REWARDS_HARVESTER,
      ["recoverToken"],
      true
    );

    await manager.connect(msig).addFarm(ADDRS.EXTERNAL.SKY.STAKING_FARMS.STAKE_SKY_EARN_SKY, 0);
    await manager.connect(msig).switchFarms(3);

    const farmDetails = await manager.farmDetails([0,1,2,3]);
    console.log("Farm details:");
    for (const details of farmDetails) {
      console.log(details);
    }
  } else {
    const filename = path.join(__dirname, "./update-farm.json");
    writeSafeTransactionsBatch(
      createSafeBatch([
        setExplicitAccessSafe(
          INSTANCES.VAULTS.SKYp.COW_SWAPPER_3,
          ADDRS.VAULTS.SKYp.REWARDS_HARVESTER,
          ["recoverToken"],
          true
        ),
        addFarm(manager, ADDRS.EXTERNAL.SKY.STAKING_FARMS.STAKE_SKY_EARN_SKY, BigNumber.from(0)),
        switchFarms(manager, BigNumber.from(3)),
      ]),
      filename
    );
  }
}

runAsyncMain(main);
