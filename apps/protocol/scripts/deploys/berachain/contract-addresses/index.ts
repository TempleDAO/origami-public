import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
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
  OrigamiAutoStakingToErc4626,
  OrigamiAutoStakingToErc4626__factory,
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
    ORIBGT: {
      TOKEN: OrigamiDelegated4626Vault;
      MANAGER: OrigamiInfraredVaultManager;
      SWAPPER: OrigamiSwapperWithCallback;
    };
    INFRARED_AUTO_STAKING_HOHM_HONEY_A: OrigamiAutoStakingToErc4626;
  };

  FACTORIES: {
    INFRARED_AUTO_COMPOUNDER: {
      FACTORY: OrigamiInfraredAutoCompounderFactory;
    };
    INFRARED_AUTO_STAKING: {
      FACTORY: OrigamiAutoStakingFactory;
    };
  };

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
      BGT_TOKEN: IERC20Metadata;
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
        TOKEN: OrigamiOFT__factory.connect(ADDRS.VAULTS.hOHM.TOKEN.address, owner),
      },
      ORIBGT: {
        TOKEN: OrigamiDelegated4626Vault__factory.connect(ADDRS.VAULTS.ORIBGT.TOKEN.address, owner),
        MANAGER: OrigamiInfraredVaultManager__factory.connect(ADDRS.VAULTS.ORIBGT.MANAGER, owner),
        SWAPPER: OrigamiSwapperWithCallback__factory.connect(ADDRS.VAULTS.ORIBGT.SWAPPER, owner),
      },
      INFRARED_AUTO_STAKING_HOHM_HONEY_A: OrigamiAutoStakingToErc4626__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_HOHM_HONEY_A.VAULT.address, owner),
    },

    FACTORIES: {
      INFRARED_AUTO_COMPOUNDER: {
        FACTORY: OrigamiInfraredAutoCompounderFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY, owner),
      },
      INFRARED_AUTO_STAKING: {
        FACTORY: OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, owner),
      },
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
        BGT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.BGT_TOKEN, owner),
      },
      INFRARED: {
        IBGT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN, owner),
        IBGT_VAULT: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.IBGT_VAULT, owner),
        IBERA_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.INFRARED.IBERA_TOKEN, owner),
        REWARD_VAULTS: {
          HONEY_USDC: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.HONEY_USDC, owner),
          HONEY_BYUSD: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.BYUSD_HONEY_BEX, owner),
          OHM_HONEY: IInfraredVault__factory.connect(ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.OHM_HONEY, owner),
        },
      },
    },
  }
}
