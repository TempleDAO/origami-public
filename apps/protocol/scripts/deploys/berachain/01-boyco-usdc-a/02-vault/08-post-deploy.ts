import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedErc4626TokenPrice,
  encodedScalar,
  mine,
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { TokenPrices } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    // @todo oracles for these in bera mainnet?
    honeyToUsd: encodedScalar(ethers.utils.parseUnits("1", 30)),
    usdcToUsd: encodedScalar(ethers.utils.parseUnits("1", 30)),

    vaultTokenToUsd: encodedErc4626TokenPrice(
      ADDRS.VAULTS.BOYCO_USDC_A.TOKEN
    ),
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    encodedPrices.usdcToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
    encodedPrices.honeyToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.BOYCO_USDC_A.TOKEN,
    encodedPrices.vaultTokenToUsd
  ));
}

async function setupPrices() { 
  return updatePrices(INSTANCES.CORE.TOKEN_PRICES.V3);
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));

  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN.setManager(
      ADDRS.VAULTS.BOYCO_USDC_A.MANAGER
    )
  );

  await setExplicitAccess(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, 
    ADDRS.VAULTS.BOYCO_USDC_A.MANAGER,
    ["stake", "withdraw"],
    true
  );
  await setExplicitAccess(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, 
    ADDRS.VAULTS.BOYCO_USDC_A.MANAGER,
    ["stake", "withdraw"],
    true
  );

  await setupPrices();
}

runAsyncMain(main);
