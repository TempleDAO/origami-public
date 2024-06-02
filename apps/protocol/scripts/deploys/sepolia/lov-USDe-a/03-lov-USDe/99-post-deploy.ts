import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  mine,
  impersonateAndFund
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';
import { ContractAddresses } from '../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupPrices(owner: SignerWithAddress) {
  // This works in local fork testing. For actual testnet deploy, a multisig
  // operation will be required instead.
  const msig = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);

  // $lov-USDe-a
  await mine(INSTANCES.CORE.TOKEN_PRICES.connect(msig).setTokenPriceFunction(
    ADDRS.LOV_USDE.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_USDE.TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_USDE.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_USDE.MANAGER)
  );
  await mine(
    INSTANCES.LOV_USDE.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.LOV_USDE.SWAPPER_1INCH
    )
  );

  await mine(
    INSTANCES.LOV_USDE.MANAGER.setOracles(
      ADDRS.ORACLES.USDE_DAI,
      ADDRS.ORACLES.USDE_DAI
    )
  );

  await mine(
    INSTANCES.LOV_USDE.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_USDE.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USDE.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_USDE.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_USDE.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USDE.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_USDE.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_USDE.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USDE.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USDE.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_USDE.TOKEN.setManager(
      ADDRS.LOV_USDE.MANAGER
    )
  );

  await setupPrices(owner);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });