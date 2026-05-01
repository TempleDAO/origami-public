import '@nomiclabs/hardhat-ethers';
import { runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { createSafeBatch, SafeTransaction, whitelistRouter, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';
import { OrigamiDexAggregatorSwapper__factory } from '../../../../typechain';

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
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SWBERA_OSBGT_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.SWAPPER,
  ];

  const txsBatch: SafeTransaction[] = [];
  for (const swapperAddr of swappers) {
    if (swapperAddr == undefined) continue;
    
    const swapper = OrigamiDexAggregatorSwapper__factory.connect(swapperAddr, owner);
    const [hasOB, hasKx1, hasKx2] = await Promise.all([
      await swapper.whitelistedRouters(ADDRS.EXTERNAL.OOGABOOGA.ROUTER),
      await swapper.whitelistedRouters(ADDRS.EXTERNAL.KODIAK.KX_SWAP_ROUTERS.KX_ROUTER),
      await swapper.whitelistedRouters(ADDRS.EXTERNAL.KODIAK.KX_SWAP_ROUTERS.LEGACY_ROUTER_02),
    ]);

    if (hasOB && !hasKx1) {
      console.log("Adding KX_ROUTER for:", swapper.address);
      txsBatch.push(whitelistRouter(swapper, ADDRS.EXTERNAL.KODIAK.KX_SWAP_ROUTERS.KX_ROUTER, true));
    }
    if (hasOB && !hasKx2) {
      console.log("Adding LEGACY_ROUTER_02 for:", swapper.address);
      txsBatch.push(whitelistRouter(swapper, ADDRS.EXTERNAL.KODIAK.KX_SWAP_ROUTERS.LEGACY_ROUTER_02, true));
    }
  }
  
  const filename = path.join(__dirname, "./01-add.json");
  writeSafeTransactionsBatch(
    createSafeBatch(txsBatch),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
