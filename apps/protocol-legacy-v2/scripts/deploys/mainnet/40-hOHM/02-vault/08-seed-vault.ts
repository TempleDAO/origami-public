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
import { approve, createSafeBatch, seedTokenizedBalanceSheet, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { ContractAddresses } from '../../contract-addresses/types';

let INSTANCES: ContractInstances;
const GOHM_WHALE = '0x56D24a19dCbF8b08BEbAe9995Ea41Cb001120235';

async function seedDepositTestnet(
  assetAmountBN: BigNumber,
  liabilityAmountBN: BigNumber,
  sharesToMintBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.VAULTS.hOHM.TOKEN;
  const vaultDecimals = await vault.decimals();
  const assetToken = INSTANCES.EXTERNAL.OLYMPUS.GOHM_TOKEN;
  const assetTokenDecimals = await assetToken.decimals();
  const liabilitiesToken = INSTANCES.EXTERNAL.SKY.USDS_TOKEN;
  const liabilitiesTokenDecimals = await liabilitiesToken.decimals();

  await mine(
    assetToken.approve(vault.address, assetAmountBN)
  );
  await mine(
    vault.seed(
        [assetAmountBN],
        [liabilityAmountBN],
        sharesToMintBN,
        accountAddress,
        maxSupply,
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tAccount balance of liabilities:", ethers.utils.formatUnits(
    await liabilitiesToken.balanceOf(accountAddress),
    liabilitiesTokenDecimals,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
  
  const sharePrices = await vault.convertFromShares(ethers.utils.parseUnits("1", vaultDecimals));
  console.log("\tasset[0] share price:", ethers.utils.formatUnits(
    sharePrices.assets[0],
    assetTokenDecimals,
  ));
  console.log("\tliabilities[0] share price:", ethers.utils.formatUnits(
    sharePrices.liabilities[0],
    liabilitiesTokenDecimals,
  ));
}

async function seedDepositMainnet(
  assetAmountBN: BigNumber,
  liabilityAmountBN: BigNumber,
  sharesToMintBN: BigNumber,
  receiverAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.VAULTS.hOHM.TOKEN;
  const assetToken = INSTANCES.EXTERNAL.OLYMPUS.GOHM_TOKEN;
  const batch = createSafeBatch(
    [
      approve(assetToken, vault.address, assetAmountBN),
      seedTokenizedBalanceSheet(vault, [assetAmountBN], [liabilityAmountBN], sharesToMintBN, receiverAddress, maxSupply),
    ]
  );

  const filename = path.join(__dirname, "../seed-vault.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  let owner: SignerWithAddress;
  let ADDRS: ContractAddresses;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  // Localhost only
  if (network.name === 'localhost') {
    const signer = await impersonateAndFund2(GOHM_WHALE);
    await mine(INSTANCES.EXTERNAL.OLYMPUS.GOHM_TOKEN.connect(signer).transfer(
      owner.getAddress(), 
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_GOHM_AMOUNT
    ));

    await seedDepositTestnet(
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_GOHM_AMOUNT, 
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_USDS_AMOUNT, 
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_SHARES_AMOUNT, 
      await owner.getAddress(), 
      DEFAULT_SETTINGS.VAULTS.hOHM.MAX_TOTAL_SUPPLY
    );
  } else {
    await seedDepositMainnet(
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_GOHM_AMOUNT, 
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_USDS_AMOUNT, 
      DEFAULT_SETTINGS.VAULTS.hOHM.SEED_SHARES_AMOUNT, 
      ADDRS.CORE.MULTISIG, 
      DEFAULT_SETTINGS.VAULTS.hOHM.MAX_TOTAL_SUPPLY
    );
  }
}

runAsyncMain(main);
