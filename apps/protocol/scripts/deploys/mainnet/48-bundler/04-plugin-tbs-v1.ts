import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginTbsV1__factory } from "../../../../typechain";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginTbsV1__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.TBS.V1",
    factory,
    factory.deploy,
    await owner.getAddress(),
  );
}

runAsyncMain(main);
