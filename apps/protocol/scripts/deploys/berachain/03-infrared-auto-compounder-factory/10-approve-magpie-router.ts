import "@nomiclabs/hardhat-ethers";
import { runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { ContractAddresses } from "../contract-addresses/types";
import {
  createSafeBatch,
  writeSafeTransactionsBatch,
  SafeTransaction,
  whitelistRouter,
} from "../../safe-tx-builder";
import path from "path";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { OrigamiSwapperWithLiquidityManagement__factory } from "../../../../typechain";

let OWNER: SignerWithAddress;
let ADDRS: ContractAddresses;

function approveMagpieForSwapper(
  swapperAddress: `0x${string}`
): SafeTransaction {
  const swapper = OrigamiSwapperWithLiquidityManagement__factory.connect(
    swapperAddress,
    OWNER
  );
  return whitelistRouter(swapper, ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, true);
}

async function main() {
  ({ owner: OWNER, ADDRS } = await getDeployContext(__dirname));

  const swappersToApprove = [
    ADDRS.VAULTS.ORIBGT.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_OSBGT_A.SWAPPER,
  ];

  const approvalCommands = swappersToApprove.map(approveMagpieForSwapper);

  const batch = createSafeBatch(approvalCommands);

  const filename = path.join(__dirname, "./approve-magpie-router-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
