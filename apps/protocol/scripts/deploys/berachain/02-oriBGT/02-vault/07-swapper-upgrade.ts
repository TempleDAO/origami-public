import "@nomiclabs/hardhat-ethers";
import { OrigamiSwapperWithCallback, OrigamiSwapperWithCallback__factory } from "../../../../../typechain";
import { deployAndMine, mine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";

async function main() {
  const { ADDRS, owner } = await getDeployContext(__dirname);

  const factory = new OrigamiSwapperWithCallback__factory(owner);
  const swapper = await deployAndMine(
    "VAULTS.ORIBGT.SWAPPER",
    factory,
    factory.deploy,
    await owner.getAddress(),
  ) as OrigamiSwapperWithCallback;

  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.OOGABOOGA.ROUTER, true));
  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.MAGPIE.ROUTER, true));
  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.KYBERSWAP.ROUTER_V2, true));
  await mine(swapper.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // And then a multisig to:
  // a/ claim ownership of new swapper
  // b/ update swapper on manager (0x8e008401d7D4788C05a4a746e531B65CF2f5602b)
  // 
  // Note: Run at the same time as a release to automations which:
  // a/ pause compounding temporarily
  // b/ remove the blacklist from osBGT
  // c/ updates the swapper address to this new address
  //
  // After a successful compounding, then check and claim any rewards left in the old swapper.
}

runAsyncMain(main);
