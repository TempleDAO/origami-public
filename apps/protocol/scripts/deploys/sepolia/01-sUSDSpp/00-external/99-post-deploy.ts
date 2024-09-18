import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await mine(INSTANCES.EXTERNAL.SKY.SUSDS_TOKEN.setInterestRate(DEFAULT_SETTINGS.EXTERNAL.SUSDS_INTEREST_RATE));

  // $USDS
  {
    await mine(
      INSTANCES.EXTERNAL.SKY.USDS_TOKEN.addMinter(
        INSTANCES.EXTERNAL.SKY.USDS_TOKEN.owner()
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.USDS_TOKEN.addMinter(
        ADDRS.CORE.MULTISIG
      )
    );

    await mine(
      INSTANCES.EXTERNAL.SKY.USDS_TOKEN.mint(
        ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, 
        ethers.utils.parseEther("100000000")
      )
    );
  }

  // $SKY
  {
    await mine(
      INSTANCES.EXTERNAL.SKY.SKY_TOKEN.addMinter(
        INSTANCES.EXTERNAL.SKY.SKY_TOKEN.owner()
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.SKY_TOKEN.addMinter(
        ADDRS.CORE.MULTISIG
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.SKY_TOKEN.mint(
        ADDRS.EXTERNAL.SKY.STAKING_FARMS.USDS_SKY,  
        ethers.utils.parseEther("10000000")
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.STAKING_FARMS.USDS_SKY.notifyRewardAmount(
        ethers.utils.parseEther("1000")
      )
    );
  }

  // $SDAO
  {
    await mine(
      INSTANCES.EXTERNAL.SKY.SDAO_TOKEN.addMinter(
        INSTANCES.EXTERNAL.SKY.SDAO_TOKEN.owner()
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.SDAO_TOKEN.addMinter(
        ADDRS.CORE.MULTISIG
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.SDAO_TOKEN.mint(
        ADDRS.EXTERNAL.SKY.STAKING_FARMS.USDS_SDAO, 
        ethers.utils.parseEther("10000000")
      )
    );
    await mine(
      INSTANCES.EXTERNAL.SKY.STAKING_FARMS.USDS_SDAO.notifyRewardAmount(
        ethers.utils.parseEther("1500")
      )
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });