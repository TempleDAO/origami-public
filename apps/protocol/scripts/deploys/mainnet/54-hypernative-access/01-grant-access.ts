import "@nomiclabs/hardhat-ethers";
import { runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import {
  createSafeBatch,
  setPauserEnabled,
  writeSafeTransactionsBatch,
} from "../../safe-tx-builder";
import path from "path";
import { IOrigamiSuperSkyManager__factory } from "../../../../typechain";

async function main() {
  const { ADDRS, INSTANCES, owner } = await getDeployContext(__dirname);

  const managers = [
    IOrigamiSuperSkyManager__factory.connect(ADDRS.LOV_WSTETH_A.MANAGER, owner),
    IOrigamiSuperSkyManager__factory.connect(ADDRS.LOV_WSTETH_B.MANAGER, owner),
    INSTANCES.VAULTS.SUSDSpS.MANAGER,
    INSTANCES.VAULTS.SKYp.MANAGER,
    INSTANCES.VAULTS.hOHM.MANAGER,
    INSTANCES.VAULTS.OAC_USDS_IMF_MOR.MANAGER,
    INSTANCES.VAULTS.OPAL_WEETH_A_DEPRECATED.MANAGER,
    INSTANCES.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.MANAGER,
  ];

  const filename = path.join(__dirname, "./grant-access.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      ...managers.map((manager) =>
        setPauserEnabled(manager, ADDRS.CORE.HYPERNATIVE.SYSTEM_WALLET, true),
      ),
    ]),
    filename,
  );
}

runAsyncMain(main);
