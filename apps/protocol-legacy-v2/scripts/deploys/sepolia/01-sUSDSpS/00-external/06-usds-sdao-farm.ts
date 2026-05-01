import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';
import { DummySkyStakingRewards__factory } from '../../../../../typechain';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new DummySkyStakingRewards__factory(owner);
  await deployAndMine(
    'EXTERNAL.SKY.STAKING_FARMS.USDS_SDAO',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.SKY.SDAO_TOKEN,
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });