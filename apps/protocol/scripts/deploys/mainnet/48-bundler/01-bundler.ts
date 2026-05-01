import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";
import { OrigamiBundler__factory } from "../../../../typechain";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OrigamiBundler__factory(owner);
  await deployAndMine(
    "BUNDLER.BUNDLER",
    factory,
    factory.deploy,
  );
}

runAsyncMain(main);
