import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';
import { BigNumber, Signer } from 'ethers';
import { approve, createSafeBatch, seedTokenizedBalanceSheet, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { IERC20Metadata, IERC20Metadata__factory, IOpalManager, OpalManager, OpalManager__factory, OpalVault, TokenPrices } from '../../../../../typechain';
import { ContractInstances } from '../../contract-addresses';

const COLLATERAL_WHALE = '0xdb3FaAD4436E2d133fdaB0788332845df9b0ABdF';

let OPAL_INSTANCES: OpalContracts;
let INSTANCES: ContractInstances;
let OWNER: Signer;

interface OpalContracts {
  VAULT: OpalVault;
  MANAGER: OpalManager;
  ASSET_TOKEN: IERC20Metadata;
  ASSET_DECIMALS: number;
  NUM_ASSETS: number;
  LIABILITY_TOKEN: IERC20Metadata;
  LIABILITY_DECIMALS: number;
  NUM_LIABILITIES: number;
  TOKEN_PRICES: TokenPrices;
}

const getContracts = async (vault: OpalVault): Promise<OpalContracts> => {
  const [manager, [assetTokens, liabilityTokens]] = await Promise.all([
    vault.manager(),
    vault.tokens(),
  ]);
  if (assetTokens.length != 1) console.warn("Can only handle 1 asset for now - using first one");
  if (liabilityTokens.length != 1) console.warn("Can only handle 1 liability for now - using first one");

  const aToken = IERC20Metadata__factory.connect(assetTokens[0], OWNER);
  const dToken = IERC20Metadata__factory.connect(liabilityTokens[0], OWNER)
  const [aDecimals, dDecimals] = await Promise.all([
    await aToken.decimals(),
    await dToken.decimals(),
  ]);

  return {
    VAULT: vault,
    MANAGER: OpalManager__factory.connect(manager, OWNER),
    ASSET_TOKEN: aToken,
    ASSET_DECIMALS: aDecimals,
    NUM_ASSETS: assetTokens.length,
    LIABILITY_TOKEN: dToken,
    LIABILITY_DECIMALS: dDecimals,
    NUM_LIABILITIES: liabilityTokens.length,
    TOKEN_PRICES: INSTANCES.CORE.TOKEN_PRICES.V1,
  };
}

async function encodedStartingSplit(
  assetAmountBN: BigNumber,
  liabilityAmountBN: BigNumber,
) {
  const numAdapters = (await OPAL_INSTANCES.MANAGER.adapters()).length;

  // For each adapter, need to encode the starting split
  // For now just assume one single adapter when seeding.
  const startingSplit: IOpalManager.AssetsAndLiabilitiesStruct[] = [
    {
      assets: [assetAmountBN],
      liabilities: [liabilityAmountBN],
    }
  ];

  // For now, assume zero for the other adapters with zero assets and liabilities
  for (let i = 1; i < numAdapters; i++) {
    startingSplit.push({
      assets: [0],
      liabilities: [0],
    })
  }

  return ethers.utils.defaultAbiCoder.encode(
    [
      "tuple(uint256[] assets, uint256[] liabilities)[]"
    ],
    [startingSplit]
  );
}

async function seedDepositDirect(
  assetAmountBN: BigNumber,
  liabilityAmountBN: BigNumber,
  sharesToMintBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = OPAL_INSTANCES.VAULT;
  const assetToken = OPAL_INSTANCES.ASSET_TOKEN;
  const liabilitiesToken = OPAL_INSTANCES.LIABILITY_TOKEN;
  const vaultDecimals = 18;

  await mine(
    assetToken.approve(vault.address, assetAmountBN)
  );

  await mine(
    vault.seed(
      [
        assetAmountBN,
        ...(Array(OPAL_INSTANCES.NUM_ASSETS-1).fill(0)),
      ],
      [
        liabilityAmountBN,
        ...(Array(OPAL_INSTANCES.NUM_LIABILITIES-1).fill(0)),
      ],
      sharesToMintBN,
      accountAddress,
      maxSupply,
      await encodedStartingSplit(assetAmountBN, liabilityAmountBN),
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tAccount balance of liabilities:", ethers.utils.formatUnits(
    await liabilitiesToken.balanceOf(accountAddress),
    OPAL_INSTANCES.LIABILITY_DECIMALS,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
  
  const sharePrices = await vault.convertFromShares(ethers.utils.parseUnits("1", vaultDecimals));
  console.log("\tasset[0] share price:", ethers.utils.formatUnits(
    sharePrices.assets[0],
    OPAL_INSTANCES.ASSET_DECIMALS,
  ));
  console.log("\tliabilities[0] share price:", ethers.utils.formatUnits(
    sharePrices.liabilities[0],
    OPAL_INSTANCES.LIABILITY_DECIMALS,
  ));
}

async function seedDepositSafeBatch(
  assetAmountBN: BigNumber,
  liabilityAmountBN: BigNumber,
  sharesToMintBN: BigNumber,
  receiverAddress: string,
  maxSupply: BigNumber,
) {
  const vault = OPAL_INSTANCES.VAULT;
  const assetToken = OPAL_INSTANCES.ASSET_TOKEN;

  // Only use the first asset/liability and pad the rest with zero's
  const batch = createSafeBatch(
    [
      approve(assetToken, vault.address, assetAmountBN),
      seedTokenizedBalanceSheet(
        vault,
        [
          assetAmountBN,
          ...(Array(OPAL_INSTANCES.NUM_ASSETS-1).fill(0)),
        ],
        [
          liabilityAmountBN,
          ...(Array(OPAL_INSTANCES.NUM_LIABILITIES-1).fill(0)),
        ],
        sharesToMintBN,
        receiverAddress,
        maxSupply,
        await encodedStartingSplit(assetAmountBN, liabilityAmountBN),
      ),
    ]
  );

  const filename = path.join(__dirname, "../02-seed-vault.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function dumpPrices(tokenPrices: TokenPrices) {
  const prices = await tokenPrices.tokenPrices([
    OPAL_INSTANCES.ASSET_TOKEN.address,
    OPAL_INSTANCES.LIABILITY_TOKEN.address,
    OPAL_INSTANCES.VAULT.address,
  ]);
  console.log(`\t$${await OPAL_INSTANCES.ASSET_TOKEN.symbol()}:`, ethers.utils.formatUnits(prices[0], 30));
  console.log(`\t$${await OPAL_INSTANCES.LIABILITY_TOKEN.symbol()}:`, ethers.utils.formatUnits(prices[1], 30));
  console.log(`\t$${await OPAL_INSTANCES.VAULT.symbol()}:`, ethers.utils.formatUnits(prices[2], 30));
}

function scaleTo(n: BigNumber, existingDecimals: number, newDecimals: number) {
  const delta = newDecimals - existingDecimals;
  if (delta > 0) {
    return n.mul(ethers.utils.parseUnits("1", delta));
  } else if (delta < 0) {
    return n.div(ethers.utils.parseUnits("1", -delta));
  }
  return n;
}

async function calcSeed(assetSeed: BigNumber, targetLeverage: BigNumber) {
  const [assetPriceUsd, liabilityPriceUsd] = await OPAL_INSTANCES.TOKEN_PRICES.tokenPrices([
    OPAL_INSTANCES.ASSET_TOKEN.address,
    OPAL_INSTANCES.LIABILITY_TOKEN.address,
  ]);

  const seedDebt = scaleTo(
    assetSeed.mul(targetLeverage).mul(assetPriceUsd).div(liabilityPriceUsd),
    18 + OPAL_INSTANCES.ASSET_DECIMALS,
    OPAL_INSTANCES.LIABILITY_DECIMALS,
  );

  const seedShares = (
    scaleTo(assetSeed, OPAL_INSTANCES.ASSET_DECIMALS, 18)
      .mul(assetPriceUsd)
      .div(liabilityPriceUsd)
  ).sub(
    scaleTo(seedDebt, OPAL_INSTANCES.LIABILITY_DECIMALS, 18)
  );

  return {
    seedDebt,
    seedShares
  };
}

async function main() {
  ({owner: OWNER, INSTANCES} = await getDeployContext(__dirname));
  OPAL_INSTANCES = await getContracts(INSTANCES.VAULTS.OPAL_PT_SUSDE_PLASMA_A.TOKEN);
  const vaultSettings = DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_PLASMA_A;

  console.log("\nToken Prices Before Seed:");
  await dumpPrices(INSTANCES.CORE.TOKEN_PRICES.V1);

  const {seedDebt, seedShares}  = await calcSeed(
    vaultSettings.SEED_COLLATERAL_AMOUNT, 
    vaultSettings.TARGET_LEVERAGE
  );
  console.log("Seed Debt:", ethers.utils.formatUnits(seedDebt, OPAL_INSTANCES.LIABILITY_DECIMALS));
  console.log("Seed Shares:", ethers.utils.formatEther(seedShares));

  // Localhost only
  if (network.name === 'localhost') {
    const signer = await impersonateAndFund2(COLLATERAL_WHALE);
    await mine(OPAL_INSTANCES.ASSET_TOKEN.connect(signer).transfer(
      OWNER.getAddress(), 
      vaultSettings.SEED_COLLATERAL_AMOUNT
    ));

    await seedDepositDirect(
      vaultSettings.SEED_COLLATERAL_AMOUNT, 
      seedDebt, 
      seedShares, 
      await OWNER.getAddress(),
      vaultSettings.MAX_TOTAL_SUPPLY
    );
  } else {

    await seedDepositDirect(
      vaultSettings.SEED_COLLATERAL_AMOUNT, 
      seedDebt, 
      seedShares, 
      await OWNER.getAddress(), 
      vaultSettings.MAX_TOTAL_SUPPLY
    );

    // await seedDepositSafeBatch(
    //   vaultSettings.SEED_COLLATERAL_AMOUNT, 
    //   seedDebt, 
    //   seedShares, 
    //   ADDRS.CORE.MULTISIG, 
    //   vaultSettings.MAX_TOTAL_SUPPLY
    // );
  }

  console.log("\nToken Prices After Seed:");
  await dumpPrices(INSTANCES.CORE.TOKEN_PRICES.V1);
}

runAsyncMain(main);
