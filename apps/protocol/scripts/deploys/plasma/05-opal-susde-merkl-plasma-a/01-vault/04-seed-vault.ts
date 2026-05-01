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

const COLLATERAL0_WHALE = '0xdb3FaAD4436E2d133fdaB0788332845df9b0ABdF';

let OPAL_INSTANCES: OpalContracts;
let INSTANCES: ContractInstances;
let OWNER: Signer;

interface OpalContracts {
  VAULT: OpalVault;
  MANAGER: OpalManager;
  ASSET_TOKENS: IERC20Metadata[];
  ASSET_DECIMALS: number[];
  NUM_ASSETS: number;
  LIABILITY0_TOKEN: IERC20Metadata;
  LIABILITY0_DECIMALS: number;
  NUM_LIABILITIES: number;
  TOKEN_PRICES: TokenPrices;
}

const getContracts = async (vault: OpalVault): Promise<OpalContracts> => {
  const [manager, [assetTokens, liabilityTokens]] = await Promise.all([
    vault.manager(),
    vault.tokens(),
  ]);
  if (liabilityTokens.length != 1) console.warn("Can only handle 1 liability for now - using first one");

  const aTokens = assetTokens.map((at) => IERC20Metadata__factory.connect(at, OWNER));
  const dToken = IERC20Metadata__factory.connect(liabilityTokens[0], OWNER)
  const [aDecimals, dDecimals] = await Promise.all([
    Promise.all(aTokens.map((at) => at.decimals())),
    dToken.decimals(),
  ]);

  return {
    VAULT: vault,
    MANAGER: OpalManager__factory.connect(manager, OWNER),
    ASSET_TOKENS: aTokens,
    ASSET_DECIMALS: aDecimals,
    NUM_ASSETS: assetTokens.length,
    LIABILITY0_TOKEN: dToken,
    LIABILITY0_DECIMALS: dDecimals,
    NUM_LIABILITIES: liabilityTokens.length,
    TOKEN_PRICES: INSTANCES.CORE.TOKEN_PRICES.V1,
  };
}

async function encodedStartingSplit(
  asset0AmountBN: BigNumber,
  liability0AmountBN: BigNumber,
) {
  const numAdapters = (await OPAL_INSTANCES.MANAGER.adapters()).length;

  // For each adapter, need to encode the starting split
  // For now just assume one single adapter when seeding.
  // Only use the first asset balance in the first adapter - overlord will rebalance
  const startingSplit: IOpalManager.AssetsAndLiabilitiesStruct[] = [
    {
      assets: [
        asset0AmountBN,
        ...(Array(OPAL_INSTANCES.NUM_ASSETS-1).fill(0)),
      ],
      liabilities: [
        liability0AmountBN,
        ...(Array(OPAL_INSTANCES.NUM_LIABILITIES-1).fill(0)),
      ],
    }
  ];

  // For now, assume zero for the other adapters with zero assets and liabilities
  for (let i = 1; i < numAdapters; i++) {
    startingSplit.push({
      assets: Array(OPAL_INSTANCES.NUM_ASSETS).fill(0),
      liabilities: Array(OPAL_INSTANCES.NUM_LIABILITIES).fill(0),
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
  asset0AmountBN: BigNumber,
  liability0AmountBN: BigNumber,
  sharesToMintBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = OPAL_INSTANCES.VAULT;
  const asset0Token = OPAL_INSTANCES.ASSET_TOKENS[0];
  const liability0Token = OPAL_INSTANCES.LIABILITY0_TOKEN;
  const vaultDecimals = 18;

  await mine(asset0Token.approve(vault.address, asset0AmountBN));

  await mine(
    vault.seed(
      [
        asset0AmountBN,
        ...(Array(OPAL_INSTANCES.NUM_ASSETS-1).fill(0)),
      ],
      [
        liability0AmountBN,
        ...(Array(OPAL_INSTANCES.NUM_LIABILITIES-1).fill(0)),
      ],
      sharesToMintBN,
      accountAddress,
      maxSupply,
      await encodedStartingSplit(asset0AmountBN, liability0AmountBN),
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tAccount balance of liabilities:", ethers.utils.formatUnits(
    await liability0Token.balanceOf(accountAddress),
    OPAL_INSTANCES.LIABILITY0_DECIMALS,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
  
  const sharePrices = await vault.convertFromShares(ethers.utils.parseUnits("1", vaultDecimals));
  sharePrices.assets.forEach((assetAmt, i) => {
    console.log(`\tasset[${i}] share price: ${ethers.utils.formatUnits(
      assetAmt,
      OPAL_INSTANCES.ASSET_DECIMALS[i],
    )}`);
  });
  console.log("\tliabilities[0] share price:", ethers.utils.formatUnits(
    sharePrices.liabilities[0],
    OPAL_INSTANCES.LIABILITY0_DECIMALS,
  ));
}

async function seedDepositSafeBatch(
  asset0AmountBN: BigNumber,
  liability0AmountBN: BigNumber,
  sharesToMintBN: BigNumber,
  receiverAddress: string,
  maxSupply: BigNumber,
) {
  const vault = OPAL_INSTANCES.VAULT;
  const assetTokens = OPAL_INSTANCES.ASSET_TOKENS;

  // Only use the first asset/liability and pad the rest with zero's
  const batch = createSafeBatch(
    [
      approve(assetTokens[0], vault.address, asset0AmountBN),
      seedTokenizedBalanceSheet(
        vault,
        [
          asset0AmountBN,
          ...(Array(OPAL_INSTANCES.NUM_ASSETS-1).fill(0)),
        ],
        [
          liability0AmountBN,
          ...(Array(OPAL_INSTANCES.NUM_LIABILITIES-1).fill(0)),
        ],
        sharesToMintBN,
        receiverAddress,
        maxSupply,
        await encodedStartingSplit(asset0AmountBN, liability0AmountBN),
      ),
    ]
  );

  const filename = path.join(__dirname, "../02-seed-vault.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function dumpPrices(tokenPrices: TokenPrices) {
  const [liabilityPriceUsd, vaultPriceUsd, ...assetPricesUsd] = await tokenPrices.tokenPrices([
    OPAL_INSTANCES.LIABILITY0_TOKEN.address,
    OPAL_INSTANCES.VAULT.address,
    ...OPAL_INSTANCES.ASSET_TOKENS.map((at) => at.address),
  ]);

  for (const [i, price] of assetPricesUsd.entries()) {
    console.log(`\t$${await OPAL_INSTANCES.ASSET_TOKENS[i].symbol()}:`, ethers.utils.formatUnits(price, 30));
  }
  console.log(`\t$${await OPAL_INSTANCES.LIABILITY0_TOKEN.symbol()}:`, ethers.utils.formatUnits(liabilityPriceUsd, 30));
  console.log(`\t$${await OPAL_INSTANCES.VAULT.symbol()}:`, ethers.utils.formatUnits(vaultPriceUsd, 30));
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

async function calcSeed(asset0Seed: BigNumber, targetLeverage: BigNumber) {
  const [asset0PriceUsd, liability0PriceUsd] = await OPAL_INSTANCES.TOKEN_PRICES.tokenPrices([
    OPAL_INSTANCES.ASSET_TOKENS[0].address,
    OPAL_INSTANCES.LIABILITY0_TOKEN.address,
  ]);
  
  const seedDebt = scaleTo(
    asset0Seed.mul(targetLeverage).mul(asset0PriceUsd).div(liability0PriceUsd),
    18 + OPAL_INSTANCES.ASSET_DECIMALS[0],
    OPAL_INSTANCES.LIABILITY0_DECIMALS,
  );

  const seedShares = (
    scaleTo(asset0Seed, OPAL_INSTANCES.ASSET_DECIMALS[0], 18)
      .mul(asset0PriceUsd)
      .div(liability0PriceUsd)
  ).sub(
    scaleTo(seedDebt, OPAL_INSTANCES.LIABILITY0_DECIMALS, 18)
  );

  return {
    seedDebt,
    seedShares
  };
}

async function main() {
  ({owner: OWNER, INSTANCES} = await getDeployContext(__dirname));
  OPAL_INSTANCES = await getContracts(INSTANCES.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.TOKEN);
  const vaultSettings = DEFAULT_SETTINGS.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A;

  console.log("\nToken Prices Before Seed:");
  await dumpPrices(INSTANCES.CORE.TOKEN_PRICES.V1);

  const {seedDebt, seedShares}  = await calcSeed(
    vaultSettings.SEED_COLLATERAL0_AMOUNT, 
    vaultSettings.TARGET_LEVERAGE
  );
  console.log("Seed Debt:", ethers.utils.formatUnits(seedDebt, OPAL_INSTANCES.LIABILITY0_DECIMALS));
  console.log("Seed Shares:", ethers.utils.formatEther(seedShares));

  // Localhost only
  if (network.name === 'localhost') {
    const signer = await impersonateAndFund2(COLLATERAL0_WHALE);
    await mine(OPAL_INSTANCES.ASSET_TOKENS[0].connect(signer).transfer(
      OWNER.getAddress(), 
      vaultSettings.SEED_COLLATERAL0_AMOUNT
    ));

    await seedDepositDirect(
      vaultSettings.SEED_COLLATERAL0_AMOUNT, 
      seedDebt, 
      seedShares, 
      await OWNER.getAddress(),
      vaultSettings.MAX_TOTAL_SUPPLY
    );
  } else {
    await seedDepositDirect(
      vaultSettings.SEED_COLLATERAL0_AMOUNT, 
      seedDebt, 
      seedShares, 
      await OWNER.getAddress(), 
      vaultSettings.MAX_TOTAL_SUPPLY
    );
  }

  console.log("\nToken Prices After Seed:");
  await dumpPrices(INSTANCES.CORE.TOKEN_PRICES.V1);
}

runAsyncMain(main);
