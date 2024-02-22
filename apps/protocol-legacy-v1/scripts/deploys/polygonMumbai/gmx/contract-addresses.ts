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
            OVERLORD_EOA: '0xd3668b94e54472b5cdff2642da6a7b9d1d5c1864', // https://app.automation-templedao.link/

            TOKEN_PRICES: '0xfB720eAa483beF207400D6561b5E17b8d6f2BB2f',
            // yarn hardhat verify --network polygonMumbai 0xfB720eAa483beF207400D6561b5E17b8d6f2BB2f 30

            GMX: {
                oGMX: '0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61',
                // yarn hardhat verify --network polygonMumbai 0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526
                oGLP: '0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded',
                // yarn hardhat verify --network polygonMumbai 0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0xaDA4020481b166219DE50884dD710b3aD18573e4

                ovGMX: '0x084E1ceB358Fc9A78BB2799424A407419F28F3cf',
                // yarn hardhat verify --network polygonMumbai 0x084E1ceB358Fc9A78BB2799424A407419F28F3cf 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 "Origami GMX Investment Vault" ovGMX 0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61 0xfB720eAa483beF207400D6561b5E17b8d6f2BB2f 5 604800
                ovGLP: '0xE781bF69e3dfaB3E7161B3f718897BcbDE17539a',
                // yarn hardhat verify --network polygonMumbai 0xE781bF69e3dfaB3E7161B3f718897BcbDE17539a 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 "Origami GLP Investment Vault" ovGLP 0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded 0xfB720eAa483beF207400D6561b5E17b8d6f2BB2f 5 604800

                GMX_EARN_ACCOUNT: '0xB0D950bc9C87802c9691FF38d3baA1E4Bb2F8353',
                // yarn hardhat verify --network polygonMumbai 0xB0D950bc9C87802c9691FF38d3baA1E4Bb2F8353 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87
                GLP_PRIMARY_EARN_ACCOUNT: '0xa5765dC27a68A8D620443dA822E0AF8206a44112',
                // yarn hardhat verify --network polygonMumbai 0xa5765dC27a68A8D620443dA822E0AF8206a44112 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87
                GLP_SECONDARY_EARN_ACCOUNT: '0xEa2082f6168A5102A180575C32F822cE5EE5be25',
                // yarn hardhat verify --network polygonMumbai 0xEa2082f6168A5102A180575C32F822cE5EE5be25 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87

                GMX_MANAGER: '0x3b81Fcc218c0b29F28c72c053cBe4f286A7dcf67',
                // yarn hardhat verify --network polygonMumbai 0x3b81Fcc218c0b29F28c72c053cBe4f286A7dcf67 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87 0x2A8C68bc359e5ADA137512Cb6DA01D34B8fFf73f 0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61 0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0xB0D950bc9C87802c9691FF38d3baA1E4Bb2F8353 0x0000000000000000000000000000000000000000
                GLP_MANAGER: '0xf589Ee06C0967Fe36bbF7E9B8DA45B6954Df2AFf',
                // yarn hardhat verify --network polygonMumbai 0xf589Ee06C0967Fe36bbF7E9B8DA45B6954Df2AFf 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87 0x2A8C68bc359e5ADA137512Cb6DA01D34B8fFf73f 0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61 0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0xa5765dC27a68A8D620443dA822E0AF8206a44112 0xEa2082f6168A5102A180575C32F822cE5EE5be25

                GMX_REWARDS_AGGREGATOR: '0x647Ea2305C51831f5e42A072d0f1757cdd7fAE26',
                // yarn hardhat verify --network polygonMumbai 0x647Ea2305C51831f5e42A072d0f1757cdd7fAE26 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 1 0x3b81Fcc218c0b29F28c72c053cBe4f286A7dcf67 0xf589Ee06C0967Fe36bbF7E9B8DA45B6954Df2AFf 0x084E1ceB358Fc9A78BB2799424A407419F28F3cf 0xaDA4020481b166219DE50884dD710b3aD18573e4 0x7B174Bb59b6691fd3b9dfd5147E29a21972bd2E7 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165
                GLP_REWARDS_AGGREGATOR: '0x32E5b971618f6DC55263Bbcc1593949697B8481b',
                // yarn hardhat verify --network polygonMumbai 0x32E5b971618f6DC55263Bbcc1593949697B8481b 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0 0x3b81Fcc218c0b29F28c72c053cBe4f286A7dcf67 0xf589Ee06C0967Fe36bbF7E9B8DA45B6954Df2AFf 0xE781bF69e3dfaB3E7161B3f718897BcbDE17539a 0xaDA4020481b166219DE50884dD710b3aD18573e4 0x7B174Bb59b6691fd3b9dfd5147E29a21972bd2E7 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165
            },
        },

        PRICES: {
            NATIVE_USD_ORACLE: '0x50459F0d58c27495600f7504f37EEB943e6ce864',
            // yarn hardhat verify --network polygonMumbai 0x50459F0d58c27495600f7504f37EEB943e6ce864 --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: 200000000000,
            //       startedAt: 1687817398,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            DAI_USD_ORACLE: '0x2639F4617eaFF3B8Ab41bBB39772ed51C9A36F1e',
            // yarn hardhat verify --network polygonMumbai 0x2639F4617eaFF3B8Ab41bBB39772ed51C9A36F1e --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: 100000000,
            //       startedAt: 1687817518,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            BNB_USD_ORACLE: '0xDBED390230bE7A3b8d43fCf0D02fBcC66D334cF4',
            // yarn hardhat verify --network polygonMumbai 0xDBED390230bE7A3b8d43fCf0D02fBcC66D334cF4 --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: 30000000000,
            //       startedAt: 1687817546,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            BTC_USD_ORACLE: '0xAFa95cffaCF53A8cD2F189F8DC56f6d79BD881Ea',
            // yarn hardhat verify --network polygonMumbai 0xAFa95cffaCF53A8cD2F189F8DC56f6d79BD881Ea --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: 6000000000000,
            //       startedAt: 1687817570,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            NATIVE_GMX_POOL: '0xE07CaDe0ad5846D0D1d04affC45E5B1b482dA512',
            // yarn hardhat verify --network polygonMumbai 0xE07CaDe0ad5846D0D1d04affC45E5B1b482dA512 46356982031850672597547879488562 0xaDA4020481b166219DE50884dD710b3aD18573e4 0x79264843745dD81127B42Cffe30584A11a08C8F5
        },

        // This uses a DummyDEX with a fixed price for testing.
        ZERO_EX_PROXY: '0x7B174Bb59b6691fd3b9dfd5147E29a21972bd2E7',
        // yarn hardhat verify --network polygonMumbai 0x7B174Bb59b6691fd3b9dfd5147E29a21972bd2E7 0x79264843745dD81127B42Cffe30584A11a08C8F5 0xaDA4020481b166219DE50884dD710b3aD18573e4 1000000000000000000000000000000 46356982031850672597547879488562

        GMX: {
            LIQUIDITY_POOL: {
                WETH_TOKEN: '0xaDA4020481b166219DE50884dD710b3aD18573e4',
                // yarn hardhat verify --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken --network polygonMumbai 0xaDA4020481b166219DE50884dD710b3aD18573e4 WETH WETH
                WETH_PRICE_FEED: '0xa51Db0B24eE4B9dDdDa24dFEE950f4ad3267857A',
                // yarn hardhat verify --network polygonMumbai 0xa51Db0B24eE4B9dDdDa24dFEE950f4ad3267857A
                BNB_TOKEN: '0xDAAe5236C1b4cE822ac5beDDb597e8a6E0604b4e',
                // yarn hardhat verify --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken --network polygonMumbai 0xDAAe5236C1b4cE822ac5beDDb597e8a6E0604b4e BNB BNB
                BNB_PRICE_FEED: '0x2Cb28E1579E00f15289259BF7cA91551d43D578e',
                // yarn hardhat verify --network polygonMumbai 0x2Cb28E1579E00f15289259BF7cA91551d43D578e
                BTC_TOKEN: '0xc8Daa4E13780E59B50150980beF3469B7E0Cff25',
                // yarn hardhat verify --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken --network polygonMumbai 0xc8Daa4E13780E59B50150980beF3469B7E0Cff25 Bitcoin BTC
                BTC_PRICE_FEED: '0x2B8ad0726F23252d487EF2A002F8f15Ab952f788',
                // yarn hardhat verify --network polygonMumbai 0x2B8ad0726F23252d487EF2A002F8f15Ab952f788
                DAI_TOKEN: '0x133B3e03B9164d846204Bf1B7780F948c95A36Ea',
                // yarn hardhat verify --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken --network polygonMumbai 0x133B3e03B9164d846204Bf1B7780F948c95A36Ea Dai DAI
                DAI_PRICE_FEED: '0x587B5b90356A8b7c2Fb4a8858DA32f49FbCE1134',
                // yarn hardhat verify --network polygonMumbai 0x587B5b90356A8b7c2Fb4a8858DA32f49FbCE1134
            },
            TOKENS: {
                GLP_TOKEN: '0x34dd7eC18fcae1817DB0424E8b8B054DF68E8f37',
                // yarn hardhat verify --network polygonMumbai 0x34dd7eC18fcae1817DB0424E8b8B054DF68E8f37
                GMX_TOKEN: '0x79264843745dD81127B42Cffe30584A11a08C8F5',
                // yarn hardhat verify --network polygonMumbai 0x79264843745dD81127B42Cffe30584A11a08C8F5
                ESGMX_TOKEN: '0x16D97deE5d6EFFe6AFA95B17Ba68187B5AbEc758',
                // yarn hardhat verify --network polygonMumbai 0x16D97deE5d6EFFe6AFA95B17Ba68187B5AbEc758
                BNGMX_TOKEN: '0xa9867Fe9C86EeEf6f04e3bEF907b3aAC8A2e8E62',
                // yarn hardhat verify --network polygonMumbai 0xa9867Fe9C86EeEf6f04e3bEF907b3aAC8A2e8E62 "Bonus GMX" bnGMX 0
            },
            CORE: {
                TIMELOCK: '0x56D960eBAb6EdD84f40B4CFF726A1410ecc87553',
                // yarn hardhat verify --network polygonMumbai 0x56D960eBAb6EdD84f40B4CFF726A1410ecc87553 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 10 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x93eC8b912D3a9673B1991C97a498E754B8c468da 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87 100000000000000000000000000 10 100
                VAULT: '0xc0B5083647ABf89A2EA30307614909042d7c7182',
                // yarn hardhat verify --network polygonMumbai 0xc0B5083647ABf89A2EA30307614909042d7c7182
                VAULT_PRICE_FEED: '0xC750643Af431cE0370758F314E4B03b25B9F9D40',
                // yarn hardhat verify --network polygonMumbai 0xC750643Af431cE0370758F314E4B03b25B9F9D40
                VAULT_UTILS: '0x7d767323F9d524D5455027eA6592125c62824a5B',
                // yarn hardhat verify --network polygonMumbai 0x7d767323F9d524D5455027eA6592125c62824a5B 0xc0B5083647ABf89A2EA30307614909042d7c7182
                VAULT_ERROR_CONTROLLER: '0x26cB486c6458647b300dFf51BDee64cC02d5526e',
                // yarn hardhat verify --network polygonMumbai 0x26cB486c6458647b300dFf51BDee64cC02d5526e
                USDG_TOKEN: '0xab799112d6B9Dd85D2FeCc63CcAf9F7A2b4ed8F2',
                // yarn hardhat verify --network polygonMumbai 0xab799112d6B9Dd85D2FeCc63CcAf9F7A2b4ed8F2 0xc0B5083647ABf89A2EA30307614909042d7c7182
                ROUTER: '0x62D1AC3C1f85e4D86187Fe55E4E0b9672D2e12Bf', 
                // yarn hardhat verify --network polygonMumbai 0x62D1AC3C1f85e4D86187Fe55E4E0b9672D2e12Bf 0xc0B5083647ABf89A2EA30307614909042d7c7182 0xab799112d6B9Dd85D2FeCc63CcAf9F7A2b4ed8F2 0xDAAe5236C1b4cE822ac5beDDb597e8a6E0604b4e
                GLP_MANAGER: '0x93eC8b912D3a9673B1991C97a498E754B8c468da',
                // yarn hardhat verify --network polygonMumbai 0x93eC8b912D3a9673B1991C97a498E754B8c468da 0xc0B5083647ABf89A2EA30307614909042d7c7182 0xab799112d6B9Dd85D2FeCc63CcAf9F7A2b4ed8F2 0x34dd7eC18fcae1817DB0424E8b8B054DF68E8f37 0x0000000000000000000000000000000000000000 900
            },
            STAKING: {
                STAKED_GMX_TRACKER: '0x3a4EA601FA9ac2DfA40Bc18Bf41192F87667d9A1',
                // yarn hardhat verify --network polygonMumbai 0x3a4EA601FA9ac2DfA40Bc18Bf41192F87667d9A1 "Staked GMX" sGMX
                STAKED_GMX_DISTRIBUTOR: '0xB689F00751db756DFd3cB3F1eb7C35E3FaF8DEf2',
                // yarn hardhat verify --network polygonMumbai 0xB689F00751db756DFd3cB3F1eb7C35E3FaF8DEf2 0x16D97deE5d6EFFe6AFA95B17Ba68187B5AbEc758 0x3a4EA601FA9ac2DfA40Bc18Bf41192F87667d9A1
                BONUS_GMX_TRACKER: '0x7b0bD5722bbE6209EB65C4e0F5F15533A80CFFD3',
                // yarn hardhat verify --network polygonMumbai 0x7b0bD5722bbE6209EB65C4e0F5F15533A80CFFD3 "Staked + Bonus GMX" sbGMX
                BONUS_GMX_DISTRIBUTOR: '0x7AB96FeF76293180f08B9FB159D8Cd48CFb6fA5e',
                // yarn hardhat verify --network polygonMumbai 0x7AB96FeF76293180f08B9FB159D8Cd48CFb6fA5e 0xa9867Fe9C86EeEf6f04e3bEF907b3aAC8A2e8E62 0x7b0bD5722bbE6209EB65C4e0F5F15533A80CFFD3
                FEE_GMX_TRACKER: '0x7c164086dF2c433e9558736Bd2C470abcDB648ff',
                // yarn hardhat verify --network polygonMumbai 0x7c164086dF2c433e9558736Bd2C470abcDB648ff "Staked + Bonus + Fee GMX" sbfGMX
                FEE_GMX_DISTRIBUTOR: '0x2BA4EA8051A5fc3DF777E0dC4d1ceb6bD2165E8B',
                // yarn hardhat verify --network polygonMumbai 0x2BA4EA8051A5fc3DF777E0dC4d1ceb6bD2165E8B 0xaDA4020481b166219DE50884dD710b3aD18573e4 0x7c164086dF2c433e9558736Bd2C470abcDB648ff
                FEE_GLP_TRACKER: '0xB642758D8ebacB5206E7ea45E49D0f81a55c35D0',
                // yarn hardhat verify --network polygonMumbai 0xB642758D8ebacB5206E7ea45E49D0f81a55c35D0 "Fee GLP" fGLP
                FEE_GLP_DISTRIBUTOR: '0xEeBfAA4A678F6001bcF0e1fdDC3FeC8A71658f18',
                // yarn hardhat verify --network polygonMumbai 0xEeBfAA4A678F6001bcF0e1fdDC3FeC8A71658f18 0xaDA4020481b166219DE50884dD710b3aD18573e4 0xB642758D8ebacB5206E7ea45E49D0f81a55c35D0
                STAKED_GLP_TRACKER: '0x907be4992b2C8F0F1Ae85C98413A8F0EF4a3E651',
                // yarn hardhat verify --network polygonMumbai 0x907be4992b2C8F0F1Ae85C98413A8F0EF4a3E651 "Fee + Staked GLP" fsGLP
                STAKED_GLP_DISTRIBUTOR: '0x114697d41bfF76C629F0F827f88821A3a296Cfb0',
                // yarn hardhat verify --network polygonMumbai 0x114697d41bfF76C629F0F827f88821A3a296Cfb0 0x16D97deE5d6EFFe6AFA95B17Ba68187B5AbEc758 0x907be4992b2C8F0F1Ae85C98413A8F0EF4a3E651
                STAKED_GLP: '0x947d2B5ADc3882FA5D4E86E065f7340a5465Dd91',
                // yarn hardhat verify --network polygonMumbai 0x947d2B5ADc3882FA5D4E86E065f7340a5465Dd91 0x34dd7eC18fcae1817DB0424E8b8B054DF68E8f37 0x93eC8b912D3a9673B1991C97a498E754B8c468da 0x907be4992b2C8F0F1Ae85C98413A8F0EF4a3E651 0xB642758D8ebacB5206E7ea45E49D0f81a55c35D0
                GMX_ESGMX_VESTER: '0xC50f3a41d77dAe48e82af4644e0E82aF3F12ad39',
                // yarn hardhat verify --network polygonMumbai 0xC50f3a41d77dAe48e82af4644e0E82aF3F12ad39 "Vested GMX" vGMX 31536000 0x16D97deE5d6EFFe6AFA95B17Ba68187B5AbEc758 0x7c164086dF2c433e9558736Bd2C470abcDB648ff 0x79264843745dD81127B42Cffe30584A11a08C8F5 0x3a4EA601FA9ac2DfA40Bc18Bf41192F87667d9A1
                GLP_ESGMX_VESTER: '0xF11D4C5860eDb0dd70047CFB461A7B4261c6Ba03',
                // yarn hardhat verify --network polygonMumbai 0xF11D4C5860eDb0dd70047CFB461A7B4261c6Ba03 "Vested GLP" vGLP 31536000 0x16D97deE5d6EFFe6AFA95B17Ba68187B5AbEc758 0x907be4992b2C8F0F1Ae85C98413A8F0EF4a3E651 0x79264843745dD81127B42Cffe30584A11a08C8F5 0x907be4992b2C8F0F1Ae85C98413A8F0EF4a3E651
                GMX_REWARD_ROUTER: '0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87',
                // yarn hardhat verify --network polygonMumbai 0x12bc6F46926B8D7a7Ee79b2772f4AEf5cf409f87
                GLP_REWARD_ROUTER: '0x2A8C68bc359e5ADA137512Cb6DA01D34B8fFf73f',
                // yarn hardhat verify --network polygonMumbai 0x2A8C68bc359e5ADA137512Cb6DA01D34B8fFf73f
            },
        },

        TESTNET_MINTER: '0x1dED637E7F68fFEbC94930550E9E0D6D1eeE203a',
        // yarn hardhat verify --network polygonMumbai 0xD2509497D21E2F40B2612F9f2386A44E191770c1  --constructor-args arguments.js
        // [
        //     [
        //       {
        //         token: '0xee8405FBBa52312cE8783a09A646992D2E209C8a',
        //         amount: "10000000000000000000",
        //         mintType: 0
        //       },
        //       {
        //         token: '0xD80A1171E8E3400868051e7ced31550638660575',
        //         amount: "67000000000000000000",
        //         mintType: 0
        //       },
        //       {
        //         token: '0x436F79C41b477C28A292808523b3eb0E22202B7F',
        //         amount: "400000000000000000",
        //         mintType: 0
        //       },
        //       {
        //         token: '0x5da15e1fC595ff5991dD92447DB94Cfde78A08B8',
        //         amount: "20000000000000000000000",
        //         mintType: 0
        //       },
        //       {
        //         token: '0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948',
        //         amount: "500000000000000000000",
        //         mintType: 0
        //       },
        //       {
        //         token: '0x9f9d9e1f64618695142664280b6241442432e45b',
        //         amount: "20000000000000000000000",
        //         mintType: 1
        //       }
        //     ],
        //     86400
        //   ]
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
