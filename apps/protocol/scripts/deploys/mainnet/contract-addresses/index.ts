import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  OrigamiVolatileChainlinkOracle, OrigamiVolatileChainlinkOracle__factory,
  OrigamiStableChainlinkOracle, OrigamiStableChainlinkOracle__factory,
  OrigamiLovToken, OrigamiLovToken__factory,
  OrigamiLovTokenMorphoManager, OrigamiLovTokenMorphoManager__factory,
  OrigamiMorphoBorrowAndLend, OrigamiMorphoBorrowAndLend__factory,
  OrigamiErc4626Oracle, OrigamiErc4626Oracle__factory,
  OrigamiErc4626AndDexAggregatorSwapper, OrigamiErc4626AndDexAggregatorSwapper__factory,
  IMorpho, IMorpho__factory,
  OrigamiDexAggregatorSwapper,
  OrigamiDexAggregatorSwapper__factory,
  OrigamiEtherFiEthToEthOracle,
  OrigamiRenzoEthToEthOracle,
  OrigamiEtherFiEthToEthOracle__factory,
  OrigamiRenzoEthToEthOracle__factory,
  IRenzoRestakeManager,
  IEtherFiLiquidityPool,
  IEtherFiLiquidityPool__factory,
  IRenzoRestakeManager__factory,
  OrigamiWstEthToEthOracle,
  OrigamiWstEthToEthOracle__factory,
  OrigamiAaveV3FlashLoanProvider,
  OrigamiAaveV3BorrowAndLend,
  OrigamiLovTokenFlashAndBorrowManager,
  OrigamiAaveV3FlashLoanProvider__factory,
  OrigamiAaveV3BorrowAndLend__factory,
  OrigamiLovTokenFlashAndBorrowManager__factory,
  IPoolAddressesProvider, IPoolAddressesProvider__factory,
  OrigamiCrossRateOracle,
  OrigamiCrossRateOracle__factory,
  OrigamiPendlePtToAssetOracle,
  OrigamiPendlePtToAssetOracle__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  OrigamiFixedPriceOracle,
  OrigamiVolatileCurveEmaOracle,
  OrigamiVolatileCurveEmaOracle__factory,
  OrigamiFixedPriceOracle__factory,
  OrigamiCowSwapper,
  OrigamiCowSwapper__factory,
  OrigamiSuperSavingsUsdsManager, OrigamiSuperSavingsUsdsManager__factory,
  OrigamiDelegated4626Vault, OrigamiDelegated4626Vault__factory,
  OrigamiScaledOracle,
  OrigamiScaledOracle__factory,
  OrigamiLovTokenMorphoManagerMarketAL,
  OrigamiLovTokenMorphoManagerMarketAL__factory,
  OrigamiHOhmVault,
  OrigamiHOhmManager,
  OrigamiSwapperWithCallback,
  OrigamiTokenTeleporter,
  OrigamiHOhmVault__factory,
  OrigamiHOhmManager__factory,
  OrigamiSwapperWithCallback__factory,
  OrigamiTokenTeleporter__factory,
  IMonoCooler,
  IMonoCooler__factory,
  OrigamiCoolerMigrator,
  OrigamiCoolerMigrator__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as MAINNET_CONTRACTS } from "./mainnet";
import { IERC4626 } from "../../../../typechain/@openzeppelin/contracts/interfaces";
import { IERC4626__factory } from "../../../../typechain/factories/@openzeppelin/contracts/interfaces";

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "mainnet" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'mainnet') {
    return MAINNET_CONTRACTS;
  } else if (network.name === 'localhost') {
    return MAINNET_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'mainnet') {
    return MAINNET_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(MAINNET_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

interface IType {
  TOKEN: OrigamiLovToken;
};

interface IMorphoType extends IType {
  MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
  MANAGER: OrigamiLovTokenMorphoManager;
}

interface IMorphoMarketALType extends IType {
  MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
  MANAGER: OrigamiLovTokenMorphoManagerMarketAL;
}

interface ISparkType extends IType {
  SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend;
  MANAGER: OrigamiLovTokenFlashAndBorrowManager;
}

interface IZeroLendType extends IType {
  ZEROLEND_BORROW_LEND: OrigamiAaveV3BorrowAndLend;
  MANAGER: OrigamiLovTokenFlashAndBorrowManager;
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V1: TokenPrices;
      V2: TokenPrices;
      V3: TokenPrices;
      V4: TokenPrices;
    };
  };
  ORACLES: {
    USDE_DAI: OrigamiStableChainlinkOracle;
    SUSDE_DAI: OrigamiErc4626Oracle;
    WEETH_WETH: OrigamiEtherFiEthToEthOracle;
    EZETH_WETH: OrigamiRenzoEthToEthOracle;
    STETH_WETH: OrigamiStableChainlinkOracle;
    WSTETH_WETH: OrigamiWstEthToEthOracle;
    WOETH_WETH: OrigamiErc4626Oracle;
    WETH_DAI: OrigamiVolatileChainlinkOracle;
    WBTC_DAI: OrigamiVolatileChainlinkOracle;
    WETH_WBTC: OrigamiVolatileChainlinkOracle;
    DAI_USD: OrigamiStableChainlinkOracle;
    SDAI_DAI: OrigamiErc4626Oracle;
    WETH_SDAI: OrigamiCrossRateOracle;
    WBTC_SDAI: OrigamiCrossRateOracle;
    PT_SUSDE_OCT24_USDE: OrigamiPendlePtToAssetOracle;
    PT_SUSDE_OCT24_DAI: OrigamiCrossRateOracle;
    PT_SUSDE_MAR_2025_USDE: OrigamiPendlePtToAssetOracle;
    PT_SUSDE_MAR_2025_DAI: OrigamiCrossRateOracle;
    PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY: OrigamiVolatileChainlinkOracle;
    PT_SUSDE_MAR_2025_DAI_WITH_DISCOUNT_TO_MATURITY: OrigamiScaledOracle;
    PT_SUSDE_MAY_2025_USDE: OrigamiPendlePtToAssetOracle;
    PT_SUSDE_MAY_2025_DAI: OrigamiCrossRateOracle;
    PT_SUSDE_MAY_2025_DISCOUNT_TO_MATURITY: OrigamiVolatileChainlinkOracle;
    PT_SUSDE_MAY_2025_DAI_WITH_DISCOUNT_TO_MATURITY: OrigamiScaledOracle;
    MKR_DAI: OrigamiVolatileChainlinkOracle;
    AAVE_USDC: OrigamiVolatileChainlinkOracle;
    SDAI_USDC: OrigamiErc4626Oracle;
    USD0pp_USD0: OrigamiVolatileCurveEmaOracle;
    USD0pp_USDC_PEGGED: OrigamiFixedPriceOracle;
    USD0pp_USDC_FLOOR_PRICE: OrigamiVolatileChainlinkOracle;
    USD0pp_USDC_MARKET_PRICE: OrigamiVolatileChainlinkOracle;
    USD0pp_MORPHO_TO_MARKET_CONVERSION: OrigamiCrossRateOracle;
    USD0_USDC: OrigamiVolatileCurveEmaOracle;
    RSWETH_WETH: OrigamiVolatileChainlinkOracle;
    PT_EBTC_DEC24_EBTC: OrigamiPendlePtToAssetOracle;
    PT_CORN_LBTC_DEC24_LBTC: OrigamiPendlePtToAssetOracle;
    WETH_CBBTC: OrigamiVolatileChainlinkOracle;
    PT_USD0pp_MAR_2025_USD0pp: OrigamiPendlePtToAssetOracle;
    PT_USD0pp_MAR_2025_USDC_PEGGED: OrigamiCrossRateOracle;
    SKY_MKR: OrigamiFixedPriceOracle;
    SKY_USDS: OrigamiCrossRateOracle;
    PT_LBTC_MAR_2025_LBTC: OrigamiPendlePtToAssetOracle;
  };
  SWAPPERS: {
    DIRECT_SWAPPER: OrigamiDexAggregatorSwapper;
    SUSDE_SWAPPER: OrigamiErc4626AndDexAggregatorSwapper;
  };
  FLASHLOAN_PROVIDERS: {
    SPARK: OrigamiAaveV3FlashLoanProvider;
  };

  LOV_WSTETH_A: ISparkType;
  LOV_WSTETH_B: ISparkType;
  LOV_USD0pp_A: IMorphoType;
  LOV_PT_SUSDE_MAY_2025_A: IMorphoMarketALType;

  LOV_SUSDE_A: IMorphoType; // DEPRECATED
  LOV_SUSDE_B: IMorphoType; // DEPRECATED
  LOV_USDE_A: IMorphoType; // DEPRECATED
  LOV_USDE_B: IMorphoType; // DEPRECATED
  LOV_WEETH_A: IMorphoType; // DEPRECATED
  LOV_EZETH_A: IMorphoType; // DEPRECATED
  LOV_WOETH_A: IMorphoType; // DEPRECATED
  LOV_WETH_DAI_LONG_A: ISparkType; // DEPRECATED
  LOV_WETH_SDAI_SHORT_A: ISparkType; // DEPRECATED
  LOV_WBTC_DAI_LONG_A: ISparkType; // DEPRECATED
  LOV_WBTC_SDAI_SHORT_A: ISparkType; // DEPRECATED
  LOV_WETH_WBTC_LONG_A: ISparkType; // DEPRECATED
  LOV_WETH_WBTC_SHORT_A: ISparkType; // DEPRECATED
  LOV_PT_SUSDE_OCT24_A: IMorphoMarketALType; // DEPRECATED
  LOV_PT_SUSDE_MAR_2025_A: IMorphoMarketALType; // DEPRECATED
  LOV_MKR_DAI_LONG_A: ISparkType; // DEPRECATED
  LOV_AAVE_USDC_LONG_A: ISparkType; // DEPRECATED
  LOV_SDAI_A: IMorphoType; // DEPRECATED
  LOV_RSWETH_A: IMorphoType; // DEPRECATED
  LOV_PT_EBTC_DEC24_A: IZeroLendType; // DEPRECATED
  LOV_PT_CORN_LBTC_DEC24_A: IZeroLendType; // DEPRECATED
  LOV_WETH_CBBTC_LONG_A: ISparkType; // DEPRECATED
  LOV_PT_USD0pp_MAR_2025_A: IMorphoType; // DEPRECATED
  LOV_PT_LBTC_MAR_2025_A: IMorphoType; // DEPRECATED

  VAULTS: {
    SUSDSpS: {
      TOKEN: OrigamiDelegated4626Vault;
      MANAGER: OrigamiSuperSavingsUsdsManager;
      COW_SWAPPER: OrigamiCowSwapper;
      COW_SWAPPER_2: OrigamiCowSwapper;
    };
    hOHM: {
      TOKEN: OrigamiHOhmVault;
      MANAGER: OrigamiHOhmManager;
      SWEEP_SWAPPER: OrigamiSwapperWithCallback;
      TELEPORTER: OrigamiTokenTeleporter;
      MIGRATOR: OrigamiCoolerMigrator;
    };
  };

  EXTERNAL: {
    WETH_TOKEN: IERC20Metadata;
    WBTC_TOKEN: IERC20Metadata;
    MAKER_DAO: {
      DAI_TOKEN: IERC20Metadata;
      SDAI_TOKEN: IERC4626;
      MKR_TOKEN: IERC20Metadata;
    };
    SKY: {
      USDS_TOKEN: IERC20Metadata;
      SUSDS_TOKEN: IERC4626;
      SKY_TOKEN: IERC20Metadata;
    };
    CIRCLE: {
      USDC_TOKEN: IERC20Metadata;
    };
    ETHENA: {
      USDE_TOKEN: IERC20Metadata;
      SUSDE_TOKEN: IERC4626;
    };
    ETHERFI: {
      WEETH_TOKEN: IERC20Metadata;
      LIQUIDITY_POOL: IEtherFiLiquidityPool;
      EBTC_TOKEN: IERC20Metadata;
    };
    RENZO: {
      EZETH_TOKEN: IERC20Metadata;
      RESTAKE_MANAGER: IRenzoRestakeManager;
    };
    LIDO: {
      STETH_TOKEN: IERC20Metadata;
      WSTETH_TOKEN: IERC20Metadata;
    };
    ORIGIN: {
      OETH_TOKEN: IERC20Metadata;
      WOETH_TOKEN: IERC4626;
    };
    USUAL: {
      USD0pp_TOKEN: IERC20Metadata;
      USD0_TOKEN: IERC20Metadata;
    };
    SWELL: {
      RSWETH_TOKEN: IERC20Metadata;
    };
    LOMBARD: {
      LBTC_TOKEN: IERC20Metadata;
    };
    COINBASE: {
      CBBTC_TOKEN: IERC20Metadata;
    };
    MORPHO: {
      SINGLETON: IMorpho;
    };
    SPARK: {
      POOL_ADDRESS_PROVIDER: IPoolAddressesProvider;
    };
    ZEROLEND: {
      MAINNET_BTC_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider;
    };
    AAVE: {
      AAVE_TOKEN: IERC20Metadata;
      V3_MAINNET_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider;
      V3_LIDO_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider;
    };
    PENDLE: {
      SUSDE_OCT24: {
        PT_TOKEN: IERC20Metadata;
      };
      SUSDE_MAR_2025: {
        PT_TOKEN: IERC20Metadata;
      };
      SUSDE_MAY_2025: {
        PT_TOKEN: IERC20Metadata;
      };
      EBTC_DEC24: {
        PT_TOKEN: IERC20Metadata;
      };
      CORN_LBTC_DEC24: {
        PT_TOKEN: IERC20Metadata;
      };
      USD0pp_MAR_2025: {
        PT_TOKEN: IERC20Metadata;
      };
      LBTC_MAR_2025: {
        PT_TOKEN: IERC20Metadata;
      };
    };
    OLYMPUS: {
      GOHM_TOKEN: IERC20Metadata;
      MONO_COOLER: IMonoCooler;
    };
  };

  MAINNET_TEST: {
    SWAPPERS: {
      COW_SWAPPER_1: OrigamiCowSwapper;
      COW_SWAPPER_2: OrigamiCowSwapper;
    },
  },
}

export function connectToContracts(owner: Signer): ContractInstances {
  return connectToContracts1(owner, getDeployedContracts());
}

export function connectToContracts1(owner: Signer, ADDRS: ContractAddresses): ContractInstances {
  return {
    CORE: {
      TOKEN_PRICES: {
          V1: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V1, owner),
          V2: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V2, owner),
          V3: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V3, owner),
          V4: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V4, owner),
        },
    },
    ORACLES: {
      USDE_DAI: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.USDE_DAI, owner),
      SUSDE_DAI: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.SUSDE_DAI, owner),
      WEETH_WETH: OrigamiEtherFiEthToEthOracle__factory.connect(ADDRS.ORACLES.WEETH_WETH, owner),
      EZETH_WETH: OrigamiRenzoEthToEthOracle__factory.connect(ADDRS.ORACLES.EZETH_WETH, owner),
      STETH_WETH: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.STETH_WETH, owner),
      WSTETH_WETH: OrigamiWstEthToEthOracle__factory.connect(ADDRS.ORACLES.WSTETH_WETH, owner),
      WOETH_WETH: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.WOETH_WETH, owner),
      WETH_DAI: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.WETH_DAI, owner),
      WBTC_DAI: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.WBTC_DAI, owner),
      WETH_WBTC: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.WETH_WBTC, owner),
      WETH_SDAI: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.WETH_SDAI, owner),
      WBTC_SDAI: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.WBTC_SDAI, owner),
      DAI_USD: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.DAI_USD, owner),
      SDAI_DAI: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.SDAI_DAI, owner),
      PT_SUSDE_OCT24_USDE: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_OCT24_USDE, owner),
      PT_SUSDE_OCT24_DAI: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_OCT24_DAI, owner),
      PT_SUSDE_MAR_2025_USDE: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAR_2025_USDE, owner),
      PT_SUSDE_MAR_2025_DAI: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAR_2025_DAI, owner),
      PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY, owner),
      PT_SUSDE_MAR_2025_DAI_WITH_DISCOUNT_TO_MATURITY: OrigamiScaledOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAR_2025_DAI_WITH_DISCOUNT_TO_MATURITY, owner),
      PT_SUSDE_MAY_2025_USDE: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAY_2025_USDE, owner),
      PT_SUSDE_MAY_2025_DAI: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAY_2025_DAI, owner),
      PT_SUSDE_MAY_2025_DISCOUNT_TO_MATURITY: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAY_2025_DISCOUNT_TO_MATURITY, owner),
      PT_SUSDE_MAY_2025_DAI_WITH_DISCOUNT_TO_MATURITY: OrigamiScaledOracle__factory.connect(ADDRS.ORACLES.PT_SUSDE_MAY_2025_DAI_WITH_DISCOUNT_TO_MATURITY, owner),
      MKR_DAI: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.MKR_DAI, owner),
      AAVE_USDC: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.AAVE_USDC, owner),
      SDAI_USDC: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.SDAI_USDC, owner),
      USD0pp_USD0: OrigamiVolatileCurveEmaOracle__factory.connect(ADDRS.ORACLES.USD0pp_USD0, owner),
      USD0pp_USDC_PEGGED: OrigamiFixedPriceOracle__factory.connect(ADDRS.ORACLES.USD0pp_USDC_PEGGED, owner),
      USD0pp_USDC_FLOOR_PRICE: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.USD0pp_USDC_FLOOR_PRICE, owner),
      USD0pp_USDC_MARKET_PRICE: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.USD0pp_USDC_MARKET_PRICE, owner),
      USD0pp_MORPHO_TO_MARKET_CONVERSION: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION, owner),
      USD0_USDC: OrigamiVolatileCurveEmaOracle__factory.connect(ADDRS.ORACLES.USD0_USDC, owner),
      RSWETH_WETH: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.RSWETH_WETH, owner),
      PT_EBTC_DEC24_EBTC: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_EBTC_DEC24_EBTC, owner),
      PT_CORN_LBTC_DEC24_LBTC: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_CORN_LBTC_DEC24_LBTC, owner),
      WETH_CBBTC: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.WETH_CBBTC, owner),
      PT_USD0pp_MAR_2025_USD0pp: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_USD0pp_MAR_2025_USD0pp, owner),
      PT_USD0pp_MAR_2025_USDC_PEGGED: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.PT_USD0pp_MAR_2025_USDC_PEGGED, owner),
      SKY_MKR: OrigamiFixedPriceOracle__factory.connect(ADDRS.ORACLES.SKY_MKR, owner),
      SKY_USDS: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.SKY_USDS, owner),
      PT_LBTC_MAR_2025_LBTC: OrigamiPendlePtToAssetOracle__factory.connect(ADDRS.ORACLES.PT_LBTC_MAR_2025_LBTC, owner),
    },
    SWAPPERS: {
      DIRECT_SWAPPER: OrigamiDexAggregatorSwapper__factory.connect(ADDRS.SWAPPERS.DIRECT_SWAPPER, owner),
      SUSDE_SWAPPER: OrigamiErc4626AndDexAggregatorSwapper__factory.connect(ADDRS.SWAPPERS.SUSDE_SWAPPER, owner),
    },
    FLASHLOAN_PROVIDERS: {
      SPARK: OrigamiAaveV3FlashLoanProvider__factory.connect(ADDRS.FLASHLOAN_PROVIDERS.SPARK, owner),
    },

    LOV_WSTETH_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WSTETH_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WSTETH_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WSTETH_A.MANAGER, owner),
    },
    LOV_WSTETH_B: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WSTETH_B.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WSTETH_B.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WSTETH_B.MANAGER, owner),
    },
    LOV_USD0pp_A: {
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_USD0pp_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_USD0pp_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManagerMarketAL__factory.connect(ADDRS.LOV_USD0pp_A.MANAGER, owner),
    },
    LOV_PT_SUSDE_MAY_2025_A: {
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_PT_SUSDE_MAY_2025_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_SUSDE_MAY_2025_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManagerMarketAL__factory.connect(ADDRS.LOV_PT_SUSDE_MAY_2025_A.MANAGER, owner),
    },
    
    LOV_SUSDE_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_SUSDE_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_SUSDE_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_SUSDE_A.MANAGER, owner),
    },
    LOV_SUSDE_B: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_SUSDE_B.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_SUSDE_B.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_SUSDE_B.MANAGER, owner),
    },
    LOV_USDE_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_USDE_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_USDE_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_USDE_A.MANAGER, owner),
    },
    LOV_USDE_B: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_USDE_B.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_USDE_B.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_USDE_B.MANAGER, owner),
    },
    LOV_WEETH_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_WEETH_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WEETH_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_WEETH_A.MANAGER, owner),
    },
    LOV_EZETH_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_EZETH_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_EZETH_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_EZETH_A.MANAGER, owner),
    },
    LOV_WOETH_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_WOETH_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WOETH_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_WOETH_A.MANAGER, owner),
    },
    LOV_WETH_DAI_LONG_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WETH_DAI_LONG_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WETH_DAI_LONG_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WETH_DAI_LONG_A.MANAGER, owner),
    },
    LOV_WETH_SDAI_SHORT_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WETH_SDAI_SHORT_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WETH_SDAI_SHORT_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WETH_SDAI_SHORT_A.MANAGER, owner),
    },
    LOV_WBTC_DAI_LONG_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WBTC_DAI_LONG_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WBTC_DAI_LONG_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WBTC_DAI_LONG_A.MANAGER, owner),
    },
    LOV_WBTC_SDAI_SHORT_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WBTC_SDAI_SHORT_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WBTC_SDAI_SHORT_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WBTC_SDAI_SHORT_A.MANAGER, owner),
    },
    LOV_WETH_WBTC_LONG_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WETH_WBTC_LONG_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WETH_WBTC_LONG_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WETH_WBTC_LONG_A.MANAGER, owner),
    },
    LOV_WETH_WBTC_SHORT_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WETH_WBTC_SHORT_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WETH_WBTC_SHORT_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WETH_WBTC_SHORT_A.MANAGER, owner),
    },
    LOV_PT_SUSDE_OCT24_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_SUSDE_OCT24_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManagerMarketAL__factory.connect(ADDRS.LOV_PT_SUSDE_OCT24_A.MANAGER, owner),
    },
    LOV_PT_SUSDE_MAR_2025_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_PT_SUSDE_MAR_2025_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_SUSDE_MAR_2025_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManagerMarketAL__factory.connect(ADDRS.LOV_PT_SUSDE_MAR_2025_A.MANAGER, owner),
    },
    LOV_MKR_DAI_LONG_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_MKR_DAI_LONG_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_MKR_DAI_LONG_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_MKR_DAI_LONG_A.MANAGER, owner),
    },
    LOV_AAVE_USDC_LONG_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_AAVE_USDC_LONG_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_AAVE_USDC_LONG_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_AAVE_USDC_LONG_A.MANAGER, owner),
    },
    LOV_SDAI_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_SDAI_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_SDAI_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_SDAI_A.MANAGER, owner),
    },
    LOV_RSWETH_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_RSWETH_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_RSWETH_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_RSWETH_A.MANAGER, owner),
    },
    LOV_PT_EBTC_DEC24_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_EBTC_DEC24_A.TOKEN, owner),
      ZEROLEND_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_PT_EBTC_DEC24_A.ZEROLEND_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_PT_EBTC_DEC24_A.MANAGER, owner),
    },
    LOV_PT_CORN_LBTC_DEC24_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_CORN_LBTC_DEC24_A.TOKEN, owner),
      ZEROLEND_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_PT_CORN_LBTC_DEC24_A.ZEROLEND_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_PT_CORN_LBTC_DEC24_A.MANAGER, owner),
    },
    LOV_WETH_CBBTC_LONG_A: { // DEPRECATED
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WETH_CBBTC_LONG_A.TOKEN, owner),
      SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WETH_CBBTC_LONG_A.MANAGER, owner),
    },
    LOV_PT_USD0pp_MAR_2025_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_PT_USD0pp_MAR_2025_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_USD0pp_MAR_2025_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_PT_USD0pp_MAR_2025_A.MANAGER, owner),
    },
    LOV_PT_LBTC_MAR_2025_A: { // DEPRECATED
      MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_PT_LBTC_MAR_2025_A.MORPHO_BORROW_LEND, owner),
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_PT_LBTC_MAR_2025_A.TOKEN, owner),
      MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_PT_LBTC_MAR_2025_A.MANAGER, owner),
    },

    VAULTS: {
      SUSDSpS: {
        TOKEN: OrigamiDelegated4626Vault__factory.connect(ADDRS.VAULTS.SUSDSpS.TOKEN, owner),
        MANAGER: OrigamiSuperSavingsUsdsManager__factory.connect(ADDRS.VAULTS.SUSDSpS.MANAGER, owner),
        COW_SWAPPER: OrigamiCowSwapper__factory.connect(ADDRS.VAULTS.SUSDSpS.COW_SWAPPER, owner),
        COW_SWAPPER_2: OrigamiCowSwapper__factory.connect(ADDRS.VAULTS.SUSDSpS.COW_SWAPPER_2, owner),
      },
      hOHM: {
        TOKEN: OrigamiHOhmVault__factory.connect(ADDRS.VAULTS.hOHM.TOKEN, owner),
        MANAGER: OrigamiHOhmManager__factory.connect(ADDRS.VAULTS.hOHM.MANAGER, owner),
        SWEEP_SWAPPER: OrigamiSwapperWithCallback__factory.connect(ADDRS.VAULTS.hOHM.SWEEP_SWAPPER, owner),
        TELEPORTER: OrigamiTokenTeleporter__factory.connect(ADDRS.VAULTS.hOHM.TELEPORTER, owner),
        MIGRATOR: OrigamiCoolerMigrator__factory.connect(ADDRS.VAULTS.hOHM.MIGRATOR, owner),
      },
    },
    
    EXTERNAL: {
      WETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.WETH_TOKEN, owner),
      WBTC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.WBTC_TOKEN, owner),
      MAKER_DAO: {
        DAI_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN, owner),
        SDAI_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN, owner),
        MKR_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.MKR_TOKEN, owner),
      },
      SKY: {
        USDS_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.SKY.USDS_TOKEN, owner),
        SUSDS_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, owner),
        SKY_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.SKY.SKY_TOKEN, owner),
      },
      CIRCLE: {
        USDC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, owner),
      },
      ETHENA: {
        USDE_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, owner),
        SUSDE_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, owner),
      },
      ETHERFI: {
        WEETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN, owner),
        LIQUIDITY_POOL: IEtherFiLiquidityPool__factory.connect(ADDRS.EXTERNAL.ETHERFI.LIQUIDITY_POOL, owner),
        EBTC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.ETHERFI.EBTC_TOKEN, owner),
      },
      RENZO: {
        EZETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.RENZO.EZETH_TOKEN, owner),
        RESTAKE_MANAGER: IRenzoRestakeManager__factory.connect(ADDRS.EXTERNAL.RENZO.RESTAKE_MANAGER, owner),
      },
      LIDO: {
        STETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.LIDO.STETH_TOKEN, owner),
        WSTETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN, owner),
      },
      ORIGIN: {
        OETH_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.ORIGIN.OETH_TOKEN, owner),
        WOETH_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN, owner),
      },
      USUAL: {
        USD0pp_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN, owner),
        USD0_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.USUAL.USD0_TOKEN, owner),
      },
      SWELL: {
        RSWETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.SWELL.RSWETH_TOKEN, owner),
      },
      LOMBARD: {
        LBTC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN, owner),
      },
      COINBASE: {
        CBBTC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.COINBASE.CBBTC_TOKEN, owner),
      },
      MORPHO: {
        SINGLETON: IMorpho__factory.connect(ADDRS.EXTERNAL.MORPHO.SINGLETON, owner),
      },
      SPARK: {
        POOL_ADDRESS_PROVIDER: IPoolAddressesProvider__factory.connect(ADDRS.EXTERNAL.SPARK.POOL_ADDRESS_PROVIDER, owner),
      },
      AAVE: {
        AAVE_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.AAVE.AAVE_TOKEN, owner),
        V3_MAINNET_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider__factory.connect(ADDRS.EXTERNAL.AAVE.V3_MAINNET_POOL_ADDRESS_PROVIDER, owner),
        V3_LIDO_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider__factory.connect(ADDRS.EXTERNAL.AAVE.V3_LIDO_POOL_ADDRESS_PROVIDER, owner),
      },
      ZEROLEND: {
        MAINNET_BTC_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider__factory.connect(ADDRS.EXTERNAL.ZEROLEND.MAINNET_BTC_POOL_ADDRESS_PROVIDER, owner),
      },
      PENDLE: {
        SUSDE_OCT24: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN, owner),
        },
        SUSDE_MAR_2025: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN, owner),
        },
        SUSDE_MAY_2025: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.SUSDE_MAY_2025.PT_TOKEN, owner),
        },
        EBTC_DEC24: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.EBTC_DEC24.PT_TOKEN, owner),
        },
        CORN_LBTC_DEC24: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.CORN_LBTC_DEC24.PT_TOKEN, owner),
        },
        USD0pp_MAR_2025: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN, owner),
        },
        LBTC_MAR_2025: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN, owner),
        },
      },
      OLYMPUS: {
        GOHM_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN, owner),
        MONO_COOLER: IMonoCooler__factory.connect(ADDRS.EXTERNAL.OLYMPUS.MONO_COOLER, owner),
      },
    },

    MAINNET_TEST: {
      SWAPPERS: {
        COW_SWAPPER_1: OrigamiCowSwapper__factory.connect(ADDRS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1, owner),
        COW_SWAPPER_2: OrigamiCowSwapper__factory.connect(ADDRS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2, owner),
      },
    },
  }
}
