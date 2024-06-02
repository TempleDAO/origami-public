import { network } from "hardhat";
import { 
  TokenPrices, TokenPrices__factory,
  OrigamiStableChainlinkOracle, OrigamiStableChainlinkOracle__factory,
  OrigamiLovToken, OrigamiLovToken__factory,
  OrigamiLovTokenMorphoManager, OrigamiLovTokenMorphoManager__factory,
  OrigamiMorphoBorrowAndLend, OrigamiMorphoBorrowAndLend__factory,
  OrigamiErc4626Oracle, OrigamiErc4626Oracle__factory,
  AdaptiveCurveIrm, AdaptiveCurveIrm__factory,
  MorphoChainlinkOracleV2, MorphoChainlinkOracleV2__factory,
  OrigamiErc4626AndDexAggregatorSwapper, OrigamiErc4626AndDexAggregatorSwapper__factory,
  IMorpho, IMorpho__factory,
  AggregatorV3Interface, AggregatorV3Interface__factory,
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
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as MAINNET_CONTRACTS } from "./mainnet";
import { CONTRACTS as LOCALHOST_CONTRACTS } from "./localhost";
import { IERC4626 } from "../../../../typechain/@openzeppelin/contracts/interfaces";
import { IERC4626__factory } from "../../../../typechain/factories/@openzeppelin/contracts/interfaces";
import { IERC20__factory } from "../../../../typechain/factories/@openzeppelin/contracts/token/ERC20";
import { IERC20 } from "../../../../typechain/@openzeppelin/contracts/token/ERC20";

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'mainnet') {
    return MAINNET_CONTRACTS;
  } else if (network.name === 'localhost') {
    return LOCALHOST_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: TokenPrices;
  },
  ORACLES: {
    USDE_DAI: OrigamiStableChainlinkOracle;
    SUSDE_DAI: OrigamiErc4626Oracle;
    WEETH_WETH: OrigamiEtherFiEthToEthOracle;
    EZETH_WETH: OrigamiRenzoEthToEthOracle;
    STETH_WETH: OrigamiStableChainlinkOracle;
    WSTETH_WETH: OrigamiWstEthToEthOracle;
  },
  SWAPPERS: {
    ERC4626_AND_1INCH_SWAPPER: OrigamiErc4626AndDexAggregatorSwapper;
    DIRECT_1INCH_SWAPPER: OrigamiDexAggregatorSwapper;
  },
  FLASHLOAN_PROVIDERS: {
    SPARK: OrigamiAaveV3FlashLoanProvider;
  },
  LOV_SUSDE_A: {
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    TOKEN: OrigamiLovToken;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  LOV_SUSDE_B: {
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    TOKEN: OrigamiLovToken;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  LOV_USDE_A: {
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    TOKEN: OrigamiLovToken;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  LOV_USDE_B: {
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    TOKEN: OrigamiLovToken;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  LOV_WEETH_A: {
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    TOKEN: OrigamiLovToken;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  LOV_EZETH_A: {
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    TOKEN: OrigamiLovToken;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  LOV_WSTETH_A: {
    TOKEN: OrigamiLovToken;
    SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend;
    MANAGER: OrigamiLovTokenFlashAndBorrowManager;
  },
  EXTERNAL: {
    WETH_TOKEN: IERC20;
    MAKER_DAO: {
      DAI_TOKEN: IERC20;
    },
    ETHENA: {
      USDE_TOKEN: IERC20,
      SUSDE_TOKEN: IERC4626,
    },
    ETHERFI: {
      WEETH_TOKEN: IERC20,
      LIQUIDITY_POOL: IEtherFiLiquidityPool,
    },
    RENZO: {
      EZETH_TOKEN: IERC20,
      RESTAKE_MANAGER: IRenzoRestakeManager,
    },
    LIDO: {
      STETH_TOKEN: IERC20;
      WSTETH_TOKEN: IERC20;
    },
    REDSTONE: {
      USDE_USD_ORACLE: AggregatorV3Interface;
      SUSDE_USD_ORACLE: AggregatorV3Interface;
      WEETH_WETH_ORACLE: AggregatorV3Interface;
      WEETH_USD_ORACLE: AggregatorV3Interface;
      EZETH_WETH_ORACLE: AggregatorV3Interface;
    },
    CHAINLINK: {
      ETH_USD_ORACLE: AggregatorV3Interface;
      STETH_ETH_ORACLE: AggregatorV3Interface;
    },
    MORPHO: {
      SINGLETON: IMorpho,
      IRM: AdaptiveCurveIrm,
      ORACLE: {
        SUSDE_DAI: MorphoChainlinkOracleV2,
        USDE_DAI: MorphoChainlinkOracleV2,
        WEETH_WETH: MorphoChainlinkOracleV2,
        EZETH_WETH: MorphoChainlinkOracleV2,
      },
    },
    SPARK: {
      POOL_ADDRESS_PROVIDER: IPoolAddressesProvider,
    },
  },
}

export function connectToContracts(owner: Signer): ContractInstances {
    const ADDRS = getDeployedContracts();

    return {
      CORE: {
        TOKEN_PRICES: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES, owner),
      },
      ORACLES: {
        USDE_DAI: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.USDE_DAI, owner),
        SUSDE_DAI: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.SUSDE_DAI, owner),
        WEETH_WETH: OrigamiEtherFiEthToEthOracle__factory.connect(ADDRS.ORACLES.WEETH_WETH, owner),
        EZETH_WETH: OrigamiRenzoEthToEthOracle__factory.connect(ADDRS.ORACLES.EZETH_WETH, owner),
        STETH_WETH: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.STETH_WETH, owner),
        WSTETH_WETH: OrigamiWstEthToEthOracle__factory.connect(ADDRS.ORACLES.WSTETH_WETH, owner),
      },
      SWAPPERS: {
        ERC4626_AND_1INCH_SWAPPER: OrigamiErc4626AndDexAggregatorSwapper__factory.connect(ADDRS.SWAPPERS.ERC4626_AND_1INCH_SWAPPER, owner),
        DIRECT_1INCH_SWAPPER: OrigamiDexAggregatorSwapper__factory.connect(ADDRS.SWAPPERS.DIRECT_1INCH_SWAPPER, owner),
      },
      FLASHLOAN_PROVIDERS: {
        SPARK: OrigamiAaveV3FlashLoanProvider__factory.connect(ADDRS.FLASHLOAN_PROVIDERS.SPARK, owner),
      },
      LOV_SUSDE_A: {
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_SUSDE_A.MORPHO_BORROW_LEND, owner),
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_SUSDE_A.TOKEN, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_SUSDE_A.MANAGER, owner),
      },
      LOV_SUSDE_B: {
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_SUSDE_B.MORPHO_BORROW_LEND, owner),
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_SUSDE_B.TOKEN, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_SUSDE_B.MANAGER, owner),
      },
      LOV_USDE_A: {
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_USDE_A.MORPHO_BORROW_LEND, owner),
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_USDE_A.TOKEN, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_USDE_A.MANAGER, owner),
      },
      LOV_USDE_B: {
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_USDE_B.MORPHO_BORROW_LEND, owner),
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_USDE_B.TOKEN, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_USDE_B.MANAGER, owner),
      },
      LOV_WEETH_A: {
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_WEETH_A.MORPHO_BORROW_LEND, owner),
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WEETH_A.TOKEN, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_WEETH_A.MANAGER, owner),
      },
      LOV_EZETH_A: {
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_EZETH_A.MORPHO_BORROW_LEND, owner),
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_EZETH_A.TOKEN, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_EZETH_A.MANAGER, owner),
      },
      LOV_WSTETH_A: {
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WSTETH_A.TOKEN, owner),
        SPARK_BORROW_LEND: OrigamiAaveV3BorrowAndLend__factory.connect(ADDRS.LOV_WSTETH_A.SPARK_BORROW_LEND, owner),
        MANAGER: OrigamiLovTokenFlashAndBorrowManager__factory.connect(ADDRS.LOV_WSTETH_A.MANAGER, owner),
      },
      EXTERNAL: {
        WETH_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.WETH_TOKEN, owner),
        MAKER_DAO: {
          DAI_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN, owner),
        },
        ETHENA: {
          USDE_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, owner),
          SUSDE_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, owner),
        },
        ETHERFI: {
          WEETH_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN, owner),
          LIQUIDITY_POOL: IEtherFiLiquidityPool__factory.connect(ADDRS.EXTERNAL.ETHERFI.LIQUIDITY_POOL, owner),
        },
        RENZO: {
          EZETH_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.RENZO.EZETH_TOKEN, owner),
          RESTAKE_MANAGER: IRenzoRestakeManager__factory.connect(ADDRS.EXTERNAL.RENZO.RESTAKE_MANAGER, owner),
        },
        LIDO: {
          STETH_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.LIDO.STETH_TOKEN, owner),
          WSTETH_TOKEN: IERC20__factory.connect(ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN, owner),
        },
        REDSTONE: {
          USDE_USD_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.REDSTONE.USDE_USD_ORACLE, owner),
          SUSDE_USD_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE, owner),
          WEETH_WETH_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.REDSTONE.WEETH_WETH_ORACLE, owner),
          WEETH_USD_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.REDSTONE.WEETH_USD_ORACLE, owner),
          EZETH_WETH_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE, owner),
        },
        CHAINLINK: {
          ETH_USD_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, owner),
          STETH_ETH_ORACLE: AggregatorV3Interface__factory.connect(ADDRS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE, owner),
        },
        MORPHO: {
          SINGLETON: IMorpho__factory.connect(ADDRS.EXTERNAL.MORPHO.SINGLETON, owner),
          IRM: AdaptiveCurveIrm__factory.connect(ADDRS.EXTERNAL.MORPHO.IRM, owner),
          ORACLE: {
            SUSDE_DAI: MorphoChainlinkOracleV2__factory.connect(ADDRS.EXTERNAL.MORPHO.ORACLE.SUSDE_DAI, owner),
            USDE_DAI: MorphoChainlinkOracleV2__factory.connect(ADDRS.EXTERNAL.MORPHO.ORACLE.USDE_DAI, owner),
            WEETH_WETH: MorphoChainlinkOracleV2__factory.connect(ADDRS.EXTERNAL.MORPHO.ORACLE.WEETH_WETH, owner),
            EZETH_WETH: MorphoChainlinkOracleV2__factory.connect(ADDRS.EXTERNAL.MORPHO.ORACLE.EZETH_WETH, owner),
          },
        },
        SPARK: {
          POOL_ADDRESS_PROVIDER: IPoolAddressesProvider__factory.connect(ADDRS.EXTERNAL.SPARK.POOL_ADDRESS_PROVIDER, owner),
        },
      },
    }
  }
