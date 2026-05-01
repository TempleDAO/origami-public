import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiCrossRateOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { ZERO_ADDRESS } from '../../../helpers';
import { connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  const INSTANCES = connectToContracts1(owner, ADDRS);

  const factory = new OrigamiCrossRateOracle__factory(owner);
  await deployAndMine(
    'ORACLES.SDAI_SUSDE',
    factory,
    factory.deploy,
    {
      description: "sDAI/sUSDe",
      baseAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.decimals(),
    },
    ADDRS.ORACLES.SDAI_USD_INTERNAL,
    ADDRS.ORACLES.SUSDE_USD_INTERNAL,
    ZERO_ADDRESS,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });