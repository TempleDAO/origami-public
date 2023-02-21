import { ApiConfig } from '@/api/ethers';
import { Chain } from '@/api/types';

export function getApiConfig(): ApiConfig {
  throw new Error('Mainnet config not yet implemented');
}

const _ARBITRUM: Chain = {
  name: 'Arbitrum One',
  id: 42161,
  rpcUrl: 'https://arb1.arbitrum.io/rpc',
  walletRpcUrl: 'https://arb1.arbitrum.io/rpc',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  subgraphUrl: 'https://TODO',
  explorer: {
    transactionUrl: (hash) => `https://arbiscan.io/tx/${hash}`,
    tokenUrl: (hash) => `https://arbiscan.io/token/${hash}`,
  },
};

const _AVALANCHE: Chain = {
  name: 'Avalanche C-Chain',
  id: 43114,
  rpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  walletRpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  subgraphUrl: 'https://TODO',
  explorer: {
    transactionUrl: (hash) => `https://snowtrace.io/tx/${hash}`,
    tokenUrl: (hash) => `https://snowtrace.io/token${hash}`,
  },
};
