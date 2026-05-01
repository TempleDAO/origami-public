
import "@nomiclabs/hardhat-ethers";
import { mine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { acceptOwnerAddr, createSafeBatch, writeSafeTransactionsBatch } from "../../../safe-tx-builder";
import path from "path";

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const adapters = [
    ADDRS.OPAL.ADAPTER_IMPLEMENTATIONS.AAVE_V3.V1,
    ADDRS.OPAL.ADAPTER_IMPLEMENTATIONS.SPOT_ASSETS.V1,
  ];

  for (const adapter of adapters) {
    await mine(INSTANCES.OPAL.ADAPTER_FACTORY.addImplementation(adapter));
  }
  await mine(INSTANCES.OPAL.ADAPTER_FACTORY.proposeNewOwner(ADDRS.CORE.MULTISIG));

  {
    const batch = createSafeBatch([
      acceptOwnerAddr(ADDRS.OPAL.ADAPTER_FACTORY),
    ]);
    const filename = path.join(__dirname, "../01-access.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
