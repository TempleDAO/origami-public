import { runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { createSafeBatch, setFeeCollector, writeSafeTransactionsBatch } from "../../safe-tx-builder";
import path from "path";
import { SafeTransaction, setExplicitAccess } from "../../safe-tx-builder";

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const batchTxs: SafeTransaction[] = [
    setExplicitAccess(
      INSTANCES.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN,
      ADDRS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.OVERLORD_WALLET,
      ["collectPerformanceFees"],
      true
    ),
    setFeeCollector(INSTANCES.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN, ADDRS.CORE.FEE_COLLECTOR),
    setExplicitAccess(
      INSTANCES.VAULTS.OPAL_WEETH_A_DEPRECATED.TOKEN,
      ADDRS.VAULTS.OPAL_WEETH_A_DEPRECATED.OVERLORD_WALLET,
      ["collectPerformanceFees"],
      true
    ),
    setFeeCollector(INSTANCES.VAULTS.OPAL_WEETH_A_DEPRECATED.TOKEN, ADDRS.CORE.FEE_COLLECTOR),
  ];
  
  const filename = path.join(__dirname, "./01-add-access.json");
  writeSafeTransactionsBatch(createSafeBatch(batchTxs), filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
