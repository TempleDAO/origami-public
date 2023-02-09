import { WalletConnectConnector } from '@wagmi/core/connectors/walletConnect';
import { MetaMaskConnector } from '@wagmi/core/connectors/metaMask';
import { getApiConfig } from '.';

export type SupportedWallet = 'metaMask' | 'walletConnect';
export type Connector = MetaMaskConnector | WalletConnectConnector;

const WALLET_CONNECT_PROJECT_ID = 'e5772c7a7fe21916e3828485a53fb06d';

const API_CONFIG = getApiConfig();
const chains = API_CONFIG.chainConfigs.map((chainConfig) => chainConfig.chain);

export const CONNECTORS: Record<SupportedWallet, Connector> = {
  metaMask: new MetaMaskConnector({
    chains,
    options: {
      shimDisconnect: true,
    },
  }),
  walletConnect: new WalletConnectConnector({
    chains,
    options: {
      qrcode: true,
      version: '2',
      projectId: WALLET_CONNECT_PROJECT_ID,
    },
  }),
} as const;
