
import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalAdapterEuler__factory } from "../../../../../typechain";
import { ethers } from "ethers";

async function main() {
  const { ADDRS, owner } = await getDeployContext(__dirname);

  const factory = new OpalAdapterEuler__factory(owner);
  await deployAndMine(
    "OPAL.ADAPTER_IMPLEMENTATIONS.EULER_V2.V1",
    factory,
    factory.deploy,
    ethers.utils.formatBytes32String("EULER-V2.1"),
    ADDRS.EXTERNAL.EULER_V2.EVC,
  );
}

runAsyncMain(main);
