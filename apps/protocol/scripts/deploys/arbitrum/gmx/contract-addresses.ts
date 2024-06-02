import { network } from "hardhat";

export interface GmxDeployedContracts {
    ORIGAMI: {
        OVERLORD_EOA: string,

        GMX: {
            oGMX: string,
            oGLP: string,
            
            ovGMX: string,
            ovGLP: string,
            
            GMX_EARN_ACCOUNT: string,
            GLP_PRIMARY_EARN_ACCOUNT: string,
            GLP_SECONDARY_EARN_ACCOUNT: string,

            GMX_MANAGER: string,
            GLP_MANAGER: string,

            GMX_REWARDS_AGGREGATOR: string,
            GLP_REWARDS_AGGREGATOR: string,
        },

        TOKEN_PRICES: string,
    },

    PRICES: {
        ETH_USD_ORACLE: string,
        BTC_USD_ORACLE: string,
        LINK_USD_ORACLE: string,
        UNI_USD_ORACLE: string,
        USDC_USD_ORACLE: string,
        USDT_USD_ORACLE: string,
        DAI_USD_ORACLE: string,
        FRAX_USD_ORACLE: string,

        // Avax pool
        AVAX_USD_ORACLE: string,

        // ETH/GMX Uni v3 on Arbitrum, AVAX/GMX Trader Joe pool on Avalanche
        NATIVE_GMX_POOL: string,
    },

    ZERO_EX_PROXY: string,

    GMX: {
        LIQUIDITY_POOL: {
            // Arbitrum tokens
            WETH_TOKEN: string,
            WBTC_TOKEN: string,
            LINK_TOKEN: string,
            UNI_TOKEN: string,
            USDC_TOKEN: string,
            USDC_E_TOKEN: string,
            USDT_TOKEN: string,
            DAI_TOKEN: string,
            FRAX_TOKEN: string,

            // Avalanche tokens
            WAVAX_TOKEN: string,
            WETH_E_TOKEN: string,
            BTC_B_TOKEN: string,
            WBTC_E_TOKEN: string,
        },
        CORE: {
            GLP_MANAGER: string,
            VAULT: string,
        },
        TOKENS: {
            GMX_TOKEN: string,
            GLP_TOKEN: string,
        },
        STAKING: {
            STAKED_GLP: string,
            GMX_ESGMX_VESTER: string,
            GLP_ESGMX_VESTER: string,
            GMX_REWARD_ROUTER: string,
            GLP_REWARD_ROUTER: string,
        },
    },
};

const GMX_DEPLOYED_CONTRACTS: {[key: string]: GmxDeployedContracts} = {
    arbitrum: {
        ORIGAMI: {
            OVERLORD_EOA: '0x93319b7059dd3e6c1ae4a2a3b825397fca81d627',

            TOKEN_PRICES: '0x534fe8c14d291950da1022d25D0f7d38Fe057ef4',

            GMX: {
                oGMX: '0x784f75C39bD7D3EBC377e64991e99178341c831D',
                oGLP: '0xb48aC9c5585e5F3c88c63CF9bcbAEdC921F76Df2',

                ovGMX: '0xe488A643E4b0Aaae60E4bdC02045a10d8a323bae',
                ovGLP: '0x7FC862A47BBCDe3812CA772Ae851d0A9D1619eDa',

                GMX_EARN_ACCOUNT: '0x9B517Eb5806b41af0ab49992985D35816612134e',
                GLP_PRIMARY_EARN_ACCOUNT: '0x73957eEf5b6F32208F274D6fEA07f60cF53Def9b',
                GLP_SECONDARY_EARN_ACCOUNT: '0xc3431D389999f2412B2570a66DA84CE59E5C2a94',

                GMX_MANAGER: '0xc0F9dd64D247f4Cb50C07632353896918bE79562',
                GLP_MANAGER: '0x58833508c3d057FE8901A7A2D89CeCcb3449ac24',

                GMX_REWARDS_AGGREGATOR: '0xcB6D80Ac3209626D5BC6cB9291eF6c4c321c82bA',
                GLP_REWARDS_AGGREGATOR: '0x643d715a0697c56629A25EC33C9BF5990D08317F',
            },
        },

        PRICES: {
            ETH_USD_ORACLE: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
            BTC_USD_ORACLE: '0x6ce185860a4963106506C203335A2910413708e9',
            LINK_USD_ORACLE: '0x86E53CF1B870786351Da77A57575e79CB55812CB',
            UNI_USD_ORACLE: '0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720',
            USDC_USD_ORACLE: '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3',
            USDT_USD_ORACLE: '0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7',
            DAI_USD_ORACLE: '0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB',
            FRAX_USD_ORACLE: '0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8',

            // GMX's FE also uses this ETH/GMX univ3 1% pool:
            // https://github.com/gmx-io/gmx-interface/blob/master/src/config/contracts.ts#L155
            NATIVE_GMX_POOL: '0x80A9ae39310abf666A87C743d6ebBD0E8C42158E',

            // Unused in Arbi
            AVAX_USD_ORACLE: '',
        },

        ZERO_EX_PROXY: '0xDef1C0ded9bec7F1a1670819833240f027b25EfF',

        GMX: {
            LIQUIDITY_POOL: {
                WETH_TOKEN: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
                WBTC_TOKEN: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
                LINK_TOKEN: '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4',
                UNI_TOKEN: '0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0',
                USDC_TOKEN: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
                USDC_E_TOKEN: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                USDT_TOKEN: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
                DAI_TOKEN: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
                FRAX_TOKEN: '0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F',

                // Not used in Arbitrum
                WAVAX_TOKEN: '',
                WETH_E_TOKEN: '',
                BTC_B_TOKEN: '',
                WBTC_E_TOKEN: '',
            },
            CORE: {
                GLP_MANAGER: '0x3963FfC9dff443c2A94f21b129D429891E32ec18',
                VAULT: '0x489ee077994B6658eAfA855C308275EAd8097C4A',
            },
            TOKENS: {
                GMX_TOKEN: '0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
                GLP_TOKEN: '0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258',
            },
            STAKING: {
                STAKED_GLP: '0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf',
                GMX_ESGMX_VESTER: '0x199070DDfd1CFb69173aa2F7e20906F26B363004',
                GLP_ESGMX_VESTER: '0xA75287d2f8b217273E7FCD7E86eF07D33972042E',
                GMX_REWARD_ROUTER: '0x159854e14A862Df9E39E1D128b8e5F70B4A3cE9B',
                GLP_REWARD_ROUTER: '0xB95DB5B167D75e6d04227CfFFA61069348d271F5',
            },
        }
    },
    avalanche: {
        ORIGAMI: {
            OVERLORD_EOA: '',

            TOKEN_PRICES: '',

            GMX: {
                oGMX: '',
                // yarn hardhat verify
                oGLP: '',
                // yarn hardhat verify

                ovGMX: '',
                // yarn hardhat verify
                ovGLP: '',
                // yarn hardhat verify

                GMX_EARN_ACCOUNT: '',
                // yarn hardhat verify
                GLP_PRIMARY_EARN_ACCOUNT: '',
                // yarn hardhat verify
                GLP_SECONDARY_EARN_ACCOUNT: '',
                // yarn hardhat verify

                GMX_MANAGER: '',
                // yarn hardhat verify
                GLP_MANAGER: '',
                // yarn hardhat verify

                GMX_REWARDS_AGGREGATOR: '',
                // yarn hardhat verify
                GLP_REWARDS_AGGREGATOR: '',
                // yarn hardhat verify
            },
        },

        PRICES: {
            AVAX_USD_ORACLE: '0x0a77230d17318075983913bc2145db16c7366156',
            ETH_USD_ORACLE: '0x976b3d034e162d8bd72d6b9c989d545b839003b0',
            BTC_USD_ORACLE: '0x2779d32d5166baaa2b2b658333ba7e6ec0c65743',
            USDC_USD_ORACLE: '0xf096872672f44d6eba71458d74fe67f9a77a23b9',

            NATIVE_GMX_POOL: '0x0c91a070f862666bBcce281346BE45766d874D98',

            // Unused in Avalanche
            LINK_USD_ORACLE: '',
            UNI_USD_ORACLE: '',
            USDT_USD_ORACLE: '',
            DAI_USD_ORACLE: '',
            FRAX_USD_ORACLE: '',
        },

        ZERO_EX_PROXY: '0xDef1C0ded9bec7F1a1670819833240f027b25EfF',

        GMX: {
            LIQUIDITY_POOL: {
                WAVAX_TOKEN: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
                WETH_E_TOKEN: '0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB',
                BTC_B_TOKEN: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
                WBTC_E_TOKEN: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
                USDC_TOKEN: '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
                USDC_E_TOKEN: '0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664',

                // Not used in Avalanche
                WETH_TOKEN: '',
                WBTC_TOKEN: '',
                LINK_TOKEN: '',
                UNI_TOKEN: '',
                USDT_TOKEN: '',
                DAI_TOKEN: '',
                FRAX_TOKEN: '',
            },
            CORE: {
                GLP_MANAGER: '0xD152c7F25db7F4B95b7658323c5F33d176818EE4',
                VAULT: '0x9ab2De34A33fB459b538c43f251eB825645e8595',
            },
            TOKENS: {
                GMX_TOKEN: '0x62edc0692BD897D2295872a9FFCac5425011c661',
                GLP_TOKEN: '0x01234181085565ed162a948b6a5e88758CD7c7b8',
            },
            STAKING: {
                STAKED_GLP: '0xaE64d55a6f09E4263421737397D1fdFA71896a69',
                GMX_ESGMX_VESTER: '0x472361d3cA5F49c8E633FB50385BfaD1e018b445',
                GLP_ESGMX_VESTER: '0x62331A7Bd1dfB3A7642B7db50B5509E57CA3154A',
                GMX_REWARD_ROUTER: '0x82147C5A7E850eA4E28155DF107F2590fD4ba327',
                GLP_REWARD_ROUTER: '0xB70B91CE0771d3f4c81D87660f71Da31d48eB3B3',
            },
        }
    },
    localhost: {
        ORIGAMI: {
            OVERLORD_EOA: '0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526',

            TOKEN_PRICES: '0x95401dc811bb5740090279Ba06cfA8fcF6113778',

            GMX: {
                oGMX: '0x998abeb3E57409262aE5b751f60747921B33613E',
                oGLP: '0x70e0bA845a1A0F2DA3359C97E0285013525FFC49',

                ovGMX: '0x4826533B4897376654Bb4d4AD88B7faFD0C98528',
                ovGLP: '0x99bbA657f2BbC93c02D617f8bA121cB8Fc104Acf',

                GMX_EARN_ACCOUNT: '0x8f86403A4DE0BB5791fa46B8e795C547942fE4Cf',
                GLP_PRIMARY_EARN_ACCOUNT: '0x9d4454B023096f34B160D6B654540c56A1F81688',
                GLP_SECONDARY_EARN_ACCOUNT: '0x5eb3Bc0a489C5A8288765d2336659EbCA68FCd00',

                GMX_MANAGER: '0x36C02dA8a0983159322a80FFE9F24b1acfF8B570',
                GLP_MANAGER: '0x809d550fca64d94Bd9F66E60752A544199cfAC3D',

                GMX_REWARDS_AGGREGATOR: '0x4c5859f0F772848b2D91F1D83E2Fe57935348029',
                GLP_REWARDS_AGGREGATOR: '0x1291Be112d480055DaFd8a610b7d1e203891C274',
            },
        },

        PRICES: {
            ETH_USD_ORACLE: '0x639fe6ab55c921f74e7fac1ee960c0b6293ba612',
            BTC_USD_ORACLE: '0x6ce185860a4963106506c203335a2910413708e9',
            LINK_USD_ORACLE: '0x86e53cf1b870786351da77a57575e79cb55812cb',
            UNI_USD_ORACLE: '0x9c917083fdb403ab5adbec26ee294f6ecada2720',
            USDC_USD_ORACLE: '0x50834f3163758fcc1df9973b6e91f0f0f0434ad3',
            USDT_USD_ORACLE: '0x3f3f5df88dc9f13eac63df89ec16ef6e7e25dde7',
            DAI_USD_ORACLE: '0xc5c8e77b397e531b8ec06bfb0048328b30e9ecfb',
            FRAX_USD_ORACLE: '0x0809e3d38d1b4214958faf06d8b1b1a2b73f2ab8',
            NATIVE_GMX_POOL: '0x80A9ae39310abf666A87C743d6ebBD0E8C42158E',

            // Unused in Arbi
            AVAX_USD_ORACLE: '',
        },

        ZERO_EX_PROXY: '0xDef1C0ded9bec7F1a1670819833240f027b25EfF',

        GMX: {
            LIQUIDITY_POOL: {
                WETH_TOKEN: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
                WBTC_TOKEN: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
                LINK_TOKEN: '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4',
                UNI_TOKEN: '0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0',
                USDC_TOKEN: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
                USDC_E_TOKEN: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                USDT_TOKEN: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
                DAI_TOKEN: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
                FRAX_TOKEN: '0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F',

                // Not used in Arbitrum
                WAVAX_TOKEN: '',
                WETH_E_TOKEN: '',
                BTC_B_TOKEN: '',
                WBTC_E_TOKEN: '',
            },
            CORE: {
                GLP_MANAGER: '0x3963FfC9dff443c2A94f21b129D429891E32ec18',
                VAULT: '0x489ee077994B6658eAfA855C308275EAd8097C4A',
            },
            TOKENS: {
                GMX_TOKEN: '0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
                GLP_TOKEN: '0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258',
            },
            STAKING: {
                STAKED_GLP: '0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf',
                GMX_ESGMX_VESTER: '0x199070DDfd1CFb69173aa2F7e20906F26B363004',
                GLP_ESGMX_VESTER: '0xA75287d2f8b217273E7FCD7E86eF07D33972042E',
                GMX_REWARD_ROUTER: '0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1',
                GLP_REWARD_ROUTER: '0xB95DB5B167D75e6d04227CfFFA61069348d271F5',
            },
        }
    },
}

export function getDeployedContracts(): GmxDeployedContracts {
    if (GMX_DEPLOYED_CONTRACTS[network.name] === undefined) {
      console.log(`No contracts configured for ${network.name}`);
      throw new Error(`No contracts configured for ${network.name}`);
    } else {
      return GMX_DEPLOYED_CONTRACTS[network.name];
    }
}
