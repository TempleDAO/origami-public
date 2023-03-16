import { network } from "hardhat";

export interface GmxDeployedContracts {
    ORIGAMI: {
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
            OZ_BOT_EOA: '0xc6ac5dda21252fa0847fbed04a6bf69873a117ac', // https://defender.openzeppelin.com/#/relay/e78b7ac1-09f3-457a-a0d7-61ca4c15feb4/settings

            TOKEN_PRICES: '0x97EDBdCB4D4bD0bC3b784117db2970Aa27D2C6a8',
            // yarn hardhat verify --network polygonMumbai 0x97EDBdCB4D4bD0bC3b784117db2970Aa27D2C6a8 30

            GMX: {
                oGMX: '0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45',
                // yarn hardhat verify --network polygonMumbai 0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526
                oGLP: '0xacfee3A66337067F75151637D0DefEd09E880914',
                // yarn hardhat verify --network polygonMumbai 0xacfee3A66337067F75151637D0DefEd09E880914 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0xee8405FBBa52312cE8783a09A646992D2E209C8a

                ovGMX: '0x500244EDee4AfCa6a1be7E28010719D9bcB3CB3e',
                // yarn hardhat verify --network polygonMumbai 0x500244EDee4AfCa6a1be7E28010719D9bcB3CB3e 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 "Origami GMX Investment Vault" ovGMX 0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45 0x97EDBdCB4D4bD0bC3b784117db2970Aa27D2C6a8 5 604800
                ovGLP: '0x7a8108A11949aa9F6395476F160304269A5EE48b',
                // yarn hardhat verify --network polygonMumbai 0x7a8108A11949aa9F6395476F160304269A5EE48b 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 "Origami GLP Investment Vault" ovGLP 0xacfee3A66337067F75151637D0DefEd09E880914 0x97EDBdCB4D4bD0bC3b784117db2970Aa27D2C6a8 5 604800

                GMX_EARN_ACCOUNT: '0x14Ab8d6Af3c6004B7A5005528A837b03853bA593',
                // yarn hardhat verify --network polygonMumbai 0x14Ab8d6Af3c6004B7A5005528A837b03853bA593 0x0258d2d4D7bA794122539785722c1a65399cfA29
                GLP_PRIMARY_EARN_ACCOUNT: '0xA8E4c1Ce9B980734e814FBE979632e7fB6913096',
                // yarn hardhat verify --network polygonMumbai 0xA8E4c1Ce9B980734e814FBE979632e7fB6913096 0x0258d2d4D7bA794122539785722c1a65399cfA29
                GLP_SECONDARY_EARN_ACCOUNT: '0x9dc9d0a95100c72bF6fcD66ef0a6A878bb83c858',
                // yarn hardhat verify --network polygonMumbai 0x9dc9d0a95100c72bF6fcD66ef0a6A878bb83c858 0x0258d2d4D7bA794122539785722c1a65399cfA29

                GMX_MANAGER: '0x35696286529EBB88c5c53ADe87a4BdCF30b3c8d9',
                // yarn hardhat verify --network polygonMumbai 0x35696286529EBB88c5c53ADe87a4BdCF30b3c8d9 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x0258d2d4D7bA794122539785722c1a65399cfA29 0x0909C4C94F0120DCa998639c9a5F8A068185EEA8 0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45 0xacfee3A66337067F75151637D0DefEd09E880914 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x14Ab8d6Af3c6004B7A5005528A837b03853bA593 0x0000000000000000000000000000000000000000
                GLP_MANAGER: '0x1d8000368122bD16a1251B9b0fe2367C1cd247d1',
                // yarn hardhat verify --network polygonMumbai 0x1d8000368122bD16a1251B9b0fe2367C1cd247d1 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0x0258d2d4D7bA794122539785722c1a65399cfA29 0x0909C4C94F0120DCa998639c9a5F8A068185EEA8 0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45 0xacfee3A66337067F75151637D0DefEd09E880914 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0xA8E4c1Ce9B980734e814FBE979632e7fB6913096 0x9dc9d0a95100c72bF6fcD66ef0a6A878bb83c858

                GMX_REWARDS_AGGREGATOR: '0x48165A1Ba49584eDF7038497d6D65A4756e43e55',
                // yarn hardhat verify --network polygonMumbai 0x48165A1Ba49584eDF7038497d6D65A4756e43e55 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 1 0x35696286529EBB88c5c53ADe87a4BdCF30b3c8d9 0x1d8000368122bD16a1251B9b0fe2367C1cd247d1 0x500244EDee4AfCa6a1be7E28010719D9bcB3CB3e 0xee8405FBBa52312cE8783a09A646992D2E209C8a 0x5923eD1131Bf82C7e89716fd797687fE9174a86b 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165
                GLP_REWARDS_AGGREGATOR: '0x4276a5D4AAB00702Ac4b28ff8A0228e0e76E46d6',
                // yarn hardhat verify --network polygonMumbai 0x4276a5D4AAB00702Ac4b28ff8A0228e0e76E46d6 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526 0 0x35696286529EBB88c5c53ADe87a4BdCF30b3c8d9 0x1d8000368122bD16a1251B9b0fe2367C1cd247d1 0x7a8108A11949aa9F6395476F160304269A5EE48b 0xee8405FBBa52312cE8783a09A646992D2E209C8a 0x5923eD1131Bf82C7e89716fd797687fE9174a86b 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165
            },
        },

        PRICES: {
            NATIVE_USD_ORACLE: '0x3f73571Fa83301A0Ff52058504416fB48F0fAca5',
            // yarn hardhat verify --network polygonMumbai 0x3f73571Fa83301A0Ff52058504416fB48F0fAca5 --constructor-args arguments.js
            // [
            // {
            //     roundId: 10,
            //     answer: "200000000000",
            //     startedAt: 1678221225,
            //     updatedAtLag: 1,
            //     answeredInRound: 5
            // },
            // 8]

            DAI_USD_ORACLE: '0x5b44Ff1400188eB1A2b2f7e34AE13a95AE412818',
            // yarn hardhat verify --network polygonMumbai 0x5b44Ff1400188eB1A2b2f7e34AE13a95AE412818 --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: "100000000",
            //       startedAt: 1678221795,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            BNB_USD_ORACLE: '0x12B05823b65015D2EE0bdEbc9534db88fE42acF2',
            // yarn hardhat verify --network polygonMumbai 0x12B05823b65015D2EE0bdEbc9534db88fE42acF2 --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: "30000000000",
            //       startedAt: 1678221887,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            BTC_USD_ORACLE: '0xE7b34CE7BEe7da1296e7d3Db62420831ccA6B83d',
            // yarn hardhat verify --network polygonMumbai 0xE7b34CE7BEe7da1296e7d3Db62420831ccA6B83d --constructor-args arguments.js
            // [
            //     {
            //       roundId: 10,
            //       answer: "6000000000000",
            //       startedAt: 1678221957,
            //       updatedAtLag: 1,
            //       answeredInRound: 5
            //     },
            //     8
            //   ]

            NATIVE_GMX_POOL: '0x6F89ecB3bFDCeFB9C2a2afD03638EeC20812ab59',
            // yarn hardhat verify --network polygonMumbai 0x6F89ecB3bFDCeFB9C2a2afD03638EeC20812ab59 46356982031850672597547879488562 0xee8405FBBa52312cE8783a09A646992D2E209C8a 0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948
        },

        // This uses a DummyDEX with a fixed price for testing.
        ZERO_EX_PROXY: '0x5923eD1131Bf82C7e89716fd797687fE9174a86b',
        // yarn hardhat verify --network polygonMumbai 0x5923eD1131Bf82C7e89716fd797687fE9174a86b 0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948 0xee8405FBBa52312cE8783a09A646992D2E209C8a 1000000000000000000000000000000 46356982031850672597547879488562

        GMX: {
            LIQUIDITY_POOL: {
                WETH_TOKEN: '0xee8405FBBa52312cE8783a09A646992D2E209C8a',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0xee8405FBBa52312cE8783a09A646992D2E209C8a WETH WETH
                WETH_PRICE_FEED: '0x5d1d02ee8eDcb18737BC6a56dE617Bf940Ba7A0A',
                // yarn hardhat verify --network polygonMumbai 0x5d1d02ee8eDcb18737BC6a56dE617Bf940Ba7A0A
                BNB_TOKEN: '0xD80A1171E8E3400868051e7ced31550638660575',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0xD80A1171E8E3400868051e7ced31550638660575 BNB BNB
                BNB_PRICE_FEED: '0x775B4F36B1200a249Eb59E8c845E0aBf8842e7Ec',
                // yarn hardhat verify --network polygonMumbai 0x775B4F36B1200a249Eb59E8c845E0aBf8842e7Ec
                BTC_TOKEN: '0x436F79C41b477C28A292808523b3eb0E22202B7F',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x436F79C41b477C28A292808523b3eb0E22202B7F Bitcoin BTC
                BTC_PRICE_FEED: '0x87c903765ebeb7ebd7a62CB530c1B517C7237fE0',
                // yarn hardhat verify --network polygonMumbai 0x87c903765ebeb7ebd7a62CB530c1B517C7237fE0
                DAI_TOKEN: '0x5da15e1fC595ff5991dD92447DB94Cfde78A08B8',
                // yarn hardhat verify --network polygonMumbai --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x5da15e1fC595ff5991dD92447DB94Cfde78A08B8 Dai DAI
                DAI_PRICE_FEED: '0x4154E4749823F6172695EF7677e7d6e8582279A9',
                // yarn hardhat verify --network polygonMumbai 0x4154E4749823F6172695EF7677e7d6e8582279A9
            },
            TOKENS: {
                GLP_TOKEN: '0x08Ea28a92c205A21D7CdF48000C5aAB466b080DA',
                // yarn hardhat verify --network polygonMumbai 0x08Ea28a92c205A21D7CdF48000C5aAB466b080DA
                GMX_TOKEN: '0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948',
                // yarn hardhat verify --network polygonMumbai 0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948
                ESGMX_TOKEN: '0x29dC9D44063ac86E2C6a3B407FD1d46626a3CFEe',
                // yarn hardhat verify --network polygonMumbai 0x29dC9D44063ac86E2C6a3B407FD1d46626a3CFEe
                BNGMX_TOKEN: '0x35CBc1e5a4DbE48745F09995bbf83d8A8f4f3B16',
                // yarn hardhat verify --network polygonMumbai 0x35CBc1e5a4DbE48745F09995bbf83d8A8f4f3B16 "Bonus GMX" bnGMX 0
            },
            CORE: {
                TIMELOCK: '0x19A736f1E9D97adfbb43fFDf83bB444007a44241',
                // yarn hardhat verify --network polygonMumbai 0x19A736f1E9D97adfbb43fFDf83bB444007a44241 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 10 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x1BCD9aC0BF12162183971Ff166A46c730ac3F2c2 0x0258d2d4D7bA794122539785722c1a65399cfA29 100000000000000000000000000 10 100
                VAULT: '0x1b5E9D37ccD409a6706c6EA47A580d24CE387Ceb',
                // yarn hardhat verify --network polygonMumbai 0x1b5E9D37ccD409a6706c6EA47A580d24CE387Ceb
                VAULT_PRICE_FEED: '0x8B89518e19CBd601cFEc8824fB9629466C120F8e',
                // yarn hardhat verify --network polygonMumbai 0x8B89518e19CBd601cFEc8824fB9629466C120F8e
                VAULT_UTILS: '0xA602a3C1D0bE6Ce61AAF5F6aAfadB7504938faB1',
                // yarn hardhat verify --network polygonMumbai 0xA602a3C1D0bE6Ce61AAF5F6aAfadB7504938faB1 0x1b5E9D37ccD409a6706c6EA47A580d24CE387Ceb
                VAULT_ERROR_CONTROLLER: '0xb7A5A6a3b1C521f747007d7a0961455c5836d228',
                // yarn hardhat verify --network polygonMumbai 0xb7A5A6a3b1C521f747007d7a0961455c5836d228
                USDG_TOKEN: '0xC906b6eb5454Eaa63033FdBE63A65210afAFC48e',
                // yarn hardhat verify --network polygonMumbai 0xC906b6eb5454Eaa63033FdBE63A65210afAFC48e 0x1b5E9D37ccD409a6706c6EA47A580d24CE387Ceb
                ROUTER: '0xe2fC9D1f4b60Babe623aD353B13E6d5395B708aB', 
                // yarn hardhat verify --network polygonMumbai 0xe2fC9D1f4b60Babe623aD353B13E6d5395B708aB 0x1b5E9D37ccD409a6706c6EA47A580d24CE387Ceb 0xC906b6eb5454Eaa63033FdBE63A65210afAFC48e 0xD80A1171E8E3400868051e7ced31550638660575
                GLP_MANAGER: '0x1BCD9aC0BF12162183971Ff166A46c730ac3F2c2',
                // yarn hardhat verify --network polygonMumbai 0x1BCD9aC0BF12162183971Ff166A46c730ac3F2c2 0x1b5E9D37ccD409a6706c6EA47A580d24CE387Ceb 0xC906b6eb5454Eaa63033FdBE63A65210afAFC48e 0x08Ea28a92c205A21D7CdF48000C5aAB466b080DA 0x0000000000000000000000000000000000000000 900
            },
            STAKING: {
                STAKED_GMX_TRACKER: '0x8C6C3899955E0A0ceB02Ba811B679822aa496157',
                // yarn hardhat verify --network polygonMumbai 0x8C6C3899955E0A0ceB02Ba811B679822aa496157 "Staked GMX" sGMX
                STAKED_GMX_DISTRIBUTOR: '0xb1B7D7DA88e36b315209a174cCF1412913d3a04a',
                // yarn hardhat verify --network polygonMumbai 0xb1B7D7DA88e36b315209a174cCF1412913d3a04a 0x29dC9D44063ac86E2C6a3B407FD1d46626a3CFEe 0x8C6C3899955E0A0ceB02Ba811B679822aa496157
                BONUS_GMX_TRACKER: '0x305fCBAa7A6aFAF10706584c1a80857717Bf19cA',
                // yarn hardhat verify --network polygonMumbai 0x305fCBAa7A6aFAF10706584c1a80857717Bf19cA "Staked + Bonus GMX" sbGMX
                BONUS_GMX_DISTRIBUTOR: '0x0bea5e0F0cfb405B57a4DD9B850a6ba14C6B26C3',
                // yarn hardhat verify --network polygonMumbai 0x0bea5e0F0cfb405B57a4DD9B850a6ba14C6B26C3 0x35CBc1e5a4DbE48745F09995bbf83d8A8f4f3B16 0x305fCBAa7A6aFAF10706584c1a80857717Bf19cA
                FEE_GMX_TRACKER: '0x0EB69bc02addF4ce20Da4E3720886EFc24057EDc',
                // yarn hardhat verify --network polygonMumbai 0x0EB69bc02addF4ce20Da4E3720886EFc24057EDc "Staked + Bonus + Fee GMX" sbfGMX
                FEE_GMX_DISTRIBUTOR: '0x25E4144008b2572C35e244677B9f198D54617268',
                // yarn hardhat verify --network polygonMumbai 0x25E4144008b2572C35e244677B9f198D54617268 0xee8405FBBa52312cE8783a09A646992D2E209C8a 0x0EB69bc02addF4ce20Da4E3720886EFc24057EDc
                FEE_GLP_TRACKER: '0x9A0dd83B3589F575C8879597512D72e794A96E52',
                // yarn hardhat verify --network polygonMumbai 0x9A0dd83B3589F575C8879597512D72e794A96E52 "Fee GLP" fGLP
                FEE_GLP_DISTRIBUTOR: '0x6600d926f38F968016C53BBF67E78Dd7B406AeB4',
                // yarn hardhat verify --network polygonMumbai 0x6600d926f38F968016C53BBF67E78Dd7B406AeB4 0xee8405FBBa52312cE8783a09A646992D2E209C8a 0x9A0dd83B3589F575C8879597512D72e794A96E52
                STAKED_GLP_TRACKER: '0x3A87A4F74B00b2aE4364021D3CB71347d63754d2',
                // yarn hardhat verify --network polygonMumbai 0x3A87A4F74B00b2aE4364021D3CB71347d63754d2 "Fee + Staked GLP" fsGLP
                STAKED_GLP_DISTRIBUTOR: '0x4Dc86BC72d84E4E9A91d1868A007215290e94C80',
                // yarn hardhat verify --network polygonMumbai 0x4Dc86BC72d84E4E9A91d1868A007215290e94C80 0x29dC9D44063ac86E2C6a3B407FD1d46626a3CFEe 0x3A87A4F74B00b2aE4364021D3CB71347d63754d2
                STAKED_GLP: '0x9f9d9e1f64618695142664280b6241442432e45b',
                // yarn hardhat verify --network polygonMumbai 0x9f9d9e1f64618695142664280b6241442432e45b 0x08Ea28a92c205A21D7CdF48000C5aAB466b080DA 0x1BCD9aC0BF12162183971Ff166A46c730ac3F2c2 0x3A87A4F74B00b2aE4364021D3CB71347d63754d2 0x9A0dd83B3589F575C8879597512D72e794A96E52
                GMX_ESGMX_VESTER: '0x081c6D8285Ec858088995C95bc2cF7dFe0b460e5',
                // yarn hardhat verify --network polygonMumbai 0x081c6D8285Ec858088995C95bc2cF7dFe0b460e5 "Vested GMX" vGMX 31536000 0x29dC9D44063ac86E2C6a3B407FD1d46626a3CFEe 0x0EB69bc02addF4ce20Da4E3720886EFc24057EDc 0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948 0x8C6C3899955E0A0ceB02Ba811B679822aa496157
                GLP_ESGMX_VESTER: '0x0dF45743856c19964714965654bbc93f46b4E305',
                // yarn hardhat verify --network polygonMumbai 0x0dF45743856c19964714965654bbc93f46b4E305 "Vested GLP" vGLP 31536000 0x29dC9D44063ac86E2C6a3B407FD1d46626a3CFEe 0x3A87A4F74B00b2aE4364021D3CB71347d63754d2 0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948 0x3A87A4F74B00b2aE4364021D3CB71347d63754d2
                GMX_REWARD_ROUTER: '0x0258d2d4D7bA794122539785722c1a65399cfA29',
                // yarn hardhat verify --network polygonMumbai 0x0258d2d4D7bA794122539785722c1a65399cfA29
                GLP_REWARD_ROUTER: '0x0909C4C94F0120DCa998639c9a5F8A068185EEA8',
                // yarn hardhat verify --network polygonMumbai 0x0909C4C94F0120DCa998639c9a5F8A068185EEA8
            },
        },

        TESTNET_MINTER: '0xD2509497D21E2F40B2612F9f2386A44E191770c1',
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
