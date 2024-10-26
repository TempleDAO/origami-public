import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockSUsdsToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new MockSUsdsToken__factory(owner);
  await deployAndMine(
    'EXTERNAL.SKY.SUSDS_TOKEN',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });