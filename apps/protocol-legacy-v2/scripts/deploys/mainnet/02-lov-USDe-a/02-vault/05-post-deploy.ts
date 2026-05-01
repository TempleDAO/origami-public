import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

// Required for testnet run to impersonate the msig
async function setupPricesTestnet(owner: SignerWithAddress) { 
  const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);

  // $lov-sUSDe
  await mine(INSTANCES.CORE.TOKEN_PRICES.V1.connect(signer).setTokenPriceFunction(
    ADDRS.LOV_USDE_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_USDE_A.TOKEN)
  ));
}

async function setupPrices() { 
  // $lov-sUSDe
  await mine(INSTANCES.CORE.TOKEN_PRICES.V1.setTokenPriceFunction(
    ADDRS.LOV_USDE_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_USDE_A.TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_USDE_A.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_USDE_A.MANAGER),
  );
  await mine(
    INSTANCES.LOV_USDE_A.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_USDE_A.MANAGER.setOracles(
      ADDRS.ORACLES.USDE_DAI,
      ADDRS.ORACLES.USDE_DAI
    )
  );

  await mine(
    INSTANCES.LOV_USDE_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_USDE_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USDE_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_USDE_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_USDE_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USDE_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_USDE_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_USDE_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USDE_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USDE_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_USDE_A.TOKEN.setManager(
      ADDRS.LOV_USDE_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_USDE_A.MANAGER.setAllowAll(
      true
    )
  );

  if (network.name === "localhost") {
    await setupPricesTestnet(owner);
  } else {
    await setupPrices();
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });