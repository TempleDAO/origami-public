import { network } from "hardhat";
import { 
  RelayedOracle, RelayedOracle__factory,
  OrigamiDexAggregatorSwapper, OrigamiDexAggregatorSwapper__factory, 
  TokenPrices, TokenPrices__factory,
  OrigamiStableChainlinkOracle,
  OrigamiStableChainlinkOracle__factory,
  OrigamiLovToken,
  OrigamiLovToken__factory,
  DummyMintableToken,
  MockSUsdEToken,
  OrigamiLovTokenMorphoManager,
  OrigamiMorphoBorrowAndLend,
  OrigamiErc4626Oracle,
  OrigamiErc4626Oracle__factory,
  OrigamiMorphoBorrowAndLend__factory,
  OrigamiLovTokenMorphoManager__factory,
  DummyMintableToken__factory,
  MockSUsdEToken__factory,
  Morpho,
  AdaptiveCurveIrm,
  MorphoChainlinkOracleV2,
  Morpho__factory,
  AdaptiveCurveIrm__factory,
  MorphoChainlinkOracleV2__factory
} from "../../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as SEPOLIA_CONTRACTS } from "./sepolia";
import { CONTRACTS as LOCALHOST_CONTRACTS } from "./localhost";

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'sepolia') {
    return SEPOLIA_CONTRACTS;
  } else if (network.name === 'localhost') {
    return LOCALHOST_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: TokenPrices;
    SWAPPER_1INCH: OrigamiDexAggregatorSwapper;
  },
  ORACLES: {
    USDE_DAI: OrigamiStableChainlinkOracle;
    SUSDE_DAI: OrigamiErc4626Oracle;
  },
  LOV_SUSDE: {
    TOKEN: OrigamiLovToken;
    MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend;
    MANAGER: OrigamiLovTokenMorphoManager;
  },
  EXTERNAL: {
    MAKER_DAO: {
      DAI_TOKEN: DummyMintableToken;
    },
    ETHENA: {
      USDE_TOKEN: DummyMintableToken,
      SUSDE_TOKEN: MockSUsdEToken,
    },
    REDSTONE: {
      USDE_USD_ORACLE: RelayedOracle;
      SUSDE_USD_ORACLE: RelayedOracle;
    },
    MORPHO: {
      SINGLETON: Morpho,
      IRM: AdaptiveCurveIrm,
      ORACLE: MorphoChainlinkOracleV2,
    }
  },
}

export function connectToContracts(owner: Signer): ContractInstances {
    const ADDRS = getDeployedContracts();

    return {
      CORE: {
        TOKEN_PRICES: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES, owner),
        SWAPPER_1INCH: OrigamiDexAggregatorSwapper__factory.connect(ADDRS.CORE.SWAPPER_1INCH, owner),
      },
      ORACLES: {
        USDE_DAI: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.USDE_DAI, owner),
        SUSDE_DAI: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.SUSDE_DAI, owner),
      },
      LOV_SUSDE: {
        TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_SUSDE.TOKEN, owner),
        MORPHO_BORROW_LEND: OrigamiMorphoBorrowAndLend__factory.connect(ADDRS.LOV_SUSDE.MORPHO_BORROW_LEND, owner),
        MANAGER: OrigamiLovTokenMorphoManager__factory.connect(ADDRS.LOV_SUSDE.MANAGER, owner),
      },
      EXTERNAL: {
        MAKER_DAO: {
          DAI_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN, owner),
        },
        ETHENA: {
          USDE_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, owner),
          SUSDE_TOKEN: MockSUsdEToken__factory.connect(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, owner),
        },
        REDSTONE: {
          USDE_USD_ORACLE: RelayedOracle__factory.connect(ADDRS.EXTERNAL.REDSTONE.USDE_USD_ORACLE, owner),
          SUSDE_USD_ORACLE: RelayedOracle__factory.connect(ADDRS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE, owner),
        },
        MORPHO: {
          SINGLETON: Morpho__factory.connect(ADDRS.EXTERNAL.MORPHO.SINGLETON, owner),
          IRM: AdaptiveCurveIrm__factory.connect(ADDRS.EXTERNAL.MORPHO.IRM, owner),
          ORACLE: MorphoChainlinkOracleV2__factory.connect(ADDRS.EXTERNAL.MORPHO.ORACLE, owner),
        },
      },
    }
  }
