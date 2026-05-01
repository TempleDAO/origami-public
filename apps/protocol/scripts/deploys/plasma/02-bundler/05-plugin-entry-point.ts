
import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginEntryPoint__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginEntryPoint__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.ENTRY_POINT",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PERMIT2,
    ADDRS.EXTERNAL.WXPL_TOKEN,
  );
}

runAsyncMain(main);
