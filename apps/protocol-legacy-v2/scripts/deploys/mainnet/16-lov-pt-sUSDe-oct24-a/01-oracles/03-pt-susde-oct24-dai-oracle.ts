import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiCrossRateOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  const INSTANCES = connectToContracts(owner);

  const factory = new OrigamiCrossRateOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_SUSDE_OCT24_DAI',
    factory,
    factory.deploy,
    {
      description: "PT-sUSDe-Oct24/DAI",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.decimals(),
    },
    ADDRS.ORACLES.PT_SUSDE_OCT24_USDE,
    ADDRS.ORACLES.USDE_DAI, // assumes DAI === USD
    ADDRS.ORACLES.DAI_USD,  // Not used within the price, but checked that it hasn't depegged.
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });