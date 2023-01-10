import { ApiConfig } from '@/api/ethers';
import { ChainConfig } from '@/api/types';

export function getApiConfig(): ApiConfig {
  throw new Error('Mainnet config not yet implemented');
}

const _ARBITRUM: ChainConfig = {
  name: 'Arbitrum One',
  id: 42161,
  rpcUrl: 'https://arb1.arbitrum.io/rpc',
  metamaskRpcUrl: 'https://arb1.arbitrum.io/rpc',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  subgraphUrl: 'https://TODO',
};

const _AVALANCHE: ChainConfig = {
  name: 'Avalanche C-Chain',
  id: 43114,
  rpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  metamaskRpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  subgraphUrl: 'https://TODO',
};
