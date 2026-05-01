import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginEulerFlash__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginEulerFlash__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.FLASHLOAN.EULER",
    factory,
    factory.deploy,
    await owner.getAddress(),
  );
}

runAsyncMain(main);
