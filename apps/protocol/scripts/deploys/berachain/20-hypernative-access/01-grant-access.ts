import "@nomiclabs/hardhat-ethers";
import { runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import {
  createSafeBatch,
  setExplicitAccess,
  setPauserEnabled,
  writeSafeTransactionsBatch,
} from "../../safe-tx-builder";
import path from "path";
import { OrigamiInfraredVaultManager__factory } from "../../../../typechain";

async function main() {
  const { ADDRS, INSTANCES, owner } = await getDeployContext(__dirname);

  const managers = [
    OrigamiInfraredVaultManager__factory.connect(ADDRS.LOV_ORIBGT_A.MANAGER, owner),
    INSTANCES.VAULTS.ORIBGT.MANAGER,
  ];

  const filename = path.join(__dirname, "./grant-access.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      ...managers.map((manager) =>
        setPauserEnabled(manager, ADDRS.CORE.HYPERNATIVE.SYSTEM_WALLET, true),
      ),
      setExplicitAccess(
        INSTANCES.VAULTS.INFRARED_AUTO_STAKING_HOHM_HONEY_A,
        ADDRS.CORE.HYPERNATIVE.SYSTEM_WALLET,
        ["setPaused"],
        true,
      ),
    ]),
    filename,
  );
}

runAsyncMain(main);
