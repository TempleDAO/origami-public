import { deployAndMine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalVault__factory } from "../../../../../typechain";
import { DEFAULT_SETTINGS } from "../../default-settings";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OpalVault__factory(owner);
  await deployAndMine(
    "VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN",
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN_SYMBOL,
    DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.AUM_FEE_BPS,
    ADDRS.CORE.MULTISIG, // fee collector
    ADDRS.CORE.TOKEN_PRICES.V4,
  );
}

runAsyncMain(main);
