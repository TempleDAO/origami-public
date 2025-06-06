import { ContractAddresses } from "./types";

export const CONTRACTS: ContractAddresses = {
  CORE: {
    MULTISIG: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    FEE_COLLECTOR: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN_PRICES: {
      V3: '0xD21779985da1677df0fFD08a610E905E3F1eA3BD',
    },
  },
  LOV_HONEY_A: {
    OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN: '0x55167758Dd9d7440d7A6C8b2C2315F102C22d42E',
    MANAGER: '0x6240b357391A916492AEEd97C252C715ABC53616',
  },
  LOV_WBERA_LONG_A: {
    OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN: '0x0f3dE1277367843714b5B70d2737F4a0A75b6269',
    MANAGER: '0xfb06123ADeb9f6f84843090D60309f37bdd0668a',
  },
  LOV_YEET_A: {
    OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN: '0xB3AA5490F7933C5Fed499312B8E77a59cE917914',
    MANAGER: '0xC6981CAF323bce127960cE3d444FA04E87387F3B',
  },
  LOV_WBTC_LONG_A: {
    OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN: '0xb01dD016DF161D28D2785e0Ac449fdf59612655d',
    MANAGER: '0x8279c6D22aFeecf6c06b44714fd9dF12C3b45feE',
  },
  LOV_WETH_LONG_A: {
    OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN: '0xC85Fa2A6A2fDb75Aac44D24875787B1B01440dfE',
    MANAGER: '0xA76b74fA7B1d1562E4076C3aF30527A1F7Cc32da',
  },
  LOV_LOCKS_A: {
    OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
    TOKEN: '0x44c4667cE983870CE8E013C87b2bE1fC37f2875d',
    MANAGER: '0x779d3Bc1A408dE767887122279fadc2A9AC3CAaF',
  },

  VAULTS: {
    BOYCO_HONEY_A: {
      OVERLORD_WALLET: '0xE00F5CB480AaAECb749dA37cb13Ee3408AF13d06',
      BEX_POOL_HELPER: '0x971AeEBf5057F17DB00DCddc2804186a858CF453',
      BERA_REWARDS_STAKER: '0x2606e63C9F84E833b2e7739224a050320f9b4F6e',
      TOKEN: '0x3FBfb89a9b7f6183e58a3859e8cF8999d48BDc91',
      MANAGER: '0x6238F98E14E7B0a05ACfBaBc1099181CF5ae8C09',
    },
  },

  EXTERNAL: {
    WETH_TOKEN: '0x6E1E9896e93F7A71ECB33d4386b49DeeD67a231A',
    WBTC_TOKEN: "0x286F1C3f0323dB9c91D1E8f45c8DF2d065AB5fae",
    CIRCLE: {
      USDC_TOKEN: '0xd6D83aF58a19Cd14eF3CF6fe848C9A4d21e5727c',
    },
    BERACHAIN: {
      WBERA_TOKEN: '0x7507c1dc16935B82698e4C63f2746A2fCf994dF8',
      HONEY_TOKEN: '0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03',
      HONEY_MINTER: '0xAd1782b2a7020631249031618fB1Bd09CD926b31',
      BGT_TOKEN: '0xbDa130737BDd9618301681329bF2e46A016ff9Ad',
      BEX: {
        VAULT: '0xAB827b1Cc3535A9e549EE387A6E9C3F02F481B49',
        QUERY_HELPER: '0x8685CE9Db06D40CBa73e3d09e6868FE476B5dC89',
        HONEY_USDC_LP_TOKEN: '0xD69ADb6FB5fD6D06E6ceEc5405D95A37F96E3b96',
        HONEY_USDC_REWARDS_VAULT: '0xe3b9B72ba027FD6c514C0e5BA075Ac9c77C23Afa',
      },
    },
    GOLDILOCKS: {
      LOCKS_TOKEN: '0xC94ecBfE16E337f6e606dcd86B8A5eaDbAe7A337',
    },
    YEET: {
      YEET_TOKEN: '0x1740F679325ef3686B2f574e392007A92e4BeD41',
    },
  },
}
