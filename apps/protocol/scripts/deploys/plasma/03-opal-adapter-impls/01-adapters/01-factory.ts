
import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalAdapterFactory__factory } from "../../../../../typechain";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OpalAdapterFactory__factory(owner);
  await deployAndMine(
    "OPAL.ADAPTER_FACTORY",
    factory,
    factory.deploy,
    await owner.getAddress(),
  );
}

runAsyncMain(main);
