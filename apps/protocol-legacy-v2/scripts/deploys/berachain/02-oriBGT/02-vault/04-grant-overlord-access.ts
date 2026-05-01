import "@nomiclabs/hardhat-ethers";
import { runAsyncMain, setExplicitAccess } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { ContractInstances } from "../../contract-addresses";

async function setAccess(
  INSTANCES: ContractInstances,
  overlordAddr: string,
  grantAccess: boolean
) {
  // allow overlord to recover rewards tokens if the rewards array changes
  await setExplicitAccess(
    INSTANCES.VAULTS.ORIBGT.MANAGER,
    overlordAddr,
    ["recoverToken"],
    grantAccess
  );

  // allow overlord to use the swapper
  await setExplicitAccess(
    INSTANCES.VAULTS.ORIBGT.SWAPPER,
    overlordAddr,
    ["execute"],
    grantAccess
  )
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.VAULTS.ORIBGT.OVERLORD_WALLET, true);
}

runAsyncMain(main);
