import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { 
  OrigamiCowSwapper__factory,
} from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiCowSwapper__factory(owner);
  await deployAndMine(
    'VAULTS.SUSDSpS.COW_SWAPPER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.COW_SWAP.VAULT_RELAYER
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });