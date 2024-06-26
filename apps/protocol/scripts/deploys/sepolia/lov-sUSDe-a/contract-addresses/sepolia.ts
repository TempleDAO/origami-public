import { ContractAddresses } from "./types";

export const CONTRACTS: ContractAddresses = {
  CORE: {
    MULTISIG: '0xF8Ab0fF572e48059c45eF3fa804e5A369d2b9b2B',
    FEE_COLLECTOR: '0xF8Ab0fF572e48059c45eF3fa804e5A369d2b9b2B',
    OVERLORD: '0xd42c38b2cebb59e77fc985d0cb0d340f15053bcd',
    TOKEN_PRICES: '0x9Fd18877aD6F966f92Dd7597ae27c535f169A296',
    SWAPPER_1INCH: '0xE885aA4b7c76960e260E328aB0702908792B94D9',
  },
  ORACLES: {
    USDE_DAI: '0x2e46909E58F4386a86187410aC4e7AEf5a14092E',
    SUSDE_DAI: '0x76f98538c1D05A19f6B1154382268B2bCb9043C0',
  },
  LOV_SUSDE: {
    TOKEN: '0x00fc693CfD49B02cE3B9Dc5a7999B05405c2efb7',
    MORPHO_BORROW_LEND: '0x761f18fA1443bD9a473F4e8eFB9Df1AacB75Ea34',
    MANAGER: '0x3D8975cD49c88d6151B707c6d017f034587Ac735',
  },
  EXTERNAL: {
    MAKER_DAO: {
      DAI_TOKEN: '0x50B44A8e5f299A453Fc7d8862Ffa09A248274817',
    },
    ETHENA: {
      USDE_TOKEN: '0xba96b29603af0b7B2d02f0D5058A238b531Ac9E3',
      SUSDE_TOKEN: '0x5B35262A5F648c12D38f82FcD693b9aEE12E92B2',
    },
    REDSTONE: {
      USDE_USD_ORACLE: '0x8a2ab97A54984F7538122669ee819CcF02687D7d',
      SUSDE_USD_ORACLE: '0xdafFc8AA780213B8F828DdAE75fCe0900b773e38',
    },
    MORPHO: {
      SINGLETON: '0x5B4051818B02B6f094907c91ed228818aabAaa24',
      IRM: '0xe230568CcA3418256f7F3ad20eA7ceD796a00189',
      ORACLE: '0x2C7784B396Ae31395E7B01a5CA2eAB58c7aF39ef',
    }
  },
}
