import { network } from "hardhat";
import { 
  DummyMintableToken, DummyMintableToken__factory,
  RelayedOracle, RelayedOracle__factory,
  LinearWithKinkInterestRateModel, LinearWithKinkInterestRateModel__factory,
  MockSDaiToken, MockSDaiToken__factory,
  OrigamiAaveV3IdleStrategy, OrigamiAaveV3IdleStrategy__factory, 
  OrigamiCircuitBreakerAllUsersPerPeriod, OrigamiCircuitBreakerAllUsersPerPeriod__factory, 
  OrigamiCircuitBreakerProxy, OrigamiCircuitBreakerProxy__factory, 
  OrigamiCrossRateOracle, OrigamiCrossRateOracle__factory, 
  OrigamiDebtToken, OrigamiDebtToken__factory, 
  OrigamiDexAggregatorSwapper, OrigamiDexAggregatorSwapper__factory, 
  OrigamiIdleStrategyManager, OrigamiIdleStrategyManager__factory, 
  OrigamiInvestmentVault, OrigamiInvestmentVault__factory, 
  OrigamiLendingClerk, OrigamiLendingClerk__factory, 
  OrigamiLendingRewardsMinter, OrigamiLendingRewardsMinter__factory, 
  OrigamiLendingSupplyManager, OrigamiLendingSupplyManager__factory, 
  OrigamiLovToken, OrigamiLovToken__factory, 
  OrigamiLovTokenErc4626Manager, OrigamiLovTokenErc4626Manager__factory, 
  OrigamiOToken, OrigamiOToken__factory, TokenPrices, TokenPrices__factory,
  OrigamiStableChainlinkOracle,
  OrigamiStableChainlinkOracle__factory
} from "../../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as SEPOLIA_CONTRACTS } from "./sepolia";


export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'sepolia') {
    return SEPOLIA_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  CORE: {
    CIRCUIT_BREAKER_PROXY: OrigamiCircuitBreakerProxy;
    TOKEN_PRICES: TokenPrices;
    SWAPPER_1INCH: OrigamiDexAggregatorSwapper;
  },
  OV_USDC: {
    TOKENS: {
      OV_USDC_TOKEN: OrigamiInvestmentVault;
      O_USDC_TOKEN: OrigamiOToken;
      IUSDC_DEBT_TOKEN: OrigamiDebtToken;
    },
    SUPPLY: {
      SUPPLY_MANAGER: OrigamiLendingSupplyManager;
      REWARDS_MINTER: OrigamiLendingRewardsMinter;
      IDLE_STRATEGY_MANAGER: OrigamiIdleStrategyManager;
      AAVE_V3_IDLE_STRATEGY: OrigamiAaveV3IdleStrategy;
    },
    BORROW: {
        LENDING_CLERK: OrigamiLendingClerk;
        CIRCUIT_BREAKER_USDC_BORROW: OrigamiCircuitBreakerAllUsersPerPeriod;
        CIRCUIT_BREAKER_OUSDC_EXIT: OrigamiCircuitBreakerAllUsersPerPeriod;
        GLOBAL_INTEREST_RATE_MODEL: LinearWithKinkInterestRateModel;
    },
  },
  LOV_DSR: {
    LOV_DSR_TOKEN: OrigamiLovToken;
    LOV_DSR_MANAGER: OrigamiLovTokenErc4626Manager;
    LOV_DSR_IR_MODEL: LinearWithKinkInterestRateModel;
  },
  ORACLES: {
    DAI_USD: OrigamiStableChainlinkOracle;
    IUSDC_USD: OrigamiStableChainlinkOracle;
    DAI_IUSDC: OrigamiCrossRateOracle;
  },
  EXTERNAL: {
    MAKER_DAO: {
      DAI_TOKEN: DummyMintableToken;
      SDAI_TOKEN: MockSDaiToken;
    },
    CIRCLE: {
      USDC_TOKEN: DummyMintableToken;
    },
    CHAINLINK: {
      DAI_USD_ORACLE: RelayedOracle;
      USDC_USD_ORACLE: RelayedOracle;
      ETH_USD_ORACLE: RelayedOracle;
    },
  },
}
export function connectToContracts(owner: Signer): ContractInstances {
    const ADDRS = getDeployedContracts();

    return {
      CORE: {
        CIRCUIT_BREAKER_PROXY: OrigamiCircuitBreakerProxy__factory.connect(ADDRS.CORE.CIRCUIT_BREAKER_PROXY, owner),
        TOKEN_PRICES: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES, owner),
        SWAPPER_1INCH: OrigamiDexAggregatorSwapper__factory.connect(ADDRS.CORE.SWAPPER_1INCH, owner),
      },
      OV_USDC: {
        TOKENS: {
          OV_USDC_TOKEN: OrigamiInvestmentVault__factory.connect(ADDRS.OV_USDC.TOKENS.OV_USDC_TOKEN, owner),
          O_USDC_TOKEN: OrigamiOToken__factory.connect(ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN, owner),
          IUSDC_DEBT_TOKEN: OrigamiDebtToken__factory.connect(ADDRS.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN, owner),
        },
        SUPPLY: {
          SUPPLY_MANAGER: OrigamiLendingSupplyManager__factory.connect(ADDRS.OV_USDC.SUPPLY.SUPPLY_MANAGER, owner),
          REWARDS_MINTER: OrigamiLendingRewardsMinter__factory.connect(ADDRS.OV_USDC.SUPPLY.REWARDS_MINTER, owner),
          IDLE_STRATEGY_MANAGER: OrigamiIdleStrategyManager__factory.connect(ADDRS.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER, owner),
          AAVE_V3_IDLE_STRATEGY: OrigamiAaveV3IdleStrategy__factory.connect(ADDRS.OV_USDC.SUPPLY.AAVE_V3_IDLE_STRATEGY, owner),
        },
        BORROW: {
            LENDING_CLERK: OrigamiLendingClerk__factory.connect(ADDRS.OV_USDC.BORROW.LENDING_CLERK, owner),
            CIRCUIT_BREAKER_USDC_BORROW: OrigamiCircuitBreakerAllUsersPerPeriod__factory.connect(ADDRS.OV_USDC.BORROW.CIRCUIT_BREAKER_USDC_BORROW, owner),
            CIRCUIT_BREAKER_OUSDC_EXIT: OrigamiCircuitBreakerAllUsersPerPeriod__factory.connect(ADDRS.OV_USDC.BORROW.CIRCUIT_BREAKER_OUSDC_EXIT, owner),
            GLOBAL_INTEREST_RATE_MODEL: LinearWithKinkInterestRateModel__factory.connect(ADDRS.OV_USDC.BORROW.GLOBAL_INTEREST_RATE_MODEL, owner),
        },
      },
      LOV_DSR: {
        LOV_DSR_TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_DSR.LOV_DSR_TOKEN, owner),
        LOV_DSR_MANAGER: OrigamiLovTokenErc4626Manager__factory.connect(ADDRS.LOV_DSR.LOV_DSR_MANAGER, owner),
        LOV_DSR_IR_MODEL: LinearWithKinkInterestRateModel__factory.connect(ADDRS.LOV_DSR.LOV_DSR_IR_MODEL, owner),
      },
      ORACLES: {
        DAI_USD: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.DAI_USD, owner),
        IUSDC_USD: OrigamiStableChainlinkOracle__factory.connect(ADDRS.ORACLES.IUSDC_USD, owner),
        DAI_IUSDC: OrigamiCrossRateOracle__factory.connect(ADDRS.ORACLES.DAI_IUSDC, owner),
      },
      EXTERNAL: {
        MAKER_DAO: {
          DAI_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN, owner),
          SDAI_TOKEN: MockSDaiToken__factory.connect(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN, owner),
        },
        CIRCLE: {
          USDC_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, owner),
        },
        CHAINLINK: {
          DAI_USD_ORACLE: RelayedOracle__factory.connect(ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE, owner),
          USDC_USD_ORACLE: RelayedOracle__factory.connect(ADDRS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE, owner),
          ETH_USD_ORACLE: RelayedOracle__factory.connect(ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, owner),
        },
      },
    }
  }
