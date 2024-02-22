import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiInvestmentVault__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts();

  const factory = new OrigamiInvestmentVault__factory(owner);
  await deployAndMine(
    'ovGMX', factory, factory.deploy,
    await owner.getAddress(),
    'Origami GMX Vault', 'ovGMX',
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.oGMX,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.TOKEN_PRICES,
    500, // 5% performance fee
    7 * 86400 // Weekly vesting of reserves
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