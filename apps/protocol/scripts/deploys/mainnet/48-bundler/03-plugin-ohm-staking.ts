import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginOhmStaking__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginOhmStaking__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.OHM_STAKING",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.OLYMPUS.GOHM_STAKING,
  );
}

runAsyncMain(main);
