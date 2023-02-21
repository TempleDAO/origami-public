import { Chain } from '@/api/types';
import { AppWallet, WalletState } from './types';

import { WalletConnectConnector } from '@wagmi/core/connectors/walletConnect';
import {
  Chain as WagmiChain,
  configureChains,
  createClient,
} from '@wagmi/core';
import { publicProvider } from '@wagmi/core/providers/public';

import { polygonMumbai, avalancheFuji } from '@wagmi/chains';

/** AppWallet implementation for walletconnect, via wagmi*/
export async function createWalletConnectWallet(): Promise<AppWallet> {
  initializeWagmi();

  const connector = new WalletConnectConnector({
    chains: WAGMI_CHAINS,
    options: {
      qrcode: true,
      version: '2',
      projectId: WALLET_CONNECT_PROJECT_ID,
    },
  });

  await connector.connect();
  const address = await connector.getAccount();

  let state: WalletState = {
    address,
    connection: undefined,
  };

  async function connect(toChain: Chain): Promise<void> {
    const wagmiChain = connector.chains.find((chain) => chain.id == toChain.id);
    if (!wagmiChain) {
      throw new Error(
        `walletconnect not configured for  ${toChain.name} (id ${toChain.id})`
      );
    }
    const signer = await connector.getSigner();
    state = {
      ...state,
      connection: {
        chainId: toChain.id,
        signer,
      },
    };
  }

  async function disconnect(): Promise<void> {
    await connector.disconnect();
  }

  function getState(): WalletState {
    return state;
  }

  return { connect, disconnect, getState };
}

let wagmi_initialised = false;

function initializeWagmi() {
  if (!wagmi_initialised) {
    const { provider, webSocketProvider } = configureChains(WAGMI_CHAINS, [
      publicProvider(),
    ]);

    createClient({
      provider,
      webSocketProvider,
    });
    wagmi_initialised = true;
  }
}

// TODO: tie this in with the config directory
const WAGMI_CHAINS: WagmiChain[] = [polygonMumbai, avalancheFuji];

// Created via the wallet connect web console.
const WALLET_CONNECT_PROJECT_ID = '9a4023728c00ee517019dbbc07e92481';
