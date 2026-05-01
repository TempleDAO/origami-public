import { BigNumber, ContractReceipt, ethers } from "ethers";
import { AdapterAddedEvent, OpalManager } from "../../typechain/contracts/investments/opal/OpalManager";
import { IERC20Metadata, IOpalAdapter, OpalAdapterAaveV3, OrigamiBundlerPluginMultiAccess__factory } from "../../typechain";
import { mine } from "./helpers";
import { IOpalVault } from "./mainnet/contract-addresses";
import { addOpalAdapter, createSafeBatch, removeOpalAdapter, SafeTransaction, setBundlerApproved, setOpalAdapterDeprecated, writeSafeTransactionsBatch } from "./safe-tx-builder";

function logAdapterAddress(description: string, txReceipt: ContractReceipt) {
  const events = txReceipt.events?.filter(
    (e): e is AdapterAddedEvent => e.event === "AdapterAdded"
  );

  if (!events?.length) {
    console.error("No AdapterAdded events found");
  } else {
    for (const ev of events) {
      const { adapter } = ev.args;
      console.log(`Adapter Instance Address for ${description}: ${adapter}`);
    }
  }
}

export async function addAaveV3Adapter(
  opalManager: OpalManager,
  adapterImpl: OpalAdapterAaveV3,
  collateralTokens: IERC20Metadata[],
  debtToken: IERC20Metadata,
  aavePoolAddressProvider: string,
  initialOwner: string,
  emode: number,
  maxUrOnJoin: BigNumber,
) {
  const [immutableArgs, initArgs, collateralSymbols, debtSymbol] = await Promise.all([
    adapterImpl.encodeImmutableArgs(
      aavePoolAddressProvider,
      collateralTokens.map((ct) => ct.address),
      debtToken.address,
    ),
    adapterImpl.encodeInitArgs(
      initialOwner,
      emode,
      maxUrOnJoin,
    ),
    await Promise.all(collateralTokens.map((ct) => ct.symbol())),
    debtToken.symbol(),
  ]);

  const description = `[${collateralSymbols.join(',')}]/[${debtSymbol}]`;
  const txReceipt = await mine(opalManager.addAdapter(
    adapterImpl.address,
    ethers.utils.formatBytes32String(description),
    immutableArgs,
    initArgs
  ));

  logAdapterAddress(description, txReceipt);
}

export async function addAaveV3AdapterBatch(
  filename: string,
  opalManager: OpalManager,
  adapterImpl: OpalAdapterAaveV3,
  collateralTokens: IERC20Metadata[],
  debtToken: IERC20Metadata,
  aavePoolAddressProvider: string,
  initialOwner: string,
  emode: number,
  maxUrOnJoin: BigNumber,
) {
  const [immutableArgs, initArgs, collateralSymbols, debtSymbol] = await Promise.all([
    adapterImpl.encodeImmutableArgs(
      aavePoolAddressProvider,
      collateralTokens.map((ct) => ct.address),
      debtToken.address,
    ),
    adapterImpl.encodeInitArgs(
      initialOwner,
      emode,
      maxUrOnJoin,
    ),
    await Promise.all(collateralTokens.map((ct) => ct.symbol())),
    debtToken.symbol(),
  ]);

  const description = `[${collateralSymbols.join(',')}]/[${debtSymbol}]`;
  const safeTx = addOpalAdapter(
    opalManager,
    adapterImpl.address,
    ethers.utils.formatBytes32String(description),
    immutableArgs,
    initArgs,
  );

  const batch = createSafeBatch([safeTx]);
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

export async function removeAdapter(
  opalManager: OpalManager,
  adapter: IOpalAdapter,
) {
  await mine(adapter.setDeprecated(true));
  await mine(opalManager.removeAdapter(adapter.address));
}

export function removeAdapterBatch(
  filename: string,
  opalManager: OpalManager,
  adapter: IOpalAdapter,
) {
  const batch = createSafeBatch([
    setOpalAdapterDeprecated(adapter, true),
    removeOpalAdapter(opalManager, adapter),
  ]);
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

export async function addPluginAccess(owner: ethers.Signer, manager: OpalManager, requiredPluginAddrs: string[]) {
  for (const pluginAddr of requiredPluginAddrs) {
    const plugin = OrigamiBundlerPluginMultiAccess__factory.connect(pluginAddr, owner);
    // Reciprocal approvals are required.
    await mine(manager.setPluginApproved(pluginAddr, true));
    await mine(plugin.setBundlerApproved(manager.address, true));
  }
}

export async function addPluginAccessBatch(
  owner: ethers.Signer,
  manager: OpalManager,
  requiredPluginAddrs: string[],
): Promise<SafeTransaction[]> {
  const batchTxs: SafeTransaction[] = [];
  for (const pluginAddr of requiredPluginAddrs) {
    const plugin = OrigamiBundlerPluginMultiAccess__factory.connect(pluginAddr, owner);
    // Reciprocal approvals are required.
    // At this point the deployer has admin access on the manager but not on the plugin, 
    // so that's done as a batch
    await mine(manager.setPluginApproved(pluginAddr, true));

    batchTxs.push(setBundlerApproved(plugin, manager, true));
  }

  return batchTxs;
}
