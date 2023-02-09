import type { ApiConfig } from '@/api/ethers';
import type { ChainConfig } from '@/api/types';

import { arbitrum, avalanche } from '@wagmi/core/chains';

export function getApiConfig(): ApiConfig {
  throw new Error('Mainnet config not yet implemented');
}

const _ARBITRUM: ChainConfig = {
  chain: arbitrum,
  subgraphUrl: 'https://TODO',
  urlBuilders: {
    transactionUrl: (hash) => `${arbitrum.blockExplorers.etherscan}/tx/${hash}`,
    tokenUrl: (hash) => `${arbitrum.blockExplorers.etherscan}/token/${hash}`,
  },
};

const _AVALANCHE: ChainConfig = {
  chain: avalanche,
  subgraphUrl: 'https://TODO',
  urlBuilders: {
    transactionUrl: (hash) =>
      `${avalanche.blockExplorers.etherscan}/tx/${hash}`,
    tokenUrl: (hash) => `${avalanche.blockExplorers.etherscan}/token/${hash}`,
  },
};
