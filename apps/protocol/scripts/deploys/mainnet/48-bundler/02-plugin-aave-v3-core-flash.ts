import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginAaveV3Flash__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginAaveV3Flash__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.FLASHLOAN.AAVE_V3_CORE",
    factory,
    factory.deploy,
    await owner.getAddress(),
    // @todo This has a 5bps flashloan fee
    // In reality we would switch to morpho/spark which is free
    // but using it to test the impact / correct maths.
    ADDRS.EXTERNAL.AAVE.V3_MAINNET_POOL_ADDRESS_PROVIDER,
  );
}

runAsyncMain(main);
