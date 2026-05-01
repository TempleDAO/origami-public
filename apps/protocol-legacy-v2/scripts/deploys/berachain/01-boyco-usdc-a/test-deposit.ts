import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  mine,
  runAsyncMain,
} from '../../helpers';
import { ContractInstances } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../deploy-context';
import { BigNumber } from 'ethers';
import { ContractAddresses } from '../contract-addresses/types';

let INSTANCES: ContractInstances;

async function deposit(
  owner: SignerWithAddress,
  amountBN: BigNumber,
  accountAddress: string,
) {
  const vault = INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN;
  const vaultDecimals = await vault.decimals();
  const depositToken = INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN;
  const depositTokenDecimals = await depositToken.decimals();

  // Assumes owner already has the USDC deposit token
  console.log("\ndeposit(%f, %s, %f)", amountBN, accountAddress);

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await depositToken.balanceOf(accountAddress),
    depositTokenDecimals,
  ));
  const allowance = await depositToken.allowance(await owner.getAddress(), vault.address);
  console.log("\tcurrent allowance:", ethers.utils.formatUnits(
    allowance,
    depositTokenDecimals,
  ));
  if (allowance.lt(amountBN)) {
    await mine(depositToken.approve(vault.address, amountBN));
  }

  const expectedShares = await vault.previewDeposit(amountBN);

  console.log("\tExpect Shares:", ethers.utils.formatUnits(
    expectedShares,
    vaultDecimals,
  ));
  await mine(
    vault.deposit(
        amountBN,
        accountAddress,
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
}

async function main() {
  let owner: SignerWithAddress;
  let ADDRS: ContractAddresses;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [ADDRS.CORE.MULTISIG]);
  const msig = provider.getSigner(ADDRS.CORE.MULTISIG);
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.connect(msig).recoverToken(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, await owner.getAddress(), ethers.utils.parseUnits("10", 6)));

  await deposit(
    owner,
    DEFAULT_SETTINGS.VAULTS.BOYCO_USDC_A.SEED_DEPOSIT_SIZE, 
    await owner.getAddress()
  );
}

runAsyncMain(main);
