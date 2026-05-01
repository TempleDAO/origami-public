
import "@nomiclabs/hardhat-ethers";
import { encodedMulPrice, encodedOraclePrice, encodedOrigamiOraclePrice, encodedTokenizedBalanceSheetTokenPrice, impersonateAndFund2, mine, PriceType, RoundingMode, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { IOrigamiBundlerPluginTbsV2__factory, IOrigamiElevatedAccess__factory, TokenPrices } from "../../../../../typechain";
import { ContractInstances, IOpalVault } from "../../contract-addresses";
import { addAaveV3Adapter, addPluginAccess } from "../../../opal-utils";
import { ContractAddresses } from "../../contract-addresses/types";
import { network } from "hardhat";
import { Signer } from "ethers";
import { createSafeBatch, setTokenPriceFunctions, writeSafeTransactionsBatch } from "../../../safe-tx-builder";
import path from "path";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

function getEncodedMappings(opalVault: IOpalVault) {
  const usde_per_ptSusde = encodedOrigamiOraclePrice(
    ADDRS.ORACLES.PT_SUSDE_9APR2026_USDE,
    PriceType.SPOT_PRICE, 
    RoundingMode.ROUND_DOWN
  );
  const usd_per_usde = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.USDE_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDE_USD_ORACLE.STALENESS_THRESHOLD
  );

  return [
    {
      token: ADDRS.EXTERNAL.PENDLE.SUSDE_9APR2026.PT_TOKEN,
      fnCalldata: encodedMulPrice(
        usd_per_usde,
        usde_per_ptSusde,
      )
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

  const vaultSettings = DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_PLASMA_A;
  const opalVault = INSTANCES.VAULTS.OPAL_PT_SUSDE_PLASMA_A;
  const adapterImpl = INSTANCES.OPAL.ADAPTER_IMPLEMENTATIONS.AAVE_V3.V1;

  const collateralToken0 = INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN;
  const debtToken0 = INSTANCES.EXTERNAL.TETHER.USDT0_TOKEN;
  const emode0 = DEFAULT_SETTINGS.EXTERNAL.AAVE.PLASMA.EMODES["sUSDe Stablecoins"];
  const maxUrOnJoin0 = vaultSettings.MAX_UR_ON_JOIN["AAVE_V3.1: [sUSDe]/[USDT0]"];

  const collateralToken1 = INSTANCES.EXTERNAL.PENDLE.SUSDE_9APR2026.PT_TOKEN;
  const debtToken1 = INSTANCES.EXTERNAL.TETHER.USDT0_TOKEN;
  const emode1 = DEFAULT_SETTINGS.EXTERNAL.AAVE.PLASMA.EMODES.PT_sUSDe_9APR2026__Stablecoins;
  const maxUrOnJoin1 = vaultSettings.MAX_UR_ON_JOIN["AAVE_V3.1: [PT-sUSDE-9APR2026]/[USDT0]"];

  const aavePoolAddressProvider = ADDRS.EXTERNAL.AAVE.V3_PLASMA_POOL_ADDRESS_PROVIDER;
  const tokenPrices = INSTANCES.CORE.TOKEN_PRICES.V1;
  const requiredPlugins = [
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.AAVE_V3_PLASMA,
    ADDRS.BUNDLER.PLUGINS.FLASHLOAN.EULER,
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
    await addPluginAccess(owner, opalVault.MANAGER, requiredPlugins);

    const tbsPlugin = IOrigamiBundlerPluginTbsV2__factory.connect(ADDRS.BUNDLER.PLUGINS.TBS.V2, owner);
    await mine(tbsPlugin.trustVault(opalVault.TOKEN.address));

    mapTokenPricesBatch(tokenPrices, opalVault);

    await mine(opalVault.MANAGER.setPauser(ADDRS.CORE.MULTISIG, true));
    await mine(opalVault.MANAGER.setPauser(ADDRS.CORE.HYPERNATIVE.SYSTEM_WALLET, true));
  }
}

runAsyncMain(main);
