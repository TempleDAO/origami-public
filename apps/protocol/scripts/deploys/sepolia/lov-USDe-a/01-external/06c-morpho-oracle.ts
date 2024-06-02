import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MorphoChainlinkOracleV2__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  ZERO_ADDRESS,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new MorphoChainlinkOracleV2__factory(owner);

  // USDe -> USD 1:1 peg always.
  await deployAndMine(
    'EXTERNAL.MORPHO.USDE_USD_ORACLE',
    factory,
    factory.deploy,
    ZERO_ADDRESS,
    1,
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