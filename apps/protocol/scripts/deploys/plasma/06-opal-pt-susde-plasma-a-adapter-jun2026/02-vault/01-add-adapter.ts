
import "@nomiclabs/hardhat-ethers";
import { encodedMulPrice, encodedOraclePrice, encodedOrigamiOraclePrice, impersonateAndFund2, mine, PriceType, RoundingMode, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { TokenPrices } from "../../../../../typechain";
import { ContractInstances } from "../../contract-addresses";
import { addAaveV3Adapter, addAaveV3AdapterBatch } from "../../../opal-utils";
import { ContractAddresses } from "../../contract-addresses/types";
import { network } from "hardhat";
import { createSafeBatch, setTokenPriceFunctions, writeSafeTransactionsBatch } from "../../../safe-tx-builder";
import path from "path";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

function getEncodedMappings() {
  const usde_per_ptSusde = encodedOrigamiOraclePrice(
    ADDRS.ORACLES.PT_SUSDE_18JUN2026_USDE,
    PriceType.SPOT_PRICE, 
    RoundingMode.ROUND_DOWN
  );
  const usd_per_usde = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.USDE_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDE_USD_ORACLE.STALENESS_THRESHOLD
  );

  return [
    {
      token: ADDRS.EXTERNAL.PENDLE.SUSDE_18JUN2026.PT_TOKEN,
      fnCalldata: encodedMulPrice(
        usd_per_usde,
        usde_per_ptSusde,
      )
    },
  ];
}

async function mapTokenPrices(tokenPrices: TokenPrices) {
  await mine(tokenPrices.setTokenPriceFunctions(getEncodedMappings()));
}

function mapTokenPricesBatch(contract: TokenPrices) {
  const batch = createSafeBatch(
    [
      setTokenPriceFunctions(contract, getEncodedMappings()),
    ],
  );

  const filename = path.join(__dirname, "../01-map-token-prices.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  ({ ADDRS, INSTANCES } = await getDeployContext(__dirname));

  const vaultSettings = DEFAULT_SETTINGS.VAULTS.OPAL_PT_SUSDE_PLASMA_A;
  const opalVault = INSTANCES.VAULTS.OPAL_PT_SUSDE_PLASMA_A;
  const adapterImpl = INSTANCES.OPAL.ADAPTER_IMPLEMENTATIONS.AAVE_V3.V1;

  const collateralToken = INSTANCES.EXTERNAL.PENDLE.SUSDE_18JUN2026.PT_TOKEN;
  const debtToken = INSTANCES.EXTERNAL.TETHER.USDT0_TOKEN;
  const emode = DEFAULT_SETTINGS.EXTERNAL.AAVE.PLASMA.EMODES.PT_sUSDE_18JUN2026__Stablecoins;
  const maxUrOnJoin = vaultSettings.MAX_UR_ON_JOIN["AAVE_V3.1: [PT-sUSDE-18JUN2026]/[USDT0]"];

  const aavePoolAddressProvider = ADDRS.EXTERNAL.AAVE.V3_PLASMA_POOL_ADDRESS_PROVIDER;
  const tokenPrices = INSTANCES.CORE.TOKEN_PRICES.V1;
  const adapterOwner = ADDRS.CORE.MULTISIG;

  if (network.name == 'localhost') {
    const managerOwner = await impersonateAndFund2(await opalVault.MANAGER.owner());
    await addAaveV3Adapter(
      opalVault.MANAGER.connect(managerOwner),
      adapterImpl,
      [collateralToken],
      debtToken,
      aavePoolAddressProvider,
      adapterOwner,
      emode,
      maxUrOnJoin,
    );
    const tokenPricesOwner = await impersonateAndFund2(await tokenPrices.owner());
    await mapTokenPrices(tokenPrices.connect(tokenPricesOwner));
  } else {
    await addAaveV3AdapterBatch(
      path.join(__dirname, "../02-add-adapter.json"),
      opalVault.MANAGER,
      adapterImpl,
      [collateralToken],
      debtToken,
      aavePoolAddressProvider,
      adapterOwner,
      emode,
      maxUrOnJoin,
    )
    mapTokenPricesBatch(tokenPrices);
  }
}

runAsyncMain(main);
