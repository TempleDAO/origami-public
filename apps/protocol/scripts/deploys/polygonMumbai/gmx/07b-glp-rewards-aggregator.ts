import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiGmxRewardsAggregator__factory } from '../../../../typechain';
import {
  GmxVaultType,
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts();

  const factory = new OrigamiGmxRewardsAggregator__factory(owner);
  await deployAndMine(
    'origamiGlpRewardsAggregator', factory, factory.deploy,
    GmxVaultType.GLP,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GMX_MANAGER,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_MANAGER,
    [
        { // weth performance fee
            numerator: 0,
            denominator: 100,
        },
        { // oGMX performance fee
            numerator: 0,
            denominator: 100,
        },
    ],
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