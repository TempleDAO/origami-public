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
    'ORACLES.WBTC_SDAI',
    factory,
    factory.deploy,
    {
      description: "wBTC/sDAI",
      baseAssetAddress: ADDRS.EXTERNAL.WBTC_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.WBTC_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.decimals(),
    },
    ADDRS.ORACLES.WBTC_DAI,
    ADDRS.ORACLES.SDAI_DAI,
    ADDRS.ORACLES.DAI_USD,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });