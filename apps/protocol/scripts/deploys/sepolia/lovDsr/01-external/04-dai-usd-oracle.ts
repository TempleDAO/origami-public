import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { RelayedOracle, RelayedOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const answer: RelayedOracle.AnswerStruct = {
    roundId: 1,
    answer: 1.00044127e8,
    startedAt: 0,
    updatedAt: 0,
    answeredInRound: 1
  };

  const factory = new RelayedOracle__factory(owner);
  await deployAndMine(
    'EXTERNAL.CHAINLINK.DAI_USD_ORACLE',
    factory,
    factory.deploy,
    "DAI/USD",
    answer,
    8,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });