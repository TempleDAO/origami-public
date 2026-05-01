
import "@nomiclabs/hardhat-ethers";
import { encodedMulPrice, encodedOraclePrice, encodedOrigamiOraclePrice, encodedTokenizedBalanceSheetTokenPrice, impersonateAndFund2, mine, PriceType, RoundingMode, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { IOrigamiBundlerPluginTbsV2__factory, IOrigamiElevatedAccess__factory, TokenPrices } from "../../../../../typechain";
import { ContractInstances, IOpalVault } from "../../contract-addresses";
import { addAaveV3Adapter, addPluginAccess, addPluginAccessBatch } from "../../../opal-utils";
import { ContractAddresses } from "../../contract-addresses/types";
import { network } from "hardhat";
import { Signer } from "ethers";
import { createSafeBatch, setTbsPluginTrusted, setTokenPriceFunctions, writeSafeTransactionsBatch } from "../../../safe-tx-builder";
import path from "path";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

function getEncodedMappings(opalVault: IOpalVault) {
  return [
    {
      token: ADDRS.EXTERNAL.TETHER.USDT_TOKEN,
      fnCalldata: encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.USDT_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDT_USD_ORACLE.STALENESS_THRESHOLD
      ),
    },
    {
      token: opalVault.TOKEN.address,
      fnCalldata: encodedTokenizedBalanceSheetTokenPrice(opalVault.TOKEN.address),
    },
  ];
}

async function mapTokenPrices(tokenPrices: TokenPrices, opalVault: IOpalVault) {
  await mine(tokenPrices.setTokenPriceFunctions(getEncodedMappings(opalVault)));
}

function mapTokenPricesBatch(contract: TokenPrices, opalVault: IOpalVault) {
  const batch = createSafeBatch(
    [
      setTokenPriceFunctions(contract, getEncodedMappings(opalVault)),
    ],
  );

  const filename = path.join(__dirname, "../01-map-token-prices.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  let owner: Signer;
  ({ owner, ADDRS, INSTANCES } = await getDeployContext(__dirname));

  const vaultSettings = DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_B;
  const opalVault = INSTANCES.VAULTS.OPAL_PT_SUSDE_B;
  const adapterImpl = INSTANCES.OPAL.ADAPTER_IMPLEMENTATIONS.AAVE_V3.V1;

  const collateralToken0 = INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN;
  const debtToken0 = INSTANCES.EXTERNAL.TETHER.USDT_TOKEN;
  const emode0 = DEFAULT_SETTINGS.EXTERNAL.AAVE.CORE.EMODES["PT-sUSDe Stablecoins Nov 2025"];
  const maxUrOnJoin0 = vaultSettings.MAX_UR_ON_JOIN["AAVE: sUSDe / USDT"];

  const collateralToken1 = INSTANCES.EXTERNAL.PENDLE.SUSDE_7MAY2026.PT_TOKEN;
  const debtToken1 = INSTANCES.EXTERNAL.TETHER.USDT_TOKEN;
  const emode1 = DEFAULT_SETTINGS.EXTERNAL.AAVE.CORE.EMODES.PT_sUSDe_7MAY2026__Stablecoins;
  const maxUrOnJoin1 = vaultSettings.MAX_UR_ON_JOIN["AAVE: PT-sUSDe-7MAY2026 / USDT"];

  const aavePoolAddressProvider = ADDRS.EXTERNAL.AAVE.V3_MAINNET_POOL_ADDRESS_PROVIDER;
  const tokenPrices = INSTANCES.CORE.TOKEN_PRICES.V4;
  const requiredPlugins = [
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.MORPHO, // fee free
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.SPARK, // fee free
    ADDRS.BUNDLER.PLUGINS.SWAP.PENDLE,
    ADDRS.BUNDLER.PLUGINS.SWAP.KYBER,
  ];
  const adapterOwner = ADDRS.CORE.MULTISIG;

  await mine(opalVault.TOKEN.setManager(opalVault.MANAGER.address));

  await addAaveV3Adapter(
    opalVault.MANAGER,
    adapterImpl,
    [collateralToken0],
    debtToken0,
    aavePoolAddressProvider,
    adapterOwner,
    emode0,
    maxUrOnJoin0,
  );
  await addAaveV3Adapter(
    opalVault.MANAGER,
    adapterImpl,
    [collateralToken1],
    debtToken1,
    aavePoolAddressProvider,
    adapterOwner,
    emode1,
    maxUrOnJoin1,
  );

  if (vaultSettings.JOIN_FEE_BPS > 0 || vaultSettings.EXIT_FEE_BPS > 0) {
    await mine(opalVault.MANAGER.setFees(
      vaultSettings.JOIN_FEE_BPS,
      vaultSettings.EXIT_FEE_BPS
    ));
  }

  if (network.name == 'localhost') {
    // Assume the first owner is the owner for all
    const firstPlugin = IOrigamiElevatedAccess__factory.connect(requiredPlugins[0], owner);
    const pluginOwner = await impersonateAndFund2(await firstPlugin.owner());
    await addPluginAccess(pluginOwner, opalVault.MANAGER, requiredPlugins);

    const tbsPlugin = IOrigamiBundlerPluginTbsV2__factory.connect(ADDRS.BUNDLER.PLUGINS.TBS.V2, pluginOwner);
    await mine(tbsPlugin.trustVault(opalVault.TOKEN.address));

    const tokenPricesOwner = await impersonateAndFund2(await tokenPrices.owner());
    await mapTokenPrices(tokenPrices.connect(tokenPricesOwner), opalVault);

    await mine(opalVault.MANAGER.setPauser(ADDRS.CORE.MULTISIG, true));
    await mine(opalVault.MANAGER.setPauser(ADDRS.CORE.HYPERNATIVE.SYSTEM_WALLET, true));
  } else {
    {
      const batchTxs = await addPluginAccessBatch(
        owner,
        opalVault.MANAGER,
        requiredPlugins
      );

      const tbsPlugin = IOrigamiBundlerPluginTbsV2__factory.connect(ADDRS.BUNDLER.PLUGINS.TBS.V2, owner);
      batchTxs.push(setTbsPluginTrusted(tbsPlugin, opalVault.TOKEN));

      const filename = path.join(__dirname, "../01-approve-plugins.json");
      writeSafeTransactionsBatch(createSafeBatch(batchTxs), filename);
      console.log(`Wrote Safe tx's batch to: ${filename}`);
    }

    mapTokenPricesBatch(tokenPrices, opalVault);

    await mine(opalVault.MANAGER.setPauser(ADDRS.CORE.MULTISIG, true));
    await mine(opalVault.MANAGER.setPauser(ADDRS.CORE.HYPERNATIVE.SYSTEM_WALLET, true));
  }
}

runAsyncMain(main);
