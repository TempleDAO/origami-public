require('dotenv').config();

import '@nomicfoundation/hardhat-chai-matchers';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-vyper';
import '@openzeppelin/hardhat-upgrades';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'solidity-coverage';

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
//

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
        },
      },
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1, // Inline with GMX.io's deploys - required to get the contract size < 32 bytes
          },
        },
      },
    ],
  },
  typechain: {
    target: 'ethers-v5',
    outDir: './typechain',
  },
  networks: {
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
      gasPrice: parseInt(process.env.ARBITRUM_GAS_IN_GWEI || '0') * 1000000000,
    },
    avalanche: {
      url: process.env.AVALANCHE_RPC_URL || '',
      accounts: process.env.AVALANCHE_ADDRESS_PRIVATE_KEY
        ? [process.env.AVALANCHE_ADDRESS_PRIVATE_KEY]
        : [],
      gasPrice: parseInt(process.env.AVALANCHE_GAS_IN_GWEI || '0') * 1000000000,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: {
      polygonMumbai: process.env.POLYGONSCAN_API_KEY,
    },
  },
  mocha: {
    timeout: 120000,
  },
  contractSizer: {
    alphaSort: true,
  }
};