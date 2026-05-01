import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { OrigamiBundlerPluginMultiAccess__factory, OrigamiBundlerPluginTbsV1__factory } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);
  
  const pluginAddrs = [
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.AAVE_V3_CORE,
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.SPARK,
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.MORPHO,
    ADDRS.BUNDLER.PLUGINS.OHM_STAKING,
    ADDRS.BUNDLER.PLUGINS.TBS.V1,
    ADDRS.BUNDLER.PLUGINS.TBS.V2,
    ADDRS.BUNDLER.PLUGINS.SWAP.KYBER,
    ADDRS.BUNDLER.PLUGINS.SWAP.PENDLE,
    ADDRS.BUNDLER.PLUGINS.ENTRY_POINT,
  ]

  for (const pluginAddr of pluginAddrs) {
    const plugin = OrigamiBundlerPluginMultiAccess__factory.connect(pluginAddr, owner);
    await mine(plugin.setBundlerApproved(ADDRS.BUNDLER.BUNDLER, true));
    await mine(plugin.proposeNewOwner(ADDRS.CORE.MULTISIG));
  }

  const tbsV1Plugin = OrigamiBundlerPluginTbsV1__factory.connect(ADDRS.BUNDLER.PLUGINS.TBS.V1, owner);
  await mine(tbsV1Plugin.trustVault(ADDRS.VAULTS.hOHM.TOKEN.address));

  {
    const batch = createSafeBatch(
      pluginAddrs.map(addr => acceptOwnerAddr(addr))
    );
    const filename = path.join(__dirname, "./01-access.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
