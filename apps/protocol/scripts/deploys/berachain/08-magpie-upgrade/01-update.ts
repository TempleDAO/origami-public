import '@nomiclabs/hardhat-ethers';
import { runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { OrigamiSwapperWithCallback__factory } from '../../../../typechain';
import { createSafeBatch, whitelistRouter, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
    const { owner, ADDRS } = await getDeployContext(__dirname);

    const swappers = [
      ADDRS.SWAPPERS.DIRECT_SWAPPER,
      ADDRS.VAULTS.ORIBGT.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_OSBGT_A.SWAPPER,
    ]

    const v2BatchItems = [];
    const v3BatchItems = [];
    for (const swapper of swappers) {
      const instance = OrigamiSwapperWithCallback__factory.connect(swapper, owner);
      const hasMagpieV2 = await instance.whitelistedRouters(ADDRS.EXTERNAL.MAGPIE.ROUTER_V2);
      console.log(swapper, hasMagpieV2);
      if (hasMagpieV2) {
        v2BatchItems.push(whitelistRouter(instance, ADDRS.EXTERNAL.MAGPIE.ROUTER_V2, false));
        v3BatchItems.push(whitelistRouter(instance, ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, true));
      }
    }

    const filenameV2 = path.join(__dirname, "./whitelist-v2-batch.json");
    writeSafeTransactionsBatch(createSafeBatch(v2BatchItems), filenameV2);
    console.log(`Wrote Safe tx's batch to: ${filenameV2}`);

    const filenameV3 = path.join(__dirname, "./whitelist-v3-batch.json");
    writeSafeTransactionsBatch(createSafeBatch(v3BatchItems), filenameV3);
    console.log(`Wrote Safe tx's batch to: ${filenameV3}`);
}

runAsyncMain(main);
