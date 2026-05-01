
import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalAdapterSpotAssets__factory } from "../../../../../typechain";
import { ethers } from "ethers";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OpalAdapterSpotAssets__factory(owner);
  await deployAndMine(
    "OPAL.ADAPTER_IMPLEMENTATIONS.SPOT_ASSETS.V1",
    factory,
    factory.deploy,
    ethers.utils.formatBytes32String("SPOT-ASSETS.1"),
  );
}

runAsyncMain(main);
