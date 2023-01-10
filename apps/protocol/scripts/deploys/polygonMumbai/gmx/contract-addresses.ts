import { network } from "hardhat";

export interface GmxDeployedContracts {
    ORIGAMI: {
        MULTISIG: string,

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
};

const GMX_DEPLOYED_CONTRACTS: {[key: string]: GmxDeployedContracts} = {
    polygonMumbai: {
        ORIGAMI: {
            // A hot wallet, Mumbai isn't in Gnosis - ask @frontier for the PK if required.
            MULTISIG: '0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165',

            TOKEN_PRICES: '0x303125Ce3D60C9B6C4CA3d6f034aD4CeedE708b3',
            // yarn hardhat verify --network polygonMumbai 0x303125Ce3D60C9B6C4CA3d6f034aD4CeedE708b3 30

            GMX: {
                oGMX: '0xBCd6BA024a179Dfd441CF2418c687e80F1AeAf0D',
                // yarn hardhat verify --network polygonMumbai 0xBCd6BA024a179Dfd441CF2418c687e80F1AeAf0D 0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37
                oGLP: '0x6e78520fd07591B459AA3a4F8B4474215C7C8aF7',
                // yarn hardhat verify --network polygonMumbai 0x6e78520fd07591B459AA3a4F8B4474215C7C8aF7 0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02 0x851dCde48989F1C6dc56e1272117A317a80dFE67

                ovGMX: '0x02aE0A50234Df57E094684B02B35c4CF1b88cC63',
                // yarn hardhat verify --network polygonMumbai 0x02aE0A50234Df57E094684B02B35c4CF1b88cC63 "Origami Shares GMX" osGMX 0xBCd6BA024a179Dfd441CF2418c687e80F1AeAf0D 0x303125Ce3D60C9B6C4CA3d6f034aD4CeedE708b3
                ovGLP: '0x22662bBa4e2b7b1E674F37D8013Fe245d278abce',
                // yarn hardhat verify --network polygonMumbai 0x22662bBa4e2b7b1E674F37D8013Fe245d278abce "Origami Shares GLP" osGLP 0x6e78520fd07591B459AA3a4F8B4474215C7C8aF7 0x303125Ce3D60C9B6C4CA3d6f034aD4CeedE708b3

                GMX_EARN_ACCOUNT: '0x37B5FD67305D237F625C08882774811F8fb9C0b7',
                // yarn hardhat verify --network polygonMumbai 0x37B5FD67305D237F625C08882774811F8fb9C0b7 0xa54F25AaABba037eDF927ae7AB395489e6e69f64 0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE 0x9AAE357dCd1f7138c5b6e89dc41F126508675F67 0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02
                GLP_PRIMARY_EARN_ACCOUNT: '0x1649CA3c0745871287F01bDeB01914a77d53a333',
                // yarn hardhat verify --network polygonMumbai 0x1649CA3c0745871287F01bDeB01914a77d53a333 0xa54F25AaABba037eDF927ae7AB395489e6e69f64 0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE 0xf9c3F14fba54d17e811Fb5Ce886483530A17ef4F 0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02
                GLP_SECONDARY_EARN_ACCOUNT: '0x48E26df359ef75b31dC6A3C1dE0808F6ecEED9c2',
                // yarn hardhat verify --network polygonMumbai 0x48E26df359ef75b31dC6A3C1dE0808F6ecEED9c2 0xa54F25AaABba037eDF927ae7AB395489e6e69f64 0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE 0xf9c3F14fba54d17e811Fb5Ce886483530A17ef4F 0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02

                GMX_MANAGER: '0xDEFA7E0ECcF9b1d45B7534EEe55b434450E5A961',
                // yarn hardhat verify --network polygonMumbai 0xDEFA7E0ECcF9b1d45B7534EEe55b434450E5A961 0xa54F25AaABba037eDF927ae7AB395489e6e69f64 0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE 0xBCd6BA024a179Dfd441CF2418c687e80F1AeAf0D 0x6e78520fd07591B459AA3a4F8B4474215C7C8aF7 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x37B5FD67305D237F625C08882774811F8fb9C0b7 0x0000000000000000000000000000000000000000
                GLP_MANAGER: '0x9C87DE70c6f4ca17f850969821Fc4405FE3FCb20',
                // yarn hardhat verify --network polygonMumbai 0x9C87DE70c6f4ca17f850969821Fc4405FE3FCb20 0xa54F25AaABba037eDF927ae7AB395489e6e69f64 0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE 0xBCd6BA024a179Dfd441CF2418c687e80F1AeAf0D 0x6e78520fd07591B459AA3a4F8B4474215C7C8aF7 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x1649CA3c0745871287F01bDeB01914a77d53a333 0x48E26df359ef75b31dC6A3C1dE0808F6ecEED9c2

                GMX_REWARDS_AGGREGATOR: '0xFF58Ea612bDD991E8aE4C46B4D97A764D8a7Ca50',
                // yarn hardhat verify --network polygonMumbai 0xFF58Ea612bDD991E8aE4C46B4D97A764D8a7Ca50 0xDEFA7E0ECcF9b1d45B7534EEe55b434450E5A961 0x9C87DE70c6f4ca17f850969821Fc4405FE3FCb20 [object Object],[object Object]
                GLP_REWARDS_AGGREGATOR: '0x135cfcfc2e7836B80233F1aaeAF008b71C8f01f1',
                // yarn hardhat verify --network polygonMumbai 0x135cfcfc2e7836B80233F1aaeAF008b71C8f01f1 0x0000000000000000000000000000000000000000 0x9C87DE70c6f4ca17f850969821Fc4405FE3FCb20 [object Object],[object Object]
            },
        },

        PRICES: {
            NATIVE_USD_ORACLE: '0xe54A03d2D1c319634dffa84Ae27dc9a151d6e2a5',
            // yarn hardhat verify --network polygonMumbai 0xe54A03d2D1c319634dffa84Ae27dc9a151d6e2a5 200000000000 8

            DAI_USD_ORACLE: '0x4f895ed8F0c55391d60B59fdEDE73d5e2Ab45Bc5',
            // yarn hardhat verify --network polygonMumbai 0x4f895ed8F0c55391d60B59fdEDE73d5e2Ab45Bc5 100000000 8

            BNB_USD_ORACLE: '0xD0B18d36AD185b4BAE6e8A5FF6fAF08D5B0Ad4bb',
            // yarn hardhat verify --network polygonMumbai 0xD0B18d36AD185b4BAE6e8A5FF6fAF08D5B0Ad4bb 30000000000 8

            BTC_USD_ORACLE: '0xdb1fC73362425eC417333De9D7fF9576ee011E72',
            // yarn hardhat verify --network polygonMumbai 0xdb1fC73362425eC417333De9D7fF9576ee011E72 6000000000000 8

            NATIVE_GMX_POOL: '0x314cff0dDA91Fb73c773fC0b8A2CA10811da2f72',
            // yarn hardhat verify --network polygonMumbai 0x314cff0dDA91Fb73c773fC0b8A2CA10811da2f72 46356982031850672597547879488562 0x851dCde48989F1C6dc56e1272117A317a80dFE67 0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37
        },

        GMX: {
            LIQUIDITY_POOL: {
                WETH_TOKEN: '0x851dCde48989F1C6dc56e1272117A317a80dFE67',
                // yarn hardhat verify --network polygonMumbai  --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x851dCde48989F1C6dc56e1272117A317a80dFE67 WETH WETH
                WETH_PRICE_FEED: '0xa9323afe65Aadc60fb82cfd2b02C183F81Dbda2d',
                // yarn hardhat verify --network polygonMumbai 0xa9323afe65Aadc60fb82cfd2b02C183F81Dbda2d
                BNB_TOKEN: '0x6b047bd68cA46bdCFa75e68DbD9Aca74c4d32C56',
                // yarn hardhat verify --network polygonMumbai  --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x6b047bd68cA46bdCFa75e68DbD9Aca74c4d32C56 BNB BNB
                BNB_PRICE_FEED: '0x62597e116010B50c9D563E92f889509aaD95B15E',
                // yarn hardhat verify --network polygonMumbai 0x62597e116010B50c9D563E92f889509aaD95B15E
                BTC_TOKEN: '0x0D345CF1b62901A4c5BBE65810f1dB2513a2284A',
                // yarn hardhat verify --network polygonMumbai  --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x0D345CF1b62901A4c5BBE65810f1dB2513a2284A Bitcoin BTC
                BTC_PRICE_FEED: '0x0737F4F6Ed3C3836642c048AE9B305cFB8a60945',
                // yarn hardhat verify --network polygonMumbai 0x0737F4F6Ed3C3836642c048AE9B305cFB8a60945
                DAI_TOKEN: '0x4451564f1e9E8487203769B0581173ef776B9116',
                // yarn hardhat verify --network polygonMumbai  --contract contracts/test/external/gmx/tokens/GMX_NamedToken.sol:GMX_NamedToken 0x4451564f1e9E8487203769B0581173ef776B9116 Dai DAI
                DAI_PRICE_FEED: '0x5e3A48d14fD465A42be720a674dd50cB0739A0e1',
                // yarn hardhat verify --network polygonMumbai 0x5e3A48d14fD465A42be720a674dd50cB0739A0e1
            },
            TOKENS: {
                GLP_TOKEN: '0x0F4521268069749a2342f5A51Af386BD91b7B646',
                // yarn hardhat verify --network polygonMumbai 0x0F4521268069749a2342f5A51Af386BD91b7B646
                GMX_TOKEN: '0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37',
                // yarn hardhat verify --network polygonMumbai 0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37
                ESGMX_TOKEN: '0x7Ad74beA1aF93A9050FF6f3c49282a560F01Db81',
                // yarn hardhat verify --network polygonMumbai 0x7Ad74beA1aF93A9050FF6f3c49282a560F01Db81
                BNGMX_TOKEN: '0x28784B0b2A04Aa4F7930E748EECd330A9f526F1d',
                // yarn hardhat verify --network polygonMumbai 0x28784B0b2A04Aa4F7930E748EECd330A9f526F1d "Bonus GMX" bnGMX 0
            },
            CORE: {
                TIMELOCK: '0x3e00C7DdbaeA482aE5f4A9F3aD8c3c2656718a76',
                // yarn hardhat verify --network polygonMumbai 0x3e00C7DdbaeA482aE5f4A9F3aD8c3c2656718a76 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 10 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165 0x97b0D2627567DA6908F8550b9AF983bb916a0997 0xa54F25AaABba037eDF927ae7AB395489e6e69f64 100000000000000000000000000 10 100
                VAULT: '0xcDB7b3D55F836BFBACb8C839B935F40183893C30',
                // yarn hardhat verify --network polygonMumbai 0xcDB7b3D55F836BFBACb8C839B935F40183893C30
                VAULT_PRICE_FEED: '0xDd79805c09AE08079C5cF20C1e058f4ABcc81CAC',
                // yarn hardhat verify --network polygonMumbai 0xDd79805c09AE08079C5cF20C1e058f4ABcc81CAC
                VAULT_UTILS: '0x06c76F4D3F0f90822ad73C9a8034b671F169718d',
                // yarn hardhat verify --network polygonMumbai 0x06c76F4D3F0f90822ad73C9a8034b671F169718d 0xcDB7b3D55F836BFBACb8C839B935F40183893C30
                VAULT_ERROR_CONTROLLER: '0x7f83EC94119dba4D838f3b3bD0c98926C9F1a4eD',
                // yarn hardhat verify --network polygonMumbai 0x7f83EC94119dba4D838f3b3bD0c98926C9F1a4eD
                USDG_TOKEN: '0xeF9Bdaac3e36897f61936e3dFaFB6eb7316059dE',
                // yarn hardhat verify --network polygonMumbai 0xeF9Bdaac3e36897f61936e3dFaFB6eb7316059dE 0xcDB7b3D55F836BFBACb8C839B935F40183893C30
                ROUTER: '0x77246460530A3b717F3F58ea4f7D96d505afB79e', 
                // yarn hardhat verify --network polygonMumbai 0x77246460530A3b717F3F58ea4f7D96d505afB79e 0xcDB7b3D55F836BFBACb8C839B935F40183893C30 0xeF9Bdaac3e36897f61936e3dFaFB6eb7316059dE 0x6b047bd68cA46bdCFa75e68DbD9Aca74c4d32C56
                GLP_MANAGER: '0x97b0D2627567DA6908F8550b9AF983bb916a0997',
                // yarn hardhat verify --network polygonMumbai 0x97b0D2627567DA6908F8550b9AF983bb916a0997 0xcDB7b3D55F836BFBACb8C839B935F40183893C30 0xeF9Bdaac3e36897f61936e3dFaFB6eb7316059dE 0x0F4521268069749a2342f5A51Af386BD91b7B646 0x0000000000000000000000000000000000000000 900
            },
            STAKING: {
                STAKED_GMX_TRACKER: '0x9636612F7504CfCa091772d4D4b0B35A5099c41f',
                // yarn hardhat verify --network polygonMumbai 0x9636612F7504CfCa091772d4D4b0B35A5099c41f "Staked GMX" sGMX
                STAKED_GMX_DISTRIBUTOR: '0x385f61468fc93B9f1E40260Ee4c4DCadf06D7fdA',
                // yarn hardhat verify --network polygonMumbai 0x385f61468fc93B9f1E40260Ee4c4DCadf06D7fdA 0x7Ad74beA1aF93A9050FF6f3c49282a560F01Db81 0x9636612F7504CfCa091772d4D4b0B35A5099c41f
                BONUS_GMX_TRACKER: '0x0661c175819BEcC7F281aba19262D488c6203613',
                // yarn hardhat verify --network polygonMumbai 0x0661c175819BEcC7F281aba19262D488c6203613 "Staked + Bonus GMX" sbGMX
                BONUS_GMX_DISTRIBUTOR: '0x1afEdf0a4FF469b0fE3AcE9Cb3fe04Fde34C6cfC',
                // yarn hardhat verify --network polygonMumbai 0x1afEdf0a4FF469b0fE3AcE9Cb3fe04Fde34C6cfC 0x28784B0b2A04Aa4F7930E748EECd330A9f526F1d 0x0661c175819BEcC7F281aba19262D488c6203613
                FEE_GMX_TRACKER: '0xA7E2Cd230CE988743e02122868155988F61E96c4',
                // yarn hardhat verify --network polygonMumbai 0xA7E2Cd230CE988743e02122868155988F61E96c4 "Staked + Bonus + Fee GMX" sbfGMX
                FEE_GMX_DISTRIBUTOR: '0x191479bCE734A6416cCF427070D3166849D20f4D',
                // yarn hardhat verify --network polygonMumbai 0x191479bCE734A6416cCF427070D3166849D20f4D 0x851dCde48989F1C6dc56e1272117A317a80dFE67 0xA7E2Cd230CE988743e02122868155988F61E96c4
                FEE_GLP_TRACKER: '0x24390bDbD4748c7A0a6865Ee7b599827c2122B2C',
                // yarn hardhat verify --network polygonMumbai 0x24390bDbD4748c7A0a6865Ee7b599827c2122B2C "Fee GLP" fGLP
                FEE_GLP_DISTRIBUTOR: '0xCC934Bd0DF71c6Ea290327522c51297d56043A90',
                // yarn hardhat verify --network polygonMumbai 0xCC934Bd0DF71c6Ea290327522c51297d56043A90 0x851dCde48989F1C6dc56e1272117A317a80dFE67 0x24390bDbD4748c7A0a6865Ee7b599827c2122B2C
                STAKED_GLP_TRACKER: '0x1d1520186D4AC21007afa68688c3c4aA9BA304Fa',
                // yarn hardhat verify --network polygonMumbai 0x1d1520186D4AC21007afa68688c3c4aA9BA304Fa "Fee + Staked GLP" fsGLP
                STAKED_GLP_DISTRIBUTOR: '0xB3e5940be4232Ef3fBf04880953346C88836cE0C',
                // yarn hardhat verify --network polygonMumbai 0xB3e5940be4232Ef3fBf04880953346C88836cE0C 0x7Ad74beA1aF93A9050FF6f3c49282a560F01Db81 0x1d1520186D4AC21007afa68688c3c4aA9BA304Fa
                STAKED_GLP: '0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02',
                // yarn hardhat verify --network polygonMumbai 0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02 0x0F4521268069749a2342f5A51Af386BD91b7B646 0x97b0D2627567DA6908F8550b9AF983bb916a0997 0x1d1520186D4AC21007afa68688c3c4aA9BA304Fa 0x24390bDbD4748c7A0a6865Ee7b599827c2122B2C
                GMX_ESGMX_VESTER: '0x9AAE357dCd1f7138c5b6e89dc41F126508675F67',
                // yarn hardhat verify --network polygonMumbai 0x9AAE357dCd1f7138c5b6e89dc41F126508675F67 "Vested GMX" vGMX 31536000 0x7Ad74beA1aF93A9050FF6f3c49282a560F01Db81 0xA7E2Cd230CE988743e02122868155988F61E96c4 0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37 0x9636612F7504CfCa091772d4D4b0B35A5099c41f
                GLP_ESGMX_VESTER: '0xf9c3F14fba54d17e811Fb5Ce886483530A17ef4F',
                // yarn hardhat verify --network polygonMumbai 0xf9c3F14fba54d17e811Fb5Ce886483530A17ef4F "Vested GLP" vGLP 31536000 0x7Ad74beA1aF93A9050FF6f3c49282a560F01Db81 0x1d1520186D4AC21007afa68688c3c4aA9BA304Fa 0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37 0x1d1520186D4AC21007afa68688c3c4aA9BA304Fa
                GMX_REWARD_ROUTER: '0xa54F25AaABba037eDF927ae7AB395489e6e69f64',
                // yarn hardhat verify --network polygonMumbai 0xa54F25AaABba037eDF927ae7AB395489e6e69f64
                GLP_REWARD_ROUTER: '0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE',
                // yarn hardhat verify --network polygonMumbai 0xB340cBb0e932F58C16c86F0e1DDBB629dF436ccE
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
