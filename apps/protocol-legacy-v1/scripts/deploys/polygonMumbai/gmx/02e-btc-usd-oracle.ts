import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { DummyOracle, DummyOracle__factory } from '../../../../typechain';
import {
  blockTimestamp,
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new DummyOracle__factory(owner);
  const answer: DummyOracle.AnswerStruct = {
    roundId: 10,
    answer: ethers.utils.parseUnits("60000.0", 8), // Initial BTC/USD price.
    startedAt: await blockTimestamp(),
    updatedAtLag: 1,
    answeredInRound: 5
  };
  console.log([answer, 8]);
  await deployAndMine(
    'btcUsdOracle', factory, factory.deploy,
    answer, 8
  );
}
        
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });