import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundlerPluginKyberSwap__factory } from "../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBundlerPluginKyberSwap__factory(owner);
  await deployAndMine(
    "BUNDLER.PLUGINS.SWAP.KYBER",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.KYBERSWAP.ROUTER_V2,
    ADDRS.EXTERNAL.KYBERSWAP.SCALING_HELPER,
  );
}

runAsyncMain(main);
