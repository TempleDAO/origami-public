import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiErc4626AndDexAggregatorSwapper__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiErc4626AndDexAggregatorSwapper__factory(owner);
  await deployAndMine(
    'SWAPPERS.ERC4626_AND_1INCH_SWAPPER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.ONE_INCH.ROUTER_V6,
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });