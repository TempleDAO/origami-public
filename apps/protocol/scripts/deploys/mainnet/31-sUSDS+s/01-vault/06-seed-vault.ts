import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';

let INSTANCES: ContractInstances;

const IMPERSONATE_SEED_WHALE = "0xDBF5E9c5206d0dB70a90108bf936DA60221dC080";

async function seedDeposit(
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.VAULTS.SUSDSpS.TOKEN;
  const vaultDecimals = await vault.decimals();
  const depositToken = INSTANCES.EXTERNAL.SKY.USDS_TOKEN;
  const depositTokenDecimals = await depositToken.decimals();

  console.log("\nseedDeposit(%f, %s, %f)", amountBN, accountAddress, maxSupply);

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await depositToken.balanceOf(accountAddress),
    depositTokenDecimals,
  ));
  await mine(depositToken.approve(vault.address, amountBN));

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
  
  if (network.name === 'localhost') {
    const signer = await impersonateAndFund(owner, IMPERSONATE_SEED_WHALE);
    await mine(INSTANCES.EXTERNAL.SKY.USDS_TOKEN.connect(signer).transfer(owner.getAddress(), DEFAULT_SETTINGS.VAULTS.SUSDSpS.SEED_DEPOSIT_SIZE));
  }

  await seedDeposit(
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.SEED_DEPOSIT_SIZE, 
    await owner.getAddress(), 
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.MAX_TOTAL_SUPPLY
  );
}

runAsyncMain(main);
