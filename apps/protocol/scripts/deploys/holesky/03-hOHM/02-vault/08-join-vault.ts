import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { CoolerTreasuryBorrower__factory, ICoolerTreasuryBorrower__factory, MockGohm__factory } from '../../../../../typechain';
import { ContractAddresses } from '../../contract-addresses/types';

let INSTANCES: ContractInstances;
const GOHM_AMOUNT = ethers.utils.parseEther("1000");

async function joinWithGohm(
  owner: SignerWithAddress,
  gohmAmountBN: BigNumber,
  accountAddress: string,
) {
  const vault = INSTANCES.VAULTS.hOHM.TOKEN;
  const vaultDecimals = await vault.decimals();
  const assetToken = INSTANCES.EXTERNAL.OLYMPUS.GOHM_TOKEN;
  const assetTokenDecimals = await assetToken.decimals();
  const liabilitiesToken = INSTANCES.EXTERNAL.SKY.USDS_TOKEN;
  const liabilitiesTokenDecimals = await liabilitiesToken.decimals();

  console.log("\tgOHM token balance:", ethers.utils.formatUnits(
    await assetToken.balanceOf(accountAddress),
    assetTokenDecimals,
  ));
  const allowance = await assetToken.allowance(await owner.getAddress(), vault.address);
  console.log("\tcurrent allowance:", ethers.utils.formatUnits(
    allowance,
    assetTokenDecimals,
  ));
  if (allowance.lt(gohmAmountBN)) {
    await mine(assetToken.approve(vault.address, ethers.constants.MaxUint256));
  }

  await mine(
    vault.joinWithToken(
      assetToken.address,
      gohmAmountBN,
      accountAddress
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
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  const mockGohm = MockGohm__factory.connect(ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN, owner);
  await mine(
    mockGohm.mint(await owner.getAddress(), GOHM_AMOUNT)
  );

  await joinWithGohm(
    owner,
    GOHM_AMOUNT,
    await owner.getAddress(),
  );

  // Send the USDS back to the ohm treasury, and send the hOHM shares to the dummy dex router
  const usdsBalance = await INSTANCES.EXTERNAL.SKY.USDS_TOKEN.balanceOf(await owner.getAddress());
  const ohmTreasuryBorrowerAddr = await INSTANCES.EXTERNAL.OLYMPUS.MONO_COOLER.treasuryBorrower();
  const ohmTreasuryBorrower = CoolerTreasuryBorrower__factory.connect(ohmTreasuryBorrowerAddr, owner);
  const olympusTreasury = await ohmTreasuryBorrower.TRSRY();
  await mine(
    INSTANCES.EXTERNAL.SKY.USDS_TOKEN.approve(ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, usdsBalance)
  );
  await mine(
    INSTANCES.EXTERNAL.SKY.SUSDS_TOKEN.deposit(usdsBalance, olympusTreasury)
  );
  const hOhmBalance = await INSTANCES.VAULTS.hOHM.TOKEN.balanceOf(await owner.getAddress());
  const hOhmToKeep = ethers.utils.parseEther("1000000");
  await mine(
    INSTANCES.VAULTS.hOHM.TOKEN.transfer(
      ADDRS.VAULTS.hOHM.DUMMY_DEX_ROUTER,
      hOhmBalance.sub(hOhmToKeep)
  ));
}

runAsyncMain(main);
