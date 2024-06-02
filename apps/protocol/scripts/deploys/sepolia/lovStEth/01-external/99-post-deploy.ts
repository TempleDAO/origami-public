import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ZERO_ADDRESS,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const INSTANCES = connectToContracts(owner);
  const ADDRS = getDeployedContracts();

  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.addMinter(
      INSTANCES.EXTERNAL.WETH_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );

  await mine(
    INSTANCES.EXTERNAL.LIDO.ST_ETH_TOKEN.addMinter(
      INSTANCES.EXTERNAL.LIDO.ST_ETH_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.LIDO.ST_ETH_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );

  await mine(
    INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.addMinter(
      INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );

  // Kickstart the stETH accrual
  await INSTANCES.EXTERNAL.LIDO.ST_ETH_TOKEN.connect(owner).submit(
    ZERO_ADDRESS, {value: ethers.utils.parseEther("0.01")}
  );

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });