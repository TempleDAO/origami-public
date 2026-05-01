import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockWstEthToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  
  const factory = new MockWstEthToken__factory(owner);
  await deployAndMine(
    'EXTERNAL.LIDO.WSTETH_TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.LIDO.ST_ETH_TOKEN,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });