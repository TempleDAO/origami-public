
import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalAdapterAaveV3__factory } from "../../../../../typechain";
import { ethers } from "ethers";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OpalAdapterAaveV3__factory(owner);
  await deployAndMine(
    "OPAL.ADAPTER_IMPLEMENTATIONS.AAVE_V3.V1",
    factory,
    factory.deploy,
    ethers.utils.formatBytes32String("AAVE-V3.1"),
  );
}

runAsyncMain(main);
