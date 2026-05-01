import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { approve, createSafeBatch, seedOrigami4626, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';

let INSTANCES: ContractInstances;

const DEPOSIT_TOKEN_WHALE = "0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3";

async function seedDepositTestnet(
  assetAmountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.VAULTS.SKYp.TOKEN;
  const vaultDecimals = await vault.decimals();
  const assetToken = INSTANCES.EXTERNAL.SKY.SKY_TOKEN;
  const assetTokenDecimals = await assetToken.decimals();

  await mine(
    assetToken.approve(vault.address, assetAmountBN)
  );
  await mine(
    vault.seedDeposit(
        assetAmountBN,
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
  
  const sharePrice = await vault.convertToAssets(ethers.utils.parseUnits("1", vaultDecimals));
  console.log("\tshare price:", ethers.utils.formatUnits(
    sharePrice,
    assetTokenDecimals,
  ));
}

async function seedDepositMainnet(
  assetAmountBN: BigNumber,
  receiverAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.VAULTS.SKYp.TOKEN;
  const assetToken = INSTANCES.EXTERNAL.SKY.SKY_TOKEN;
  const batch = createSafeBatch(
    [
      approve(assetToken, vault.address, assetAmountBN),
      seedOrigami4626(vault, assetAmountBN, receiverAddress, maxSupply),
    ]
  );

  const filename = path.join(__dirname, "../seed-vault.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, INSTANCES} = await getDeployContext(__dirname));
  
  if (network.name === 'localhost') {
    const signer = await impersonateAndFund2(DEPOSIT_TOKEN_WHALE);
    await mine(INSTANCES.EXTERNAL.SKY.SKY_TOKEN.connect(signer).transfer(
      owner.getAddress(),
      DEFAULT_SETTINGS.VAULTS.SKYp.SEED_DEPOSIT_SIZE
    ));

    await seedDepositTestnet(
      DEFAULT_SETTINGS.VAULTS.SKYp.SEED_DEPOSIT_SIZE,
      await owner.getAddress(), 
      DEFAULT_SETTINGS.VAULTS.SKYp.MAX_TOTAL_SUPPLY
    );
  } else {
    await seedDepositMainnet(
      DEFAULT_SETTINGS.VAULTS.SKYp.SEED_DEPOSIT_SIZE, 
      await owner.getAddress(), 
      DEFAULT_SETTINGS.VAULTS.SKYp.MAX_TOTAL_SUPPLY
    );
  }
}

runAsyncMain(main);
