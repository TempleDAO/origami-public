import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MorphoChainlinkOracleV2__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  ZERO_ADDRESS,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new MorphoChainlinkOracleV2__factory(owner);
  await deployAndMine(
    'EXTERNAL.MORPHO.ORACLE',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
    ethers.utils.parseEther("1"),
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    18,
    ZERO_ADDRESS,
    1,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    18,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });