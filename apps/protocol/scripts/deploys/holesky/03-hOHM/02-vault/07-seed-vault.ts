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
import { MockGohm__factory } from '../../../../../typechain';
import { ContractAddresses } from '../../contract-addresses/types';

let INSTANCES: ContractInstances;

async function seedDeposit(
  owner: SignerWithAddress,
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

  console.log("\tasset token balance:", ethers.utils.formatUnits(
    await assetToken.balanceOf(accountAddress),
    assetTokenDecimals,
  ));
  const allowance = await assetToken.allowance(await owner.getAddress(), vault.address);
  console.log("\tcurrent allowance:", ethers.utils.formatUnits(
    allowance,
    assetTokenDecimals,
  ));

  // @todo testnet only - uses max on both.
  if (allowance.lt(ethers.constants.MaxUint256)) {
    await mine(assetToken.approve(vault.address, ethers.constants.MaxUint256));
  }

  const liabilityAllowance = await liabilitiesToken.allowance(await owner.getAddress(), vault.address);
  if (liabilityAllowance.lt(ethers.constants.MaxUint256)) {
    await mine(liabilitiesToken.approve(vault.address, ethers.constants.MaxUint256));
  }

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

async function main() {
  let owner: SignerWithAddress;
  let ADDRS: ContractAddresses;
  ({owner, INSTANCES, ADDRS} = await getDeployContext(__dirname));
  
  // Testnet only
  {
    const mockGohm = MockGohm__factory.connect(ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN, owner);
    await mine(mockGohm.mint(owner.getAddress(), DEFAULT_SETTINGS.VAULTS.hOHM.SEED_GOHM_AMOUNT));
  }

  await seedDeposit(
    owner,
    DEFAULT_SETTINGS.VAULTS.hOHM.SEED_GOHM_AMOUNT, 
    DEFAULT_SETTINGS.VAULTS.hOHM.SEED_USDS_AMOUNT, 
    DEFAULT_SETTINGS.VAULTS.hOHM.SEED_SHARES_AMOUNT, 
    await owner.getAddress(), 
    DEFAULT_SETTINGS.VAULTS.hOHM.MAX_TOTAL_SUPPLY
  );
}

runAsyncMain(main);
