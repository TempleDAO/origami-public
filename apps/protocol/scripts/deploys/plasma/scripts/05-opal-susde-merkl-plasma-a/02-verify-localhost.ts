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
import { IERC20Metadata, IERC20Metadata__factory, IOpalAdapterAaveV3__factory, IOrigamiBundlerPluginEulerFlash, IOrigamiBundlerPluginEulerFlash__factory, OpalManager, OpalManager__factory, OpalVault, TokenPrices } from '../../../../../typechain';
import { ContractAddresses } from '../../contract-addresses/types';
import { CallStruct } from '../../../../../typechain/contracts/investments/opal/OpalManager';
import { AbiCoder } from '@ethersproject/abi';
import { keccak256 } from 'ethers/lib/utils';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
let OPAL_INSTANCES: OpalContracts;

interface OpalContracts {
  VAULT: OpalVault;
  MANAGER: OpalManager;
  ASSET_TOKENS: IERC20Metadata[];
  LIABILITY0_TOKEN: IERC20Metadata;
  ASSET_AMOUNT: BigNumber;
  ASSET_WHALE: string;
}

const getContracts = async (vault: OpalVault, owner: SignerWithAddress): Promise<OpalContracts> => {
  const [manager, [assetTokens, liabilityTokens]] = await Promise.all([
    vault.manager(),
    vault.tokens(),
  ]);
  if (liabilityTokens.length != 1) console.warn("Can only handle 1 liability for now - using first one");

  return {
    VAULT: vault,
    MANAGER: OpalManager__factory.connect(manager, owner),
    ASSET_TOKENS: assetTokens.map((at) => IERC20Metadata__factory.connect(at, owner)),
    LIABILITY0_TOKEN: IERC20Metadata__factory.connect(liabilityTokens[0], owner),
    ASSET_AMOUNT: ethers.utils.parseEther("10000"),
    ASSET_WHALE: '0xdb3FaAD4436E2d133fdaB0788332845df9b0ABdF',
  };
}

async function joinWithAsset(
  owner: SignerWithAddress,
  asset0AmountBN: BigNumber,
  accountAddress: string,
) {
  const vault = OPAL_INSTANCES.VAULT;
  const vaultDecimals = await vault.decimals();
  const asset0Token = OPAL_INSTANCES.ASSET_TOKENS[0];
  const liability0Token = OPAL_INSTANCES.LIABILITY0_TOKEN;

  const [assetToken0Decimals, liabilityToken0Decimals] = await Promise.all([
    asset0Token.decimals(),
    liability0Token.decimals(),
  ]);

  console.log("\tasset token 0 balance:", ethers.utils.formatUnits(
    await asset0Token.balanceOf(accountAddress),
    assetToken0Decimals,
  ));
  const allowance = await asset0Token.allowance(await owner.getAddress(), vault.address);
  console.log("\tcurrent allowance:", ethers.utils.formatUnits(
    allowance,
    assetToken0Decimals,
  ));
  if (allowance.lt(asset0AmountBN)) {
    await mine(asset0Token.approve(vault.address, ethers.constants.MaxUint256));
  }

  await mine(
    vault.joinWithToken(
      asset0Token.address,
      asset0AmountBN,
      accountAddress,
      await vault.currentTokensHash(),
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tAccount balance of liabilities:", ethers.utils.formatUnits(
    await liability0Token.balanceOf(accountAddress),
    liabilityToken0Decimals,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
  
  const sharePrices = await vault.convertFromShares(ethers.utils.parseUnits("1", vaultDecimals));
  console.log("\tasset[0] share price:", ethers.utils.formatUnits(
    sharePrices.assets[0],
    assetToken0Decimals,
  ));
  console.log("\tliabilities[0] share price:", ethers.utils.formatUnits(
    sharePrices.liabilities[0],
    liabilityToken0Decimals,
  ));
}

async function dumpPrices(tokenPrices: TokenPrices) {
  const [liabilityPriceUsd, vaultPriceUsd, ...assetPricesUsd] = await tokenPrices.tokenPrices([
    OPAL_INSTANCES.LIABILITY0_TOKEN.address,
    OPAL_INSTANCES.VAULT.address,
    ...OPAL_INSTANCES.ASSET_TOKENS.map((at) => at.address),
  ]);

  console.log("\nToken Prices:");
  for (const [i, price] of assetPricesUsd.entries()) {
    const symbol = await OPAL_INSTANCES.ASSET_TOKENS[i].symbol();
    console.log(`\t$${await OPAL_INSTANCES.ASSET_TOKENS[i].symbol()}:`, ethers.utils.formatUnits(price, 30));
  }
  console.log(`\t$${await OPAL_INSTANCES.LIABILITY0_TOKEN.symbol()}:`, ethers.utils.formatUnits(liabilityPriceUsd, 30));
  console.log(`\t$${await OPAL_INSTANCES.VAULT.symbol()}:`, ethers.utils.formatUnits(vaultPriceUsd, 30));
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

async function reallocateCollateral(
  p: {
    owner: SignerWithAddress;
    manager: OpalManager;
    asset0TargetRatio: { numerator: number, denominator: number };
  },
) {
  const {owner, manager, asset0TargetRatio} = p;
  const flashPlugin = IOrigamiBundlerPluginEulerFlash__factory.connect(ADDRS.BUNDLER.PLUGINS.FLASHLOAN.EULER, owner);
  const eulerUsdt0VaultAddress = "0x8Aec278c2fD4cc07B10A8865AEd33775f93EACe6";

  const abiCoder = ethers.utils.defaultAbiCoder;
  const innerBundle: CallStruct[] = [
    {
      to: flashPlugin.address,
      data: "0x",
      value: 0,
      skipRevert: false,
      callbackHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
    }
  ];

  const encodedInnerBundle = abiCoder.encode(
    [
      "tuple(address to, bytes data, uint256 value, bool skipRevert, bytes32 callbackHash)[]",
    ],
    [innerBundle]
  );

  const flCall = flashPlugin.interface.encodeFunctionData("flashLoan", [
    eulerUsdt0VaultAddress,
    ethers.utils.parseUnits("1000", 6),
    encodedInnerBundle,
  ]);
  console.log(flCall);
  await mine(
    manager.multicall([
      {
        to: flashPlugin.address,
        data: flCall,
        value: BigNumber.from(0),
        skipRevert: false,
        callbackHash: keccak256(encodedInnerBundle),
      }
    ])
  );
  // Assuming no FL fee:
  //  - Flash sUSDe
  //  - Add sUSDe as collateral
  //  - Withdraw USDe collateral
  //  - Sell USDe => sUSDe
  //  - Repay sUSDe

  // If we have to use Euler and swap:
  //  - Flash USDT0
  //  - Sell USDT0 => sUSDe
  //  - Add sUSDe as collateral
  //  - Withdraw USDe collateral
  //  - Sell USDe => USDT0
  //  - Repay USDT0
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, INSTANCES, ADDRS} = await getDeployContext(__dirname));
  OPAL_INSTANCES = await getContracts(INSTANCES.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.TOKEN, owner);
  const tokenPrices = INSTANCES.CORE.TOKEN_PRICES.V1;

  await dumpPrices(tokenPrices);
  await dumpBalanceSheet(owner);
  await dumpAdapterDetails(owner);

  const signer = await impersonateAndFund2(OPAL_INSTANCES.ASSET_WHALE);
  await mine(OPAL_INSTANCES.ASSET_TOKENS[0].connect(signer).transfer(
    await owner.getAddress(), 
    OPAL_INSTANCES.ASSET_AMOUNT
  ));
  
  await joinWithAsset(
    owner,
    OPAL_INSTANCES.ASSET_AMOUNT,
    await owner.getAddress(),
  );

  await dumpPrices(tokenPrices);
  await dumpBalanceSheet(owner);
  await dumpAdapterDetails(owner);

  // await reallocateCollateral({
  //   owner,
  //   manager: OPAL_INSTANCES.MANAGER,
  //   asset0TargetRatio: {numerator: 50.5, denominator: 100},
  // });
}

runAsyncMain(main);
