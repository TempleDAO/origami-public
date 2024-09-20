import { ContractAddresses } from "./types";

export const CONTRACTS: ContractAddresses = {
  CORE: {
    MULTISIG: '0x781B4c57100738095222bd92D37B07ed034AB696',
    FEE_COLLECTOR: '0x781B4c57100738095222bd92D37B07ed034AB696',
    TOKEN_PRICES: {
      V1: '0x2f321ed425c82E74925488139e1556f9B76a2551',
      V2: '0x70e754531418461eF2366b72cd396337d2AD6D5d',
      V3: '0x633a7eB9b8912b22f3616013F3153de687F96074',
    },
  },
  ORACLES: {
    USDE_DAI: '0x820638ecd57B55e51CE6EaD7D137962E7A201dD9',
    SUSDE_DAI: '0x725314746e727f586E9FCA65AeD5dBe45aA71B99',
    WEETH_WETH: '0x221416CFa5A3CD92035E537ded1dD12d4d587c03',
    EZETH_WETH: '0x36B81ebd01C31643BAF132240C8Bc6874B329c4C',
    STETH_WETH: '0x645B0f55268eF561176f3247D06d0b7742f79819',
    WSTETH_WETH: '0x5fe2f174fe51474Cd198939C96e7dB65983EA307',
    WOETH_WETH: '0xba840136E489cB5eCf9D9988421F3a9F45e0c341',
    WETH_DAI: '0x633a7eB9b8912b22f3616013F3153de687F96074',
    WBTC_DAI: '0x5E0399B4C3c4C31036DcA08d53c0c5b5c29C113e',
    WETH_WBTC: '0x4633394E4Fd1175273845d7F0d6A5F613309d384',
    DAI_USD: '0xDb731EaaFA0FFA7854A24C2379585a85D768Ed5C',
    SDAI_DAI: '0x081F08945fd17C5470f7bCee23FB57aB1099428E',
    WETH_SDAI: '0xf102f0173707c6726543d65fA38025Eb72026c37',
    WBTC_SDAI: '0xAf7868a9BB72E16B930D50636519038d7F057470',
    PT_SUSDE_OCT24_USDE: '0x2ac430E52F47420A00984E11Ef0DDba80652419a',
    PT_SUSDE_OCT24_DAI: '0x2550d6424b46f78F4E31F1CCf88Da26dda7826C6',
    MKR_DAI: '',
    AAVE_USDC: '',
    SDAI_USDC: '',
    USD0pp_USD0: '',
    USD0pp_USDC: '',
    USD0_USDC: '',
    RSWETH_WETH: '',
    SUSDE_USD_INTERNAL: '',
    SDAI_USD_INTERNAL: '',
    SDAI_SUSDE: '',
  },
  SWAPPERS: {
    DIRECT_SWAPPER: '0xD3674dc273236213379207ca3Ac6b0f292c47Dd5',
    SUSDE_SWAPPER: '0x302563254A72B59d71DD5BC209e1e91b7a84E262',
  },
  FLASHLOAN_PROVIDERS: {
    SPARK: '0x8AFB0C54bAE39A5e56b984DF1C4b5702b2abf205',
    AAVE_V3_MAINNET_HAS_FEE: '',
    MORPHO: '0xC8eE801b35a82743BA7F314623962a2bBfdbC90A',
  },
  LOV_SUSDE_A: {
    OVERLORD_WALLET: '0xd42c38b2cebb59e77fc985d0cb0d340f15053bcd',
    MORPHO_BORROW_LEND: '0x6B9C4119796C80Ced5a3884027985Fd31830555b',
    TOKEN: '0xA8d14b3d9e2589CEA8644BB0f67EB90d21079f8B',
    MANAGER: '0x716473Fb4E7cD49c7d1eC7ec6d7490A03d9dA332',
  },
  LOV_SUSDE_B: {
    OVERLORD_WALLET: '0xca0678c3a9b1acb50276245ddda06c91ab072fdd',
    MORPHO_BORROW_LEND: '0x810090f35DFA6B18b5EB59d298e2A2443a2811E2',
    TOKEN: '0x2B8F5e69C35c1Aff4CCc71458CA26c2F313c3ed3',
    MANAGER: '0x9A8Ec3B44ee760b629e204900c86d67414a67e8f',
  },
  LOV_USDE_A: {
    OVERLORD_WALLET: '0xebf8629d589d5c6ef1ec055c1fa41ecb5c6e5c4f',
    MORPHO_BORROW_LEND: '0xa138575a030a2F4977D19Cc900781E7BE3fD2bc0',
    TOKEN: '0xB8d6D6b01bFe81784BE46e5771eF017Fa3c906d8',
    MANAGER: '0xf524930660f75CF602e909C15528d58459AB2A56',
  },
  LOV_USDE_B: {
    OVERLORD_WALLET: '0xcd745c7eb39472c804db981b1829c99ce0b26ce0',
    MORPHO_BORROW_LEND: '0x87E8f332f34984728Da4c0A008a495A5Ec4E09a2',
    TOKEN: '0x53E4DAFF2073f848DC3F7a8D7CC95b3607212A73',
    MANAGER: '0x1E2e9190Cea3A97b5Aa85d9757117F499D31C47d',
  },
  LOV_WEETH_A: {
    OVERLORD_WALLET: '0x40557e20e0ffb01849782a09fcb681d5e8d9d229',
    MORPHO_BORROW_LEND: '0x0BbfcD7a557FFB8A70CB0948FF680F0E573bbFf2',
    TOKEN: '0xa591098680B1e183C332Ea8e2612a2Cf2e6ABC17',
    MANAGER: '0xdABF214E5a833269c192D9d70efDdE174680628D',
  },
  LOV_EZETH_A: {
    OVERLORD_WALLET: '0xd9a1febccb928e6205952a167808d867567d5c92',
    MORPHO_BORROW_LEND: '0x862E3acDE54f01a4540C4505a4E199214Ff6cD49',
    TOKEN: '0x8786A226918A4c6Cd7B3463ca200f156C964031f',
    MANAGER: '0x37453c92a0E3C63949ba340ee213c6C97931F96D',
  },
  LOV_WSTETH_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0x81ED8e0325B17A266B2aF225570679cfd635d0bb',
    SPARK_BORROW_LEND: '0x6B763F54D260aFF608CbbAeD8721c96992eC24Db',
    MANAGER: '0xF48883F2ae4C4bf4654f45997fE47D73daA4da07',
  },
  LOV_WSTETH_B: {
    OVERLORD_WALLET: '',
    TOKEN: '',
    SPARK_BORROW_LEND: '',
    MANAGER: '',
  },
  LOV_WOETH_A: {
    OVERLORD_WALLET: '0x956442579a697f9a502fbbf589d8352536161fa0',
    MORPHO_BORROW_LEND: '0xA13d4a67745D4Ed129AF590c495897eE2C7F8Cfc',
    TOKEN: '0xEd8D7d3A98CB4ea6C91a80dcd2220719c264531f',
    MANAGER: '0x23228469b3439d81DC64e3523068976201bA08C3',
  },
  LOV_WETH_DAI_LONG_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0x27f7785b17c6B4d034094a1B16Bc928bD697f386',
    SPARK_BORROW_LEND: '0x1E53bea57Dd5dDa7bFf1a1180a2f64a5c9e222f5',
    MANAGER: '0x17f4B55A352Be71CC03856765Ad04147119Aa09B',
  },
  LOV_WETH_SDAI_SHORT_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0x81a5186946ce055a5ceeC93cd97C7e7EDe7Da922',
    SPARK_BORROW_LEND: '0x5EdB3Ff1EA450d1FF6d614F24f5C760761F7f688',
    MANAGER: '0x98F74b7C96497070ba5052E02832EF9892962e62',
  },
  LOV_WBTC_DAI_LONG_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0x5aA185fbEFc205072FaecC6B9D564383e761f8C2',
    SPARK_BORROW_LEND: '0x512a0E8bAeb6Ac3D52A11780c92517627005b0b1',
    MANAGER: '0x63275D081C4A77AE69f76c4952F9747a5559a519',
  },
  LOV_WBTC_SDAI_SHORT_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0x99aA73dA6309b8eC484eF2C95e96C131C1BBF7a0',
    SPARK_BORROW_LEND: '0x4B7099FD879435a087C364aD2f9E7B3f94d20bBe',
    MANAGER: '0x98721EFD3D09A7Ae662C4D63156286DF673FC50B',
  },
  LOV_WETH_WBTC_LONG_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0xbF97DEfeb6a387215E3e67DFb988c675c9bb1a29',
    SPARK_BORROW_LEND: '0x039d7496e432c6Aea4c24648a59318b3cbe09942',
    MANAGER: '0xaE7b7A1c6C4d859e19301ccAc2C6eD28A4C51288',
  },
  LOV_WETH_WBTC_SHORT_A: {
    OVERLORD_WALLET: '0x46167be270f2b44fbfa8b22d7226c520b943d037',
    TOKEN: '0x1A223F93131cD7d898c28Ee0B905C39Db474FA08',
    SPARK_BORROW_LEND: '0x9118EA4a52C6c7873729c8d8702cCd85E573f9E9',
    MANAGER: '0x77e6Bd5c1988d8d766698F9CeEa5C24559b999f8',
  },
  LOV_PT_SUSDE_OCT24_A: {
    OVERLORD_WALLET: '0x6f4C6D6f836394BB8c0f46121e963821B8B3a822',
    MORPHO_BORROW_LEND: '0x97915c43511f8cB4Fbe7Ea03B96EEe940eC4AF12',
    TOKEN: '0xC6A09F78CfB85275e5261200442b0B9AA9D4D0ce',
    MANAGER: '0xA002B84Ca3c9e8748209F286Ecf99300CA50161A',
  },
  LOV_MKR_DAI_LONG_A: {
    OVERLORD_WALLET: '',
    TOKEN: '',
    SPARK_BORROW_LEND: '',
    MANAGER: '',
  },
  LOV_AAVE_USDC_LONG_A: {
    OVERLORD_WALLET: '0x33776897f75dfe6865ba6ccf4cc049027d29a0c4',
    TOKEN: '',
    SPARK_BORROW_LEND: '',
    MANAGER: '',
  },
  LOV_SDAI_A: {
    OVERLORD_WALLET: '0x39a9e58ae15e70350eeb147d59f9182d4b891e4d',
    MORPHO_BORROW_LEND: '0xDF3D394669Fe433713D170c6DE85f02E260c1c34',
    TOKEN: '0xdE6d401E4B651F313edB7da0A11e072EEf4Ce7BE',
    MANAGER: '0xc387Db4203d81723367CFf6Bcd14Ad2099A7Fbce',
  },
  LOV_USD0pp_A: {
    OVERLORD_WALLET: '',
    MORPHO_BORROW_LEND: '',
    TOKEN: '',
    MANAGER: '',
  },
  LOV_RSWETH_A: {
    OVERLORD_WALLET: '',
    MORPHO_BORROW_LEND: '',
    TOKEN: '',
    MANAGER: '',
  },
  EXTERNAL: {
    WETH_TOKEN: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    WBTC_TOKEN: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
    INTERNAL_USD: '0x000000000000000000000000000000000000115d',
    MAKER_DAO: {
      DAI_TOKEN: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
      SDAI_TOKEN: '0x83F20F44975D03b1b09e64809B757c47f942BEeA',
      MKR_TOKEN: '0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2',
    },
    CIRCLE: {
      USDC_TOKEN: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    },
    ETHENA: {
      USDE_TOKEN: '0x4c9EDD5852cd905f086C759E8383e09bff1E68B3',
      SUSDE_TOKEN: '0x9D39A5DE30e57443BfF2A8307A4256c8797A3497',
    },
    ETHERFI: {
      WEETH_TOKEN: '0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee',
      LIQUIDITY_POOL: '0x308861A430be4cce5502d0A12724771Fc6DaF216',
    },
    RENZO: {
      EZETH_TOKEN: '0xbf5495Efe5DB9ce00f80364C8B423567e58d2110',
      RESTAKE_MANAGER: '0x74a09653A083691711cF8215a6ab074BB4e99ef5',
    },
    LIDO: {
      STETH_TOKEN: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84',
      WSTETH_TOKEN: '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0',
    },
    ORIGIN: {
      OETH_TOKEN: '0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3',
      WOETH_TOKEN: '0xDcEe70654261AF21C44c093C300eD3Bb97b78192',
    },
    USUAL: {
      USD0pp_TOKEN: '0x35D8949372D46B7a3D5A56006AE77B215fc69bC0',
      USD0_TOKEN: '0x73A15FeD60Bf67631dC6cd7Bc5B6e8da8190aCF5',
    },
    CURVE: {
      USD0pp_USD0_STABLESWAP_NG: '0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52',
      USD0_USDC_STABLESWAP_NG: '0x14100f81e33C33Ecc7CDac70181Fb45B6E78569F',
    },
    SWELL: {
      RSWETH_TOKEN: '0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0',
    },
    REDSTONE: {
      USDE_USD_ORACLE: '0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58',
      SUSDE_USD_ORACLE: '0xb99D174ED06c83588Af997c8859F93E83dD4733f',
      WEETH_WETH_ORACLE: '0x8751F736E94F6CD167e8C5B97E245680FbD9CC36',
      WEETH_USD_ORACLE: '0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136',
      EZETH_WETH_ORACLE: '0xF4a3e183F59D2599ee3DF213ff78b1B3b1923696',
    },
    CHAINLINK: {
      DAI_USD_ORACLE: '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9',
      ETH_USD_ORACLE: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
      BTC_USD_ORACLE: '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c',
      ETH_BTC_ORACLE: '0xAc559F25B1619171CbC396a50854A3240b6A4e99',
      STETH_ETH_ORACLE: '0x86392dC19c0b719886221c78AB11eb8Cf5c52812',
      MKR_USD_ORACLE: '0xec1D1B3b0443256cc3860e24a46F108e699484Aa',
      AAVE_USD_ORACLE: '0x547a514d5e3769680Ce22B2361c10Ea13619e8a9',
      USDC_USD_ORACLE: '0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6',
    },
    ORIGAMI_ORACLE_ADAPTERS: {
      RSWETH_ETH_EXCHANGE_RATE: '0xb2b18E668CE6326760e3B063f72684fdF2a2D582',
    },
    SPARK: {
      POOL_ADDRESS_PROVIDER: '0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE',
    },
    AAVE: {
      AAVE_TOKEN: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9',
      V3_MAINNET_POOL_ADDRESS_PROVIDER: '0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e',
      V3_LIDO_POOL_ADDRESS_PROVIDER: '0xcfBf336fe147D643B9Cb705648500e101504B16d',
    },
    MORPHO: {
      SINGLETON: '0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb',
      IRM: '0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC',
      ORACLE: {
        SUSDE_DAI: '0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25',
        USDE_DAI: '0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35',
        WEETH_WETH: '0x3fa58b74e9a8eA8768eb33c8453e9C2Ed089A40a',
        EZETH_WETH: '0x61025e2B0122ac8bE4e37365A4003d87ad888Cc3',
        WOETH_WETH: '0xb7948b5bEEe825E609990484A99340D8767B420e',
        PT_SUSDE_OCT24_DAI: '0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35',
        SDAI_USDC: '0xd6361d441EA8Fd285F7cd8b7d406b424e50c5429',
        USD0pp_USDC: '0x1325Eb089Ac14B437E78D5D481e32611F6907eF8',
        RSWETH_WETH: '0x56e2d0957d2376dF4A0519b91D1Fa19D2d63bd9b',
      },
    },
    PENDLE: {
      ORACLE: '0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2',
      ROUTER: '0x888888888889758F76e7103c6CbF23ABbF58F946',
      SUSDE_OCT24: {
        MARKET: '0xd1D7D99764f8a52Aff007b7831cc02748b2013b5',
        PT_TOKEN: '0x6c9f097e044506712B58EAC670c9a5fd4BCceF13',
      },
    },
    ONE_INCH: {
      ROUTER_V6: '0x111111125421cA6dc452d289314280a0f8842A65',
    },
    KYBERSWAP: {
      ROUTER_V2: '0x6131B5fae19EA4f9D964eAc0408E4408b66337b5',
    },
    COW_SWAP: {
      VAULT_RELAYER: '0xC92E8bdf79f0507f65a392b0ab4667716BFE0110',
      SETTLEMENT: '0x9008D19f58AAbD9eD0D60971565AA8510560ab41',
    },
  },

  MAINNET_TEST: {
    SWAPPERS: {
      COW_SWAPPER_1: '',
      COW_SWAPPER_2: '',
    },
  },
}
