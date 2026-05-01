import { mine, runAsyncMain, setExplicitAccess } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiSwapperWithCallback__factory } from "../../../../typechain";
import { network } from "hardhat";
import { acceptOwner, createSafeBatch, createSafeTransaction, writeSafeTransactionsBatch } from "../../safe-tx-builder";
import path from "path";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const swapperAddr = ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.SWAPPER;
  if (!swapperAddr) throw new Error("swapper unset");

  const overlordAddr = ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.OVERLORD_WALLET;
  if (!overlordAddr) throw new Error("overlord wallet unset");

  const swapper = OrigamiSwapperWithCallback__factory.connect(
    swapperAddr,
    owner
  );

  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.OOGABOOGA.ROUTER, true));
  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, true));
  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.KYBERSWAP.ROUTER_V2, true));
  await mine(swapper.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      [
        acceptOwner(swapper),
        createSafeTransaction(
          ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.VAULT,
          "setSwapper",
          [{
            argType: 'address',
            name: '_swapper',
            value: swapper.address,
          }],
        ),
      ],
    );
    
    const filename = path.join(__dirname, "./transactions-batch.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
  
  // allow overlord to use the swapper
  await setExplicitAccess(
    swapper,
    overlordAddr,
    ["execute"],
    true
  );
}

runAsyncMain(main);
