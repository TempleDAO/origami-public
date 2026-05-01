require('dotenv').config();

import '@nomicfoundation/hardhat-chai-matchers';
import '@typechain/hardhat';
import '@nomicfoundation/hardhat-verify';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-vyper';
import '@openzeppelin/hardhat-upgrades';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import "@nomicfoundation/hardhat-foundry";

function getMaxGasInWei(envVar: string | undefined): number | undefined {
    return envVar
        ? parseInt(envVar) * 1000000000
        : undefined;
}

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    paths: {
        sources: "./contracts",
        artifacts: "./artifacts-hardhat",
        cache: "./cache-hardhat", // Use a different cache for Hardhat than Foundry
    },
    solidity: {
        compilers: [
            {
                version: '0.8.28',
                settings: {
                    optimizer: {
                        enabled: true,
                        // Note OrigamiLovTokenFlashAndBorrowManagerMarketAL requires this to be lowered
                        // down to 7_650 runs to fit under 24kb
                        runs: 9_999,
                    },
                    evmVersion: "cancun",
                },
            },
        ],
    },
    typechain: {
        target: 'ethers-v5',
        outDir: './typechain',
    },
    networks: {
        localhost: {
            timeout: 100_000
          },
        polygonMumbai: {
            url: process.env.MUMBAI_RPC_URL || '',
            accounts: process.env.MUMBAI_ADDRESS_PRIVATE_KEY
                ? [process.env.MUMBAI_ADDRESS_PRIVATE_KEY]
                : [],
            gasPrice: 2000000000,
        },
        arbitrum: {
            url: process.env.ARBITRUM_RPC_URL || '',
            accounts: process.env.ARBITRUM_ADDRESS_PRIVATE_KEY
                ? [process.env.ARBITRUM_ADDRESS_PRIVATE_KEY]
                : [],
        },
        avalanche: {
            url: process.env.AVALANCHE_RPC_URL || '',
            accounts: process.env.AVALANCHE_ADDRESS_PRIVATE_KEY
                ? [process.env.AVALANCHE_ADDRESS_PRIVATE_KEY]
                : [],
            gasPrice: getMaxGasInWei(process.env.AVALANCHE_GAS_IN_GWEI),
        },
        polygon: {
            url: process.env.POLYGON_RPC_URL || '',
            accounts: process.env.POLYGON_ADDRESS_PRIVATE_KEY
                ? [process.env.POLYGON_ADDRESS_PRIVATE_KEY]
                : [],
            gasPrice: getMaxGasInWei(process.env.AVALANCHE_GAS_IN_GWEI),
        },
        mainnet: {
            url: process.env.MAINNET_RPC_URL || '',
            accounts: process.env.MAINNET_ADDRESS_PRIVATE_KEY
                ? [process.env.MAINNET_ADDRESS_PRIVATE_KEY]
                : [],
        },
        sepolia: {
            url: process.env.SEPOLIA_RPC_URL || '',
            accounts: process.env.SEPOLIA_ADDRESS_PRIVATE_KEY
                ? [process.env.SEPOLIA_ADDRESS_PRIVATE_KEY]
                : [],
            gasPrice: getMaxGasInWei(process.env.AVALANCHE_GAS_IN_GWEI),
        },
        holesky: {
            chainId: 17000,
            url: process.env.HOLESKY_RPC_URL || '',
            accounts: process.env.HOLESKY_ADDRESS_PRIVATE_KEY
                ? [process.env.HOLESKY_ADDRESS_PRIVATE_KEY]
                : [],
            gasPrice: getMaxGasInWei(process.env.AVALANCHE_GAS_IN_GWEI),
        },
        bartio: {
            url: process.env.BARTIO_RPC_URL || '',
            accounts: process.env.BARTIO_ADDRESS_PRIVATE_KEY
                ? [process.env.BARTIO_ADDRESS_PRIVATE_KEY]
                : [],
            chainId: 80084,
        },
        cartio: {
            url: process.env.CARTIO_RPC_URL || '',
            accounts: process.env.CARTIO_ADDRESS_PRIVATE_KEY
                ? [process.env.CARTIO_ADDRESS_PRIVATE_KEY]
                : [],
            chainId: 80000,
        },
        berachain: {
            url: process.env.BERACHAIN_RPC_URL || '',
            accounts: process.env.BERACHAIN_ADDRESS_PRIVATE_KEY
                ? [process.env.BERACHAIN_ADDRESS_PRIVATE_KEY]
                : [],
            chainId: 80094,
        },
        plasma: {
            url: process.env.PLASMA_RPC_URL || '',
            accounts: process.env.PLASMA_ADDRESS_PRIVATE_KEY
                ? [process.env.PLASMA_ADDRESS_PRIVATE_KEY]
                : [],
            chainId: 9745,
        },
        bepolia: {
            url: process.env.BEPOLIA_RPC_URL || '',
            accounts: process.env.BEPOLIA_ADDRESS_PRIVATE_KEY
                ? [process.env.BEPOLIA_ADDRESS_PRIVATE_KEY]
                : [],
            chainId: 80069,
        },
        anvil: {
            url: "http://127.0.0.1:8545/",
            accounts: "remote",
        },
    },
    etherscan: {
        // Your API key for Etherscan
        // Obtain one at https://etherscan.io/
        apiKey: process.env.ETHERSCAN_API_KEY,
        customChains: [
            {
                network: "mainnet",
                chainId: 1,
                urls: {
                    apiURL:
                        "https://api.etherscan.io/v2/api?chainid=1",
                    browserURL: "https://etherscan.io/",
                },
            },
            {
                network: "bartio",
                chainId: 80084,
                urls: {
                    apiURL:
                        "https://api.routescan.io/v2/network/testnet/evm/80084/etherscan/api/",
                    browserURL: "https://bartio.beratrail.io/",
                },
            },
            {
                network: "cartio",
                chainId: 80000,
                urls: {
                    apiURL:
                        "https://api.routescan.io/v2/network/mainnet/evm/80000/etherscan",
                    browserURL: "https://80000.testnet.routescan.io/",
                },
            },
            {
                network: "berachain",
                chainId: 80094,
                urls: {
                    apiURL:
                        "https://api.etherscan.io/v2/api?chainid=80094",
                    browserURL: "https://berascan.com/",
                },
            },
            {
                network: "bepolia",
                chainId: 80069,
                urls: {
                    apiURL:
                        "https://api.routescan.io/v2/network/testnet/evm/80069/etherscan",
                    browserURL: "https://bepolia.beratrail.io/",
                },
            },
            {
                network: "holesky",
                chainId: 17000,
                urls: {
                    apiURL: "https://api-holesky.etherscan.io/api/",
                    browserURL: "https://holesky.etherscan.io/",
                },
            },
            {
                network: "plasma",
                chainId: 9745,
                urls: {
                    apiURL:
                        "https://api.etherscan.io/v2/api?chainid=9745",
                    browserURL: "https://plasmascan.to/",
                },
            },
        ],
    },
    sourcify: {
        // Disabled by default
        // Doesn't need an API key
        enabled: false
    },
    mocha: {
        timeout: 120000,
    },
    contractSizer: {
        alphaSort: true,
    },
    gasReporter: {
        enabled: (process.env.REPORT_GAS) ? true : false,
        outputFile: "./hardhat-gas-report.txt",
        noColors: true,
    }
};