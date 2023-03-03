import { network } from "hardhat";

export interface GmxDeployedContracts {
    ORIGAMI: {
        MULTISIG: string,
        GOV_TIMELOCK: string,
        OZ_BOT_EOA: string,

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
        // ETH/USD on Arbitrum, AVAX/USD on Avalanche
        NATIVE_USD_ORACLE: string,

        BNB_USD_ORACLE: string,
        BTC_USD_ORACLE: string,
        DAI_USD_ORACLE: string,

        // ETH/GMX Uni v3 on Arbitrum, AVAX/GMX Trader Joe pool on Avalanche
        NATIVE_GMX_POOL: string,
    },

    ZERO_EX_PROXY: string,

    GMX: {
        LIQUIDITY_POOL: {
            WETH_TOKEN: string,
            WETH_PRICE_FEED: string,
            BNB_TOKEN: string,
            BNB_PRICE_FEED: string,
            BTC_TOKEN: string,
            BTC_PRICE_FEED: string,
            DAI_TOKEN: string,
            DAI_PRICE_FEED: string,
        },
        TOKENS: {
            GLP_TOKEN: string,
            GMX_TOKEN: string,
            ESGMX_TOKEN: string,
            BNGMX_TOKEN: string,
        },
        CORE: {
            TIMELOCK: string,
            VAULT: string,
            VAULT_PRICE_FEED: string,
            VAULT_UTILS: string,
            VAULT_ERROR_CONTROLLER: string,
            USDG_TOKEN: string,
            ROUTER: string, 
            GLP_MANAGER: string,          
        },
        STAKING: {
            STAKED_GMX_TRACKER: string,
            STAKED_GMX_DISTRIBUTOR: string,
            BONUS_GMX_TRACKER: string,
            BONUS_GMX_DISTRIBUTOR: string,
            FEE_GMX_TRACKER: string,
            FEE_GMX_DISTRIBUTOR: string,
            FEE_GLP_TRACKER: string,
            FEE_GLP_DISTRIBUTOR: string,
            STAKED_GLP_TRACKER: string,
            STAKED_GLP_DISTRIBUTOR: string,
            STAKED_GLP: string,
            GMX_ESGMX_VESTER: string,
            GLP_ESGMX_VESTER: string,
            GMX_REWARD_ROUTER: string,
            GLP_REWARD_ROUTER: string,   
        },
    },

    TESTNET_MINTER: string,
};

const GMX_DEPLOYED_CONTRACTS: {[key: string]: GmxDeployedContracts} = {
    polygonMumbai: {
        ORIGAMI: {
            // A hot wallet, Mumbai isn't in Gnosis - ask @frontier for the PK if required.
            MULTISIG: '0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165',
            
            GOV_TIMELOCK: '0xFbC75D816E1B7DaAa0B5FF0b3e08299757ED2696',
            // yarn hardhat verify --network polygonMumbai 0xFbC75D816E1B7DaAa0B5FF0b3e08299757ED2696 --constructor-args arguments.js

            OZ_BOT_EOA: '0xc6ac5dda21252fa0847fbed04a6bf69873a117ac', // https://defender.openzeppelin.com/#/relay/e78b7ac1-09f3-457a-a0d7-61ca4c15feb4/settings

            TOKEN_PRICES: '0xF98C73Ce6eA51514E928A8c56eBAb3dC583A4994',
            // yarn hardhat verify --network polygonMumbai 0xF98C73Ce6eA51514E928A8c56eBAb3dC583A4994 30

            GMX: {
                oGMX: '0x58893971408b4ce2c3cc326A8697Eec4471a5615',
                // yarn hardhat verify --network polygonMumbai 0x58893971408b4ce2c3cc326A8697Eec4471a5615 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526
                oGLP: '0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad',
                // yarn hardhat verify --network polygonMumbai 0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249

                ovGMX: '0x43686bbe40E3b4EcB8A08D521D9C084da050bF51',
                // yarn hardhat verify --network polygonMumbai 0x43686bbe40E3b4EcB8A08D521D9C084da050bF51 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 "Origami GMX Investment Vault" ovGMX 0x58893971408b4ce2c3cc326A8697Eec4471a5615 0xF98C73Ce6eA51514E928A8c56eBAb3dC583A4994 5 604800
                ovGLP: '0x28E1e74661B6f354fcd11D3d01EDa798DcfaD894',
                // yarn hardhat verify --network polygonMumbai 0x28E1e74661B6f354fcd11D3d01EDa798DcfaD894 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 "Origami GLP Investment Vault" ovGLP 0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad 0xF98C73Ce6eA51514E928A8c56eBAb3dC583A4994 5 604800

                GMX_EARN_ACCOUNT: '0x38109f18387b477055d58738a89684767c74e2F0',
                // yarn hardhat verify --network polygonMumbai 0x38109f18387b477055d58738a89684767c74e2F0 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504
                GLP_PRIMARY_EARN_ACCOUNT: '0x9136f45ebd4b5C98b822F1DBb6585d0eF52d67e8',
                // yarn hardhat verify --network polygonMumbai 0x9136f45ebd4b5C98b822F1DBb6585d0eF52d67e8 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504
                GLP_SECONDARY_EARN_ACCOUNT: '0xdB5Bc5F5d6A2924e45b258d1c44Ab5535cb893D2',
                // yarn hardhat verify --network polygonMumbai 0xdB5Bc5F5d6A2924e45b258d1c44Ab5535cb893D2 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504

                GMX_MANAGER: '0x401a00e3196Be09A81E05B8c59d142B71f78f2A5',
                // yarn hardhat verify --network polygonMumbai 0x401a00e3196Be09A81E05B8c59d142B71f78f2A5 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504 0xCaC7A62Dd3D9D82d973C2DFBc5dBa6EFbb2BAf60 0x58893971408b4ce2c3cc326A8697Eec4471a5615 0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x38109f18387b477055d58738a89684767c74e2F0 0x0000000000000000000000000000000000000000
                GLP_MANAGER: '0xD1b9E7C18551B44A7E54943C8eF187Fe8bd51bF3',
                // yarn hardhat verify --network polygonMumbai 0xD1b9E7C18551B44A7E54943C8eF187Fe8bd51bF3 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504 0xCaC7A62Dd3D9D82d973C2DFBc5dBa6EFbb2BAf60 0x58893971408b4ce2c3cc326A8697Eec4471a5615 0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x0aFE49365F3283Bf52eCE995e132353059C2e7cE 0xdB5Bc5F5d6A2924e45b258d1c44Ab5535cb893D2

                GMX_REWARDS_AGGREGATOR: '0xD642e164563Bd4ba8c1bB433CAfC8d4916A2A390',
                // yarn hardhat verify --network polygonMumbai 0xD642e164563Bd4ba8c1bB433CAfC8d4916A2A390 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 1 0x401a00e3196Be09A81E05B8c59d142B71f78f2A5 0xD1b9E7C18551B44A7E54943C8eF187Fe8bd51bF3 0x43686bbe40E3b4EcB8A08D521D9C084da050bF51 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 0xb0Ab9A067EFBbAA8aa9c259131C07AfB8012B58B 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165
                GLP_REWARDS_AGGREGATOR: '0xB940160Ae4eD349D0c67fC1750D5d909d3bb2c0c',
                // yarn hardhat verify --network polygonMumbai 0xB940160Ae4eD349D0c67fC1750D5d909d3bb2c0c 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0 0x401a00e3196Be09A81E05B8c59d142B71f78f2A5 0xD1b9E7C18551B44A7E54943C8eF187Fe8bd51bF3 0x28E1e74661B6f354fcd11D3d01EDa798DcfaD894 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 0xb0Ab9A067EFBbAA8aa9c259131C07AfB8012B58B 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165
            },
        },

        PRICES: {
            NATIVE_USD_ORACLE: '0xbBd599E25FFa689A17058219d2570c7B0662fD1B',
            // yarn hardhat verify --network polygonMumbai 0xbBd599E25FFa689A17058219d2570c7B0662fD1B --constructor-args arguments.js
            // {
            //     roundId: 10,
            //     answer: 200000000000,
            //     startedAt: 1677745225,
            //     updatedAtLag: 1,
            //     answeredInRound: 5
            //   }

            DAI_USD_ORACLE: '0xa054D0B4327EAbBDA80A4A03C803Aa5eA517d488',
            // yarn hardhat verify --network polygonMumbai 0x70B87586666b331614f71A861906dC7bDD4cf786 --constructor-args arguments.js
            // {
            //     roundId: 10,
            //     answer: 100000000,
            //     startedAt: 1677745283,
            //     updatedAtLag: 1,
            //     answeredInRound: 5
            // }

            BNB_USD_ORACLE: '0x619f3D03217013aD16E02b9916DEC9Aee18975dF',
            // yarn hardhat verify --network polygonMumbai 0x619f3D03217013aD16E02b9916DEC9Aee18975dF --constructor-args arguments.js
            // {
            //     roundId: 10,
            //     answer: 30000000000,
            //     startedAt: 1677745341,
            //     updatedAtLag: 1,
            //     answeredInRound: 5
            //   }

            BTC_USD_ORACLE: '0x76Ea5f94aB3668bec4A5A98A2b21455C560117d5',
            // yarn hardhat verify --network polygonMumbai 0x76Ea5f94aB3668bec4A5A98A2b21455C560117d5 --constructor-args arguments.js
            // {
            //     roundId: 10,
            //     answer: 6000000000000,
            //     startedAt: 1677745377,
            //     updatedAtLag: 1,
            //     answeredInRound: 5
            //   }

            NATIVE_GMX_POOL: '0x9b49eb15E89210DAe44AbCf6c714b5F2De0b8C60',
            // yarn hardhat verify --network polygonMumbai 0x9b49eb15E89210DAe44AbCf6c714b5F2De0b8C60 46356982031850672597547879488562 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 0x3be80dD1aC2533d91330C82aae89Fe4D2E540146
        },

        // This uses a DummyDEX with a fixed price for testing.
        ZERO_EX_PROXY: '0xb0Ab9A067EFBbAA8aa9c259131C07AfB8012B58B',
        // yarn hardhat verify --network polygonMumbai 0xb0Ab9A067EFBbAA8aa9c259131C07AfB8012B58B 0x3be80dD1aC2533d91330C82aae89Fe4D2E540146 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 1000000000000000000000000000000 46356982031850672597547879488562

        GMX: {
            LIQUIDITY_POOL: {
                WETH_TOKEN: '0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 WETH WETH
                WETH_PRICE_FEED: '0x203c2D3e39aAe2903FaF51BD832C536E9a1174e1',
                // yarn hardhat verify --network polygonMumbai 0x203c2D3e39aAe2903FaF51BD832C536E9a1174e1
                BNB_TOKEN: '0x6352dEabF5AC3A6f14d7A1e19092fBddcda89625',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x6352dEabF5AC3A6f14d7A1e19092fBddcda89625 BNB BNB
                BNB_PRICE_FEED: '0xD81DF08f7D20D3f3fB02301EE022b51e13758A8F',
                // yarn hardhat verify --network polygonMumbai 0xD81DF08f7D20D3f3fB02301EE022b51e13758A8F
                BTC_TOKEN: '0x6C97233BBC1e8197688511586D46Ea7f98cBe775',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x6C97233BBC1e8197688511586D46Ea7f98cBe775 Bitcoin BTC
                BTC_PRICE_FEED: '0x8576eDf6F551388920bf42C2ceE484991216453b',
                // yarn hardhat verify --network polygonMumbai 0x8576eDf6F551388920bf42C2ceE484991216453b
                DAI_TOKEN: '0x5B0eeE1336cD3f5136D3DaF6970236365b9E9cd7',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x5B0eeE1336cD3f5136D3DaF6970236365b9E9cd7 Dai DAI
                DAI_PRICE_FEED: '0xd86687f017bB5658444A86CC762EAe51907172D2',
                // yarn hardhat verify --network polygonMumbai 0xd86687f017bB5658444A86CC762EAe51907172D2
            },
            TOKENS: {
                GLP_TOKEN: '0xbF93456E683455dA62ccB53b64b07252969A8B60',
                // yarn hardhat verify --network polygonMumbai 0xbF93456E683455dA62ccB53b64b07252969A8B60
                GMX_TOKEN: '0x3be80dD1aC2533d91330C82aae89Fe4D2E540146',
                // yarn hardhat verify --network polygonMumbai 0x3be80dD1aC2533d91330C82aae89Fe4D2E540146
                ESGMX_TOKEN: '0xCd2Aa63f764ab6f0f76f72C742043696C1A58F93',
                // yarn hardhat verify --network polygonMumbai 0xCd2Aa63f764ab6f0f76f72C742043696C1A58F93
                BNGMX_TOKEN: '0x0aeF8a48fe5cf06E367A4D8D43Aa1c1F626fa576',
                // yarn hardhat verify --network polygonMumbai 0x0aeF8a48fe5cf06E367A4D8D43Aa1c1F626fa576 "Bonus GMX" bnGMX 0
            },
            CORE: {
                TIMELOCK: '0x7839c9DB5e0fD1C52404Fa7b084046bf553ec370',
                // yarn hardhat verify --network polygonMumbai 0x7839c9DB5e0fD1C52404Fa7b084046bf553ec370 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 10 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0xD20d3ff386Bf31Ac321531D893Fb0A99a479e05D 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504 100000000000000000000000000 10 100
                VAULT: '0x3130243975773028d2394655571933cD43827f64',
                // yarn hardhat verify --network polygonMumbai 0x3130243975773028d2394655571933cD43827f64
                VAULT_PRICE_FEED: '0xc4C2F0ffE1750CC258859424AaC20b7Fd107537e',
                // yarn hardhat verify --network polygonMumbai 0xc4C2F0ffE1750CC258859424AaC20b7Fd107537e
                VAULT_UTILS: '0x7f55C5e61ca1f18baE3A6F7eD394B4B5CaBc5798',
                // yarn hardhat verify --network polygonMumbai 0x7f55C5e61ca1f18baE3A6F7eD394B4B5CaBc5798 0x3130243975773028d2394655571933cD43827f64
                VAULT_ERROR_CONTROLLER: '0xA1d71388591A9599f51a7c0D13aE84624643b356',
                // yarn hardhat verify --network polygonMumbai 0xA1d71388591A9599f51a7c0D13aE84624643b356
                USDG_TOKEN: '0xbaB83D22E4787519273AE9932097A7ddF9864b00',
                // yarn hardhat verify --network polygonMumbai 0xbaB83D22E4787519273AE9932097A7ddF9864b00 0x3130243975773028d2394655571933cD43827f64
                ROUTER: '0x0D14dBEBBa8D4A707b48b044d38eaFe01e3dFF90', 
                // yarn hardhat verify --network polygonMumbai 0x0D14dBEBBa8D4A707b48b044d38eaFe01e3dFF90 0x3130243975773028d2394655571933cD43827f64 0xbaB83D22E4787519273AE9932097A7ddF9864b00 0x6352dEabF5AC3A6f14d7A1e19092fBddcda89625
                GLP_MANAGER: '0xD20d3ff386Bf31Ac321531D893Fb0A99a479e05D',
                // yarn hardhat verify --network polygonMumbai 0xD20d3ff386Bf31Ac321531D893Fb0A99a479e05D 0x3130243975773028d2394655571933cD43827f64 0xbaB83D22E4787519273AE9932097A7ddF9864b00 0xbF93456E683455dA62ccB53b64b07252969A8B60 0x0000000000000000000000000000000000000000 900
            },
            STAKING: {
                STAKED_GMX_TRACKER: '0xD49738A2E7238E8eA1bC50227Fb07CffB9996f90',
                // yarn hardhat verify --network polygonMumbai 0xD49738A2E7238E8eA1bC50227Fb07CffB9996f90 "Staked GMX" sGMX
                STAKED_GMX_DISTRIBUTOR: '0x9d435b0890CA7B12c5B57174068A355aB59Cd837',
                // yarn hardhat verify --network polygonMumbai 0x9d435b0890CA7B12c5B57174068A355aB59Cd837 0xCd2Aa63f764ab6f0f76f72C742043696C1A58F93 0xD49738A2E7238E8eA1bC50227Fb07CffB9996f90
                BONUS_GMX_TRACKER: '0x278B1BE0e7Ca9cD2a05b0aA09De3AA794549d444',
                // yarn hardhat verify --network polygonMumbai 0x278B1BE0e7Ca9cD2a05b0aA09De3AA794549d444 "Staked + Bonus GMX" sbGMX
                BONUS_GMX_DISTRIBUTOR: '0xab54E904c4dA0Bd31f361df91DAbAf537253cBCa',
                // yarn hardhat verify --network polygonMumbai 0xab54E904c4dA0Bd31f361df91DAbAf537253cBCa 0x0aeF8a48fe5cf06E367A4D8D43Aa1c1F626fa576 0x278B1BE0e7Ca9cD2a05b0aA09De3AA794549d444
                FEE_GMX_TRACKER: '0xCcB9620F09A53e67669Eb5cb3fB41F713a803ffa',
                // yarn hardhat verify --network polygonMumbai 0xCcB9620F09A53e67669Eb5cb3fB41F713a803ffa "Staked + Bonus + Fee GMX" sbfGMX
                FEE_GMX_DISTRIBUTOR: '0x2Ffdf8B375E024BE2ACc773F5C37f517282BA789',
                // yarn hardhat verify --network polygonMumbai 0x2Ffdf8B375E024BE2ACc773F5C37f517282BA789 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 0xCcB9620F09A53e67669Eb5cb3fB41F713a803ffa
                FEE_GLP_TRACKER: '0x37cFF65E45B09379843F1d9D79B4e4C6138DBe7c',
                // yarn hardhat verify --network polygonMumbai 0x37cFF65E45B09379843F1d9D79B4e4C6138DBe7c "Fee GLP" fGLP
                FEE_GLP_DISTRIBUTOR: '0x0DdBa1E44cdD7beF201FcA51f4ed532a6329ac40',
                // yarn hardhat verify --network polygonMumbai 0x0DdBa1E44cdD7beF201FcA51f4ed532a6329ac40 0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249 0x37cFF65E45B09379843F1d9D79B4e4C6138DBe7c
                STAKED_GLP_TRACKER: '0x2239538cDC42F09DaF862df4a5Da60A95A3715cc',
                // yarn hardhat verify --network polygonMumbai 0x2239538cDC42F09DaF862df4a5Da60A95A3715cc "Fee + Staked GLP" fsGLP
                STAKED_GLP_DISTRIBUTOR: '0xB6534bd6abb275ea601bE593Fb4289F36D4b46DF',
                // yarn hardhat verify --network polygonMumbai 0xB6534bd6abb275ea601bE593Fb4289F36D4b46DF 0xCd2Aa63f764ab6f0f76f72C742043696C1A58F93 0x2239538cDC42F09DaF862df4a5Da60A95A3715cc
                STAKED_GLP: '0x9d4Da39fB7971Eb27e951E26eC820fC137E71475',
                // yarn hardhat verify --network polygonMumbai 0x9d4Da39fB7971Eb27e951E26eC820fC137E71475 0xbF93456E683455dA62ccB53b64b07252969A8B60 0xD20d3ff386Bf31Ac321531D893Fb0A99a479e05D 0x2239538cDC42F09DaF862df4a5Da60A95A3715cc 0x37cFF65E45B09379843F1d9D79B4e4C6138DBe7c
                GMX_ESGMX_VESTER: '0x2cB125201A1F26AC42bcd11D4dE8e0E2e20816EB',
                // yarn hardhat verify --network polygonMumbai 0x2cB125201A1F26AC42bcd11D4dE8e0E2e20816EB "Vested GMX" vGMX 31536000 0xCd2Aa63f764ab6f0f76f72C742043696C1A58F93 0xCcB9620F09A53e67669Eb5cb3fB41F713a803ffa 0x3be80dD1aC2533d91330C82aae89Fe4D2E540146 0xD49738A2E7238E8eA1bC50227Fb07CffB9996f90
                GLP_ESGMX_VESTER: '0x1C9Ead0F55751F5066975Bd10D760e5DC52F59Ef',
                // yarn hardhat verify --network polygonMumbai 0x1C9Ead0F55751F5066975Bd10D760e5DC52F59Ef "Vested GLP" vGLP 31536000 0xCd2Aa63f764ab6f0f76f72C742043696C1A58F93 0x2239538cDC42F09DaF862df4a5Da60A95A3715cc 0x3be80dD1aC2533d91330C82aae89Fe4D2E540146 0x2239538cDC42F09DaF862df4a5Da60A95A3715cc
                GMX_REWARD_ROUTER: '0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504',
                // yarn hardhat verify --network polygonMumbai 0x260ea0c7BCb732ed420d07b8ee13cC8c66DA2504
                GLP_REWARD_ROUTER: '0xCaC7A62Dd3D9D82d973C2DFBc5dBa6EFbb2BAf60',
                // yarn hardhat verify --network polygonMumbai 0xCaC7A62Dd3D9D82d973C2DFBc5dBa6EFbb2BAf60
            },
        },

        TESTNET_MINTER: '0x2B5ce096ce51Ff9EEF2D09a6d9a6e594D15e95F4',
        // yarn hardhat verify --network polygonMumbai 0x2B5ce096ce51Ff9EEF2D09a6d9a6e594D15e95F4  --constructor-args arguments.js
        // [
        //     {
        //       token: '0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249',
        //       amount: "10000000000000000000",
        //       mintType: 0
        //     },
        //     {
        //       token: '0x6352dEabF5AC3A6f14d7A1e19092fBddcda89625',
        //       amount: "67000000000000000000",
        //       mintType: 0
        //     },
        //     {
        //       token: '0x6C97233BBC1e8197688511586D46Ea7f98cBe775',
        //       amount: "400000000000000000",
        //       mintType: 0
        //     },
        //     {
        //       token: '0x5B0eeE1336cD3f5136D3DaF6970236365b9E9cd7',
        //       amount: "20000000000000000000000",
        //       mintType: 0
        //     },
        //     {
        //       token: '0x3be80dD1aC2533d91330C82aae89Fe4D2E540146',
        //       amount: "500000000000000000000",
        //       mintType: 0
        //     },
        //     {
        //       token: '0x9d4Da39fB7971Eb27e951E26eC820fC137E71475',
        //       amount: "20000000000000000000000",
        //       mintType: 1
        //     }
        //   ],
        // 86400
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
