import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { AdaptiveCurveIrm__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new AdaptiveCurveIrm__factory(owner);
  await deployAndMine(
    'EXTERNAL.MORPHO.IRM',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.MORPHO.SINGLETON
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });