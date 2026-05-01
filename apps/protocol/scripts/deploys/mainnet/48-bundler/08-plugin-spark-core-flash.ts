import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginAaveV3Flash__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginAaveV3Flash__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.FLASHLOAN.SPARK",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.SPARK.POOL_ADDRESS_PROVIDER,
  );
}

runAsyncMain(main);