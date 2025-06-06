import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  OrigamiBoycoVault,
  OrigamiBoycoVault__factory,
  OrigamiBoycoUsdcManager,
  OrigamiBoycoUsdcManager__factory,
  OrigamiBalancerComposableStablePoolHelper,
  OrigamiBeraBgtProxy,
  IBalancerVault,
  IBalancerQueries,
  IBalancerBptToken,
  IBeraRewardsVault,
  OrigamiBalancerComposableStablePoolHelper__factory,
  OrigamiBeraBgtProxy__factory,
  IBalancerVault__factory,
  IBalancerQueries__factory,
  IBalancerBptToken__factory,
  IBeraRewardsVault__factory,
  IBeraHoneyFactory,
  IBeraHoneyFactoryReader,
  IBeraHoneyFactory__factory,
  IBeraHoneyFactoryReader__factory,
  OrigamiInfraredVaultProxy,
  OrigamiInfraredVaultProxy__factory,
  OrigamiDelegated4626Vault,
  OrigamiInfraredVaultManager,
  OrigamiDelegated4626Vault__factory,
  OrigamiInfraredVaultManager__factory,
  IInfraredVault__factory,
  IInfraredVault,
  OrigamiSwapperWithCallback,
  OrigamiSwapperWithCallback__factory,
  OrigamiInfraredAutoCompounderFactory,
  OrigamiInfraredAutoCompounderFactory__factory,
  OrigamiLovToken,
  OrigamiEulerV2BorrowAndLend,
  OrigamiLovTokenMorphoManagerMarketAL,
  OrigamiLovToken__factory,
  OrigamiEulerV2BorrowAndLend__factory,
  OrigamiLovTokenMorphoManagerMarketAL__factory,
  OrigamiErc4626Oracle,
  OrigamiErc4626Oracle__factory,
  OrigamiVolatileChainlinkOracle,
  OrigamiVolatileChainlinkOracle__factory,
  OrigamiDexAggregatorSwapper,
  OrigamiDexAggregatorSwapper__factory,
  OrigamiAutoStakingFactory,
  OrigamiAutoStakingFactory__factory,
  OrigamiOFT,
  OrigamiOFT__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as BERACHAIN_CONTRACTS } from "./berachain";

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "berachain" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'berachain') {
    return BERACHAIN_CONTRACTS;
  } else if (network.name === 'localhost') {
    return BERACHAIN_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'berachain') {
    return BERACHAIN_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(BERACHAIN_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

interface IType {
  TOKEN: OrigamiLovToken;
};

interface IEulerV2Type extends IType {
  EULER_V2_BORROW_LEND: OrigamiEulerV2BorrowAndLend;
  MANAGER: OrigamiLovTokenMorphoManagerMarketAL;
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V3: TokenPrices;
      V4: TokenPrices;
      V5: TokenPrices;
    };
  };
  ORACLES: {
    IBGT_WBERA: OrigamiVolatileChainlinkOracle;
    ORIBGT_WBERA: OrigamiErc4626Oracle;
  };
  SWAPPERS: {
    DIRECT_SWAPPER: OrigamiDexAggregatorSwapper;
  };

  VAULTS: {
    hOHM: {
      TOKEN: OrigamiOFT;
    };
    BOYCO_USDC_A: {
      BEX_POOL_HELPERS: {
        HONEY_USDC: OrigamiBalancerComposableStablePoolHelper;
        HONEY_BYUSD: OrigamiBalancerComposableStablePoolHelper;
      };
      INFRARED_REWARDS_VAULT_PROXIES: {
        HONEY_USDC: OrigamiInfraredVaultProxy;
        HONEY_BYUSD: OrigamiInfraredVaultProxy;
      };
      BERA_BGT_PROXY: OrigamiBeraBgtProxy;
      TOKEN: OrigamiBoycoVault;
      MANAGER: OrigamiBoycoUsdcManager;
    };
    ORIBGT: {
      TOKEN: OrigamiDelegated4626Vault;
      MANAGER: OrigamiInfraredVaultManager;
      SWAPPER: OrigamiSwapperWithCallback;
    };
  };

  FACTORIES: {
    INFRARED_AUTO_COMPOUNDER: {
      FACTORY: OrigamiInfraredAutoCompounderFactory;
    };
    INFRARED_AUTO_STAKING: {
      FACTORY: OrigamiAutoStakingFactory;
    };
  };

  LOV_ORIBGT_A: IEulerV2Type;

  EXTERNAL: {
    CIRCLE: {
      USDC_TOKEN: IERC20Metadata;
    };
    PAYPAL: {
      BYUSD_TOKEN: IERC20Metadata;
    };
    BERACHAIN: {
      WBERA_TOKEN: IERC20Metadata;
      HONEY_TOKEN: IERC20Metadata;
      HONEY_FACTORY: IBeraHoneyFactory;
      HONEY_FACTORY_READER: IBeraHoneyFactoryReader;
      BGT_TOKEN: IERC20Metadata;
      REWARD_VAULTS: {
        HONEY_USDC: IBeraRewardsVault;
        HONEY_BYUSD: IBeraRewardsVault;
      };
    };
    INFRARED: {
      IBGT_TOKEN: IERC20Metadata;
      IBGT_VAULT: IInfraredVault;
      IBERA_TOKEN: IERC20Metadata;
      REWARD_VAULTS: {
        HONEY_USDC: IInfraredVault;
        HONEY_BYUSD: IInfraredVault;
        OHM_HONEY: IInfraredVault;
      };
    };
    BEX: {
      BALANCER_VAULT: IBalancerVault;
      BALANCER_QUERIES: IBalancerQueries;
      LP_TOKENS: {
        HONEY_USDC: IBalancerBptToken;
        HONEY_BYUSD: IBalancerBptToken;
      };
    };
  },
}

export function connectToContracts(owner: Signer): ContractInstances {
  return connectToContracts1(owner, getDeployedContracts());
}

export function connectToContracts1(owner: Signer, ADDRS: ContractAddresses): ContractInstances {
  return {
    CORE: {
      TOKEN_PRICES: {
          V3: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V3, owner),
          V4: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V4, owner),
          V5: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V5, owner),
        },
    },
    SWAPPERS: {
      DIRECT_SWAPPER: OrigamiDexAggregatorSwapper__factory.connect(ADDRS.SWAPPERS.DIRECT_SWAPPER, owner),
    },
    ORACLES: {
      IBGT_WBERA: OrigamiVolatileChainlinkOracle__factory.connect(ADDRS.ORACLES.IBGT_WBERA, owner),
      ORIBGT_WBERA: OrigamiErc4626Oracle__factory.connect(ADDRS.ORACLES.ORIBGT_WBERA, owner),
    },

    VAULTS: {
      hOHM: {
        TOKEN: OrigamiOFT__factory.connect(ADDRS.VAULTS.hOHM.TOKEN, owner),
      },
      BOYCO_USDC_A: {
        BEX_POOL_HELPERS: {
          HONEY_USDC: OrigamiBalancerComposableStablePoolHelper__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.BEX_POOL_HELPERS.HONEY_USDC, owner),
          HONEY_BYUSD: OrigamiBalancerComposableStablePoolHelper__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.BEX_POOL_HELPERS.HONEY_BYUSD, owner),
        },
        INFRARED_REWARDS_VAULT_PROXIES: {
          HONEY_USDC: OrigamiInfraredVaultProxy__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, owner),
          HONEY_BYUSD: OrigamiInfraredVaultProxy__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, owner),
        },
        BERA_BGT_PROXY: OrigamiBeraBgtProxy__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.BERA_BGT_PROXY, owner),
        TOKEN: OrigamiBoycoVault__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.TOKEN, owner),
        MANAGER: OrigamiBoycoUsdcManager__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.MANAGER, owner),
      },
      ORIBGT: {
        TOKEN: OrigamiDelegated4626Vault__factory.connect(ADDRS.VAULTS.ORIBGT.TOKEN, owner),
        MANAGER: OrigamiInfraredVaultManager__factory.connect(ADDRS.VAULTS.ORIBGT.MANAGER, owner),
        SWAPPER: OrigamiSwapperWithCallback__factory.connect(ADDRS.VAULTS.ORIBGT.SWAPPER, owner),
      },
    },

    FACTORIES: {
      INFRARED_AUTO_COMPOUNDER: {
        FACTORY: OrigamiInfraredAutoCompounderFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY, owner),
      },
      INFRARED_AUTO_STAKING: {
        FACTORY: OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, owner),
      },
    },

    LOV_ORIBGT_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_ORIBGT_A.TOKEN, owner),
      EULER_V2_BORROW_LEND: OrigamiEulerV2BorrowAndLend__factory.connect(ADDRS.LOV_ORIBGT_A.EULER_V2_BORROW_LEND, owner),
      MANAGER: OrigamiLovTokenMorphoManagerMarketAL__factory.connect(ADDRS.LOV_ORIBGT_A.MANAGER, owner),
    },

    EXTERNAL: {
      CIRCLE: {
        USDC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, owner),
      },
      PAYPAL: {
        BYUSD_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN, owner),
      },
      BERACHAIN: {
        WBERA_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, owner),
        HONEY_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN, owner),
        HONEY_FACTORY: IBeraHoneyFactory__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, owner),
        HONEY_FACTORY_READER: IBeraHoneyFactoryReader__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY_READER, owner),
        BGT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.BGT_TOKEN, owner),
        REWARD_VAULTS: {
          HONEY_USDC: IBeraRewardsVault__factory.connect(ADDRS.EXTERNAL.BERACHAIN.REWARD_VAULTS.HONEY_USDC, owner),
          HONEY_BYUSD: IBeraRewardsVault__factory.connect(ADDRS.EXTERNAL.BERACHAIN.REWARD_VAULTS.HONEY_BYUSD, owner),
        },
      },
      INFRARED: {
        IBGT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN, owner),
        IBGT_VAULT: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.IBGT_VAULT, owner),
        IBERA_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.INFRARED.IBERA_TOKEN, owner),
        REWARD_VAULTS: {
          HONEY_USDC: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.HONEY_USDC, owner),
          HONEY_BYUSD: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.HONEY_BYUSD, owner),
          OHM_HONEY: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.OHM_HONEY, owner),
        },
      },
      BEX: {
        BALANCER_VAULT: IBalancerVault__factory.connect(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, owner),
        BALANCER_QUERIES: IBalancerQueries__factory.connect(ADDRS.EXTERNAL.BEX.BALANCER_QUERIES, owner),
        LP_TOKENS: {
          HONEY_USDC: IBalancerBptToken__factory.connect(ADDRS.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC, owner),
          HONEY_BYUSD: IBalancerBptToken__factory.connect(ADDRS.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD, owner),
        },
      },
    },
  }
}
