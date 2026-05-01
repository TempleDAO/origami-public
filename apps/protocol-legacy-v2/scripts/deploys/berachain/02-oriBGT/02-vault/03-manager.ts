import "@nomiclabs/hardhat-ethers";
import { OrigamiInfraredVaultManager__factory } from "../../../../../typechain";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiInfraredVaultManager__factory(owner);
  await deployAndMine(
    "VAULTS.ORIBGT.MANAGER",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
    ADDRS.EXTERNAL.INFRARED.IBGT_VAULT,
    ADDRS.CORE.FEE_COLLECTOR,
    ADDRS.VAULTS.ORIBGT.SWAPPER,
    DEFAULT_SETTINGS.VAULTS.ORIBGT.PERFORMANCE_FEE
  );
}

runAsyncMain(main);
