import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiErc4626Oracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiErc4626Oracle__factory(owner);
  await deployAndMine(
    'ORACLES.SUSDE_USD_INTERNAL',
    factory,
    factory.deploy,
    {
      description: "sUSDe/USD",
      baseAssetAddress: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.INTERNAL_USD,
      quoteAssetDecimals: 18,
    },
    ZERO_ADDRESS,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });