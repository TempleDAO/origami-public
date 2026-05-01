import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginMorphoFlash__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginMorphoFlash__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.FLASHLOAN.MORPHO",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
  );
}

runAsyncMain(main);