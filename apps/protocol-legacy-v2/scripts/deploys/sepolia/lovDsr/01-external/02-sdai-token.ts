import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockSDaiToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new MockSDaiToken__factory(owner);
  await deployAndMine(
    'EXTERNAL.MAKER_DAO.SDAI_TOKEN',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });