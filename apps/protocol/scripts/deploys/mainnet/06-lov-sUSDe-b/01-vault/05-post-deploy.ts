import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TokenPrices } from '../../../../../typechain';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function updatePrices(contract: TokenPrices) {
    // $lov-sUSDe
    await mine(contract.setTokenPriceFunction(
      ADDRS.LOV_SUSDE_B.TOKEN,
      encodedRepricingTokenPrice(ADDRS.LOV_SUSDE_B.TOKEN)
    ));
}

// Required for testnet run to impersonate the msig
async function setupPricesTestnet(owner: SignerWithAddress) { 
  const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V1.connect(signer));
}

async function setupPrices() { 
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V1);
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_SUSDE_B.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_SUSDE_B.MANAGER),
  );
  await mine(
    INSTANCES.LOV_SUSDE_B.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.SUSDE_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_B.MANAGER.setOracles(
      ADDRS.ORACLES.SUSDE_DAI,
      ADDRS.ORACLES.USDE_DAI
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_B.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_SUSDE_B.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_SUSDE_B.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_SUSDE_B.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_SUSDE_B.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_SUSDE_B.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_B.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_SUSDE_B.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_SUSDE_B.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_SUSDE_B.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_B.TOKEN.setManager(
      ADDRS.LOV_SUSDE_B.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_SUSDE_B.MANAGER.setAllowAll(
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