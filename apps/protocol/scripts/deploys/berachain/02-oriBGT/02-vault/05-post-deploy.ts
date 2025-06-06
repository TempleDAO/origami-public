import "@nomiclabs/hardhat-ethers";
import {
  encodedErc4626TokenPrice,
  encodedKodiakV3Price,
  encodedMulPrice,
  encodedOraclePrice,
  encodedTokenPrice,
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
} from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { ContractAddresses } from "../../contract-addresses/types";
import { TokenPrices } from "../../../../../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getDeployContext } from "../../deploy-context";
import { DEFAULT_SETTINGS } from "../../default-settings";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => ({
  honeyToUsd: encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.HONEY_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.HONEY_USD_ORACLE.STALENESS_THRESHOLD
  ),

  usdcToUsd: encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.USDC_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.USDC_USD_ORACLE.STALENESS_THRESHOLD
  ),

  beraToUsd: encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.BERA_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WBERA_USD_ORACLE.STALENESS_THRESHOLD
  ),

  wBeraToUsd: encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.BERA_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WBERA_USD_ORACLE.STALENESS_THRESHOLD
  ),

  // WBERA/USD * iBGT/WBERA
  iBgtToUsd: encodedMulPrice(
    encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN),
    encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.WBERA_IBGT_V3, false)
  ),

  oriBgtToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.ORIBGT.TOKEN),
  boycoUsdcAToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.BOYCO_USDC_A.TOKEN),
});

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();
  await mine(
    contract.setTokenPriceFunction(
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      encodedPrices.honeyToUsd
    )
  );
  await mine(
    contract.setTokenPriceFunction(
      ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      encodedPrices.usdcToUsd
    )
  );
  await mine(
    contract.setTokenPriceFunction(
      ZERO_ADDRESS,
      encodedPrices.beraToUsd
    )
  );
  await mine(
    contract.setTokenPriceFunction(
      ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
      encodedPrices.wBeraToUsd
    )
  );
  await mine(
    contract.setTokenPriceFunction(
      ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
      encodedPrices.iBgtToUsd
    )
  );
  await mine(
    contract.setTokenPriceFunction(
      ADDRS.VAULTS.ORIBGT.TOKEN,
      encodedPrices.oriBgtToUsd
    )
  );
  await mine(
    contract.setTokenPriceFunction(
      ADDRS.VAULTS.BOYCO_USDC_A.TOKEN,
      encodedPrices.boycoUsdcAToUsd
    )
  );
}

async function setupPrices() {
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V4);
}

async function main() {
  let owner: SignerWithAddress;
  ({ owner, ADDRS, INSTANCES } = await getDeployContext(__dirname));

  // link token and manager
  await mine(
    INSTANCES.VAULTS.ORIBGT.TOKEN.setManager(ADDRS.VAULTS.ORIBGT.MANAGER)
  );

  await mine(INSTANCES.VAULTS.ORIBGT.SWAPPER.whitelistRouter(
    ADDRS.EXTERNAL.OOGABOOGA.ROUTER, true
  ));

  await setupPrices();
}

runAsyncMain(main);
