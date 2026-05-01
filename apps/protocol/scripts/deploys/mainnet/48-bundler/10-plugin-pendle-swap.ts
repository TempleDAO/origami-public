import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginPendleSwap__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginPendleSwap__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.SWAP.PENDLE",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.ROUTER,
  );
}

runAsyncMain(main);
