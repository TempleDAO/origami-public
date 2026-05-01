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
  // Ensure we use the mainnet Magpie router address from the context
  return whitelistRouter(swapper, ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, true);
}

async function main() {
  // Update the path to fetch context for mainnet deployment step 39
  ({ owner: OWNER, ADDRS } = await getDeployContext(__dirname));

  const swappersToApprove = [
    ADDRS.SWAPPERS.DIRECT_SWAPPER,
    ADDRS.SWAPPERS.SUSDE_SWAPPER,
  ];

  const approvalCommands = swappersToApprove.map(approveMagpieForSwapper);

  const batch = createSafeBatch(approvalCommands);

  const filename = path.join(__dirname, "./approve-magpie-router-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
