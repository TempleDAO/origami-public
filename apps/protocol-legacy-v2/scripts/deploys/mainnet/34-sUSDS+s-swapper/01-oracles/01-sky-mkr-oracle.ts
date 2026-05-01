import {
  OrigamiFixedPriceOracle__factory,
} from "../../../../../typechain";
import {
  deployAndMine,
  ensureExpectedEnvvars,
  runAsyncMain,
  ZERO_ADDRESS,
} from "../../../helpers";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { getDeployContext } from "../../deploy-context";

async function main() {
  ensureExpectedEnvvars();
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // baseAsset of the cross oracle must be the baseAsset of the baseAssetOracle
  const fixedRateFactory = new OrigamiFixedPriceOracle__factory(owner);
  await deployAndMine(
    "ORACLES.SKY_MKR",
    fixedRateFactory,
    fixedRateFactory.deploy,
    {
      description: "SKY/MKR",
      baseAssetAddress: ADDRS.EXTERNAL.SKY.SKY_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.SKY.SKY_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.MKR_TOKEN,
      quoteAssetDecimals:
        await INSTANCES.EXTERNAL.MAKER_DAO.MKR_TOKEN.decimals(),
    },
    DEFAULT_SETTINGS.ORACLES.SKY_MKR.FIXED_PRICE,
    ZERO_ADDRESS
  );
}

runAsyncMain(main);