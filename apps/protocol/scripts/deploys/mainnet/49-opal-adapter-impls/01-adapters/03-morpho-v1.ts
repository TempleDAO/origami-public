
import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalAdapterMorpho__factory } from "../../../../../typechain";
import { ethers } from "ethers";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OpalAdapterMorpho__factory(owner);
  await deployAndMine(
    "OPAL.ADAPTER_IMPLEMENTATIONS.MORPHO.V1",
    factory,
    factory.deploy,
    ethers.utils.formatBytes32String("MORPHO.1"),
  );
}

runAsyncMain(main);
