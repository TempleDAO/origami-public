import { runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { createSafeBatch, setFeeCollector, writeSafeTransactionsBatch } from "../../safe-tx-builder";
import path from "path";
import { SafeTransaction, setExplicitAccess } from "../../safe-tx-builder";

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const batchTxs: SafeTransaction[] = [
    setExplicitAccess(
      INSTANCES.VAULTS.OPAL_PT_SUSDE_PLASMA_A.TOKEN,
      ADDRS.VAULTS.OPAL_PT_SUSDE_PLASMA_A.OVERLORD_WALLET,
      ["collectPerformanceFees"],
      true
    ),
    setFeeCollector(INSTANCES.VAULTS.OPAL_PT_SUSDE_PLASMA_A.TOKEN, ADDRS.CORE.FEE_COLLECTOR),
    setExplicitAccess(
      INSTANCES.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.TOKEN,
      ADDRS.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.OVERLORD_WALLET,
      ["collectPerformanceFees"],
      true
    ),
    setFeeCollector(INSTANCES.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.TOKEN, ADDRS.CORE.FEE_COLLECTOR),
  ];
  
  const filename = path.join(__dirname, "./01-add-access.json");
  writeSafeTransactionsBatch(createSafeBatch(batchTxs), filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
