

import "@nomiclabs/hardhat-ethers";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalManager__factory } from "../../../../../typechain";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OpalManager__factory(owner);
  await deployAndMine(
    "VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.MANAGER",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.TOKEN.address,
    ADDRS.OPAL.ADAPTER_FACTORY,
  );
}

runAsyncMain(main);
