import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { IERC20Metadata, IERC20Metadata__factory, IOpalAdapterAaveV3__factory, OpalManager, OpalManager__factory, OpalVault } from '../../../../../typechain';

let INSTANCES: ContractInstances;
let OPAL_INSTANCES: OpalContracts;

interface OpalContracts {
  VAULT: OpalVault;
  MANAGER: OpalManager;
  ASSET_TOKEN: IERC20Metadata;
  LIABILITY_TOKEN: IERC20Metadata;
  ASSET_AMOUNT: BigNumber;
  ASSET_WHALE: string;
}

const getContracts = async (vault: OpalVault, owner: SignerWithAddress): Promise<OpalContracts> => {
  const [manager, [assetTokens, liabilityTokens]] = await Promise.all([
    vault.manager(),
    vault.tokens(),
  ]);
  if (assetTokens.length != 1) console.warn("Can only handle 1 asset for now - using first one");
  if (liabilityTokens.length != 1) console.warn("Can only handle 1 liability for now - using first one");

  return {
    VAULT: vault,
    MANAGER: OpalManager__factory.connect(manager, owner),
    ASSET_TOKEN: IERC20Metadata__factory.connect(assetTokens[0], owner),
    LIABILITY_TOKEN: IERC20Metadata__factory.connect(liabilityTokens[0], owner),
    ASSET_AMOUNT: ethers.utils.parseEther("50"),
    ASSET_WHALE: '0xa3A7B6F88361F48403514059F1F16C8E78d60EeC',
  };
}

async function joinWithAsset(
  owner: SignerWithAddress,
  assetAmountBN: BigNumber,
  accountAddress: string,
) {
  const vault = OPAL_INSTANCES.VAULT;
  const vaultDecimals = await vault.decimals();
  const assetToken = OPAL_INSTANCES.ASSET_TOKEN;
  const assetTokenDecimals = await assetToken.decimals();
  const liabilitiesToken = OPAL_INSTANCES.LIABILITY_TOKEN;
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
  if (allowance.lt(assetAmountBN)) {
    await mine(assetToken.approve(vault.address, ethers.constants.MaxUint256));
  }

  await mine(
    vault.joinWithToken(
      assetToken.address,
      assetAmountBN,
      accountAddress,
      await vault.currentTokensHash(),
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

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V4.tokenPrices([
    OPAL_INSTANCES.ASSET_TOKEN.address,
    OPAL_INSTANCES.LIABILITY_TOKEN.address,
    OPAL_INSTANCES.VAULT.address,
  ]);
  console.log("\nToken Prices:");
  console.log(`\t$${await OPAL_INSTANCES.ASSET_TOKEN.symbol()}:`, ethers.utils.formatUnits(prices[0], 30));
  console.log(`\t$${await OPAL_INSTANCES.LIABILITY_TOKEN.symbol()}:`, ethers.utils.formatUnits(prices[1], 30));
  console.log(`\t$${await OPAL_INSTANCES.VAULT.symbol()}:`, ethers.utils.formatUnits(prices[2], 30));
}

async function dumpBalanceSheet(owner: SignerWithAddress) {
  const [
    totalSupply,
    [aTokens, lTokens]
   ] = await Promise.all([
    OPAL_INSTANCES.VAULT.totalSupply(),
    OPAL_INSTANCES.VAULT.tokens(),
  ]);
  const aTokenContracts = aTokens.map(token => IERC20Metadata__factory.connect(token, owner));
  const lTokenContracts = lTokens.map(token => IERC20Metadata__factory.connect(token, owner));
  const aTokenSymbols = await Promise.all(aTokenContracts.map(token => token.symbol()));
  const aTokenDecimals = await Promise.all(aTokenContracts.map(token => token.decimals()));
  const lTokenSymbols = await Promise.all(lTokenContracts.map(token => token.symbol()));
  const lTokenDecimals = await Promise.all(lTokenContracts.map(token => token.decimals()));
  const [aBalances, lBalances] = await OPAL_INSTANCES.VAULT.balanceSheet();
  console.log(`\nTOTAL SUPPLY: ${ethers.utils.formatEther(totalSupply)}`);
  console.log("\nASSET BALANCES:");
  aBalances.forEach((bal, i) => console.log(`\t${aTokenSymbols[i]}: ${ethers.utils.formatUnits(bal, aTokenDecimals[i])}`));
  console.log("LIABILITY BALANCES:");
  lBalances.forEach((bal, i) => console.log(`\t${lTokenSymbols[i]}: ${ethers.utils.formatUnits(bal, lTokenDecimals[i])}`));
}

async function getSymbols(tokenAddrs: string[], owner: SignerWithAddress) {
  return Promise.all(tokenAddrs.map(token => IERC20Metadata__factory.connect(token, owner).symbol()));
}

async function dumpAdapterDetails(owner: SignerWithAddress) {
  const adapterAddrs = await OPAL_INSTANCES.MANAGER.adapters();
  const adapters = adapterAddrs.map(addr => IOpalAdapterAaveV3__factory.connect(addr, owner));

  console.log("\nADAPTERS:");
  for (const adapter of adapters) {
    const [
      implTypeAndVersion,
      description,
      [assetGroupIds, liabilityGroupIds],
      currentLtv,
      maxSafeLtv,
      liquidationLtv,
      healthFactor,
      maxLoanUtilizationRatioOnJoin,
      [assetAddrs, liabilityAddrs],
    ] = await Promise.all([
      adapter.implTypeAndVersion(),
      adapter.description(),
      adapter.groupIds(),
      adapter.currentLtv(),
      adapter.maxSafeLtv(),
      adapter.liquidationLtv(),
      adapter.healthFactor(),
      adapter.maxLoanUtilizationRatioOnJoin(),
      adapter.tokens(),
    ]);

    const [assetSymbols, liabilitySymbols] = await Promise.all([
      getSymbols(assetAddrs, owner),
      getSymbols(liabilityAddrs, owner),
    ]);

    console.log(`\t${implTypeAndVersion} ${description}`);
    console.log(`\t\taddress = ${adapter.address}`);
    console.log(`\t\tassets = ${assetSymbols}`);
    console.log(`\t\tliabilities = ${liabilitySymbols}`);
    console.log(`\t\tgroup IDs:`);
    assetGroupIds.forEach((gid, i) => console.log(`\t\t${assetSymbols[i]}: ${gid}`));
    liabilityGroupIds.forEach((gid, i) => console.log(`\t\t${liabilitySymbols[i]}: ${gid}`));
    console.log(`\t\tcurrent LTV = ${ethers.utils.formatEther(currentLtv)}`);
    console.log(`\t\tmax safe LTV = ${ethers.utils.formatEther(maxSafeLtv)}`);
    console.log(`\t\tliquidation LTV = ${ethers.utils.formatEther(liquidationLtv)}`);
    console.log(`\t\thealth factor = ${ethers.utils.formatEther(healthFactor)}`);
    console.log(`\t\tmax UR for join = ${ethers.utils.formatEther(maxLoanUtilizationRatioOnJoin)}`);
  }
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, INSTANCES} = await getDeployContext(__dirname));
  OPAL_INSTANCES = await getContracts(INSTANCES.VAULTS.OPAL_WEETH_A.TOKEN, owner);

  await dumpPrices();
  await dumpBalanceSheet(owner);
  await dumpAdapterDetails(owner);

  const signer = await impersonateAndFund2(OPAL_INSTANCES.ASSET_WHALE);
  await mine(OPAL_INSTANCES.ASSET_TOKEN.connect(signer).transfer(
    await owner.getAddress(), 
    OPAL_INSTANCES.ASSET_AMOUNT
  ));
  
  await joinWithAsset(
    owner,
    OPAL_INSTANCES.ASSET_AMOUNT,
    await owner.getAddress(),
  );

  await dumpPrices();
  await dumpBalanceSheet(owner);
  await dumpAdapterDetails(owner);
}

runAsyncMain(main);
