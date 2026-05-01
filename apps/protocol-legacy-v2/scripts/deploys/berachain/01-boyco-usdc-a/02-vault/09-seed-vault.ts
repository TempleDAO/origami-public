import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';

let INSTANCES: ContractInstances;

async function seedDeposit(
  owner: SignerWithAddress,
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN;
  const vaultDecimals = await vault.decimals();
  const depositToken = INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN;
  const depositTokenDecimals = await depositToken.decimals();

  // Assumes owner already has the USDC deposit token
  console.log("\nseedDeposit(%f, %s, %f)", amountBN, accountAddress, maxSupply);

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
    vault.seedDeposit(
        amountBN,
        accountAddress,
        maxSupply,
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
  ({owner, INSTANCES} = await getDeployContext(__dirname));
  
  await seedDeposit(
    owner,
    DEFAULT_SETTINGS.VAULTS.BOYCO_USDC_A.SEED_DEPOSIT_SIZE, 
    await owner.getAddress(), 
    DEFAULT_SETTINGS.VAULTS.BOYCO_USDC_A.MAX_TOTAL_SUPPLY
  );
}

runAsyncMain(main);
