import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { IPMarket__factory, OrigamiPendlePtToAssetOracle__factory, PendlePYLpOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  const INSTANCES = connectToContracts(owner);

  const pendleOracleAddress = ADDRS.EXTERNAL.PENDLE.ORACLE;
  const pendleMarketAddress = ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.MARKET;
  const twapSecs = DEFAULT_SETTINGS.ORACLES.PT_SUSDE_OCT24_DAI.TWAP_DURATION_SECS;

  // Check the Pendle Oracle and increase the cardinality if required.
  {
    const pendleOracle = PendlePYLpOracle__factory.connect(pendleOracleAddress, owner);
    const oracleState = await pendleOracle.getOracleState(pendleMarketAddress, twapSecs);
    console.log("Existing Oracle State:", oracleState);
    if (oracleState.increaseCardinalityRequired) {
      console.log("Increase cardinality required");
      const market = IPMarket__factory.connect(pendleMarketAddress, owner);
      await mine(market.increaseObservationsCardinalityNext(oracleState.cardinalityRequired));

      if (network.name == 'localhost') {
        const block = await ethers.provider.getBlock("latest");
        const newTs = block.timestamp + twapSecs;
        await ethers.provider.send("evm_setNextBlockTimestamp", [newTs]);
        await ethers.provider.send("anvil_mine", [1]);
      } else {
        console.log(`Sleeping for the twap [${twapSecs}] seconds...`);
        await new Promise((resolve) => setTimeout(resolve, twapSecs * 1_000));
      }

      console.log("New Oracle State:", await pendleOracle.getOracleState(pendleMarketAddress, twapSecs));
    }
  }

  const factory = new OrigamiPendlePtToAssetOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_SUSDE_OCT24_USDE',
    factory,
    factory.deploy,
    {
      description: "PT-sUSDe-Oct24/USDe",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.decimals(),
    },
    pendleOracleAddress,
    pendleMarketAddress,
    twapSecs,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });