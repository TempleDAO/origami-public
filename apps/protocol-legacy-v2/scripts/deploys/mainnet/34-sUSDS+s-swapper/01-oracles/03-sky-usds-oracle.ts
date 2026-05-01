import {
  OrigamiCrossRateOracle__factory,
} from "../../../../../typechain";
import {
  deployAndMine,
  ensureExpectedEnvvars,
  runAsyncMain,
  ZERO_ADDRESS,
} from "../../../helpers";
import { getDeployContext } from "../../deploy-context";

async function main() {
  ensureExpectedEnvvars();
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const crossRateFactory = new OrigamiCrossRateOracle__factory(owner);
  await deployAndMine(
    "ORACLES.SKY_USDS",
    crossRateFactory,
    crossRateFactory.deploy,
    {
      description: "SKY/USDS",
      baseAssetAddress: ADDRS.EXTERNAL.SKY.SKY_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.SKY.SKY_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
      quoteAssetDecimals:
        await INSTANCES.EXTERNAL.SKY.USDS_TOKEN.decimals(),
    },
    ADDRS.ORACLES.SKY_MKR,
    ADDRS.ORACLES.MKR_USDS,
    ZERO_ADDRESS
  );
}

runAsyncMain(main)
