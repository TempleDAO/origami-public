import { ProviderApi, SignerApi } from '@/api/api';
import { Chain } from '@/api/types';
import { createProviderApi, createSignerApi, ApiConfig } from '@/api/ethers';

import React, { useEffect, useMemo, useState } from 'react';
import { ApiCache, useCache } from '@/api/cache';
import { AppWallet, WalletState } from '@/wallets/types';
import { createMetaMaskWallet } from '@/wallets/metamask';
import { createWalletConnectWallet } from '@/wallets/walletconnect';
import { assertNever } from '@/utils/assert';
import { TERMS_OF_SERVICE_URL } from '@/urls';

interface ApiManager {
  papi: ProviderApi;
  sapi: SignerApi | undefined;
  wallet: WalletState | undefined;
  cache: ApiCache;

  walletInitialize(walletKind: SupportedWallet): Promise<void>;
  walletConnect(chain: Chain): Promise<SignerApi | undefined>;
  walletDisconnect(): Promise<void>;
}

export const ApiManagerContext =
  React.createContext<ApiManager | undefined>(undefined);

export function ApiManagerProvider(props: {
  apiConfig: ApiConfig;
  children?: React.ReactNode;
}) {
  const papi = useMemo(
    () => createProviderApi(props.apiConfig),
    [props.apiConfig]
  );
  const [appWallet, setAppWallet] = useState<AppWallet | undefined>();
  const [walletState, setWalletState] = useState<WalletState | undefined>();
  const [sapi, setSApi] = useState<SignerApi | undefined>();

  async function walletInitialize(walletKind: SupportedWallet) {
    const appWallet = await createAppWallet(walletKind, props.apiConfig.chains);
    setAppWallet(appWallet);
    setWalletState(appWallet.getState());
    localStorage.setItem(LOCALSTORE_WALLET_STATE, walletKind);
  }

  async function walletConnect(chain: Chain): Promise<SignerApi | undefined> {
    if (!appWallet) {
      throw new Error('no wallet initialized');
    }
    await appWallet.connect(chain);
    const walletState = appWallet.getState();
    const connection = walletState.connection;
    if (!connection) {
      throw new Error('Failed to connect');
    }

    const termsKey = `origami.tos.${walletState.address}`;
    if (localStorage.getItem(termsKey) === null) {
      const termsMessage = `I agree to the Origami Terms of Service at:\n\n${TERMS_OF_SERVICE_URL}`;
      try {
        const signedMessage = await connection.signer.signMessage(termsMessage);
        localStorage.setItem(termsKey, signedMessage);
      } catch (e) {
        console.error('failed to sign terms of Service', e);
        return;
      }
    }

    setWalletState(walletState);
    const sapi = createSignerApi(
      props.apiConfig,
      walletState.address,
      connection.chainId,
      connection.signer
    );

    setSApi(sapi);
    return sapi;
  }

  async function walletDisconnect() {
    if (appWallet) {
      await appWallet.disconnect();
      setAppWallet(undefined);
      setWalletState(undefined);
      setSApi(undefined);
    }
    localStorage.removeItem(LOCALSTORE_WALLET_STATE);
  }

  useEffect(() => {
    const walletKind = localStorage.getItem(LOCALSTORE_WALLET_STATE);
    if (walletKind != null) {
      walletInitialize(walletKind as SupportedWallet);
    }
  }, []); // eslint-disable-line

  const cache = useCache(papi, walletState?.address);

  const apiManager: ApiManager = {
    papi,
    sapi,
    wallet: walletState,
    cache,
    walletInitialize,
    walletConnect,
    walletDisconnect,
  };
  return (
    <ApiManagerContext.Provider value={apiManager}>
      {props.children}
    </ApiManagerContext.Provider>
  );
}

export type SupportedWallet = 'metaMask' | 'walletConnect';

export async function createAppWallet(
  walletKind: SupportedWallet,
  chains: Chain[]
): Promise<AppWallet> {
  if (walletKind === 'metaMask') {
    return createMetaMaskWallet();
  } else if (walletKind == 'walletConnect') {
    return createWalletConnectWallet(chains);
  }
  return assertNever(walletKind);
}

export function useApiManager(): ApiManager {
  const chainSigner = React.useContext(ApiManagerContext);
  if (!chainSigner) {
    throw new Error('useChainSigner invalid outside an ChainSignerProvider');
  }
  return chainSigner;
}

const LOCALSTORE_WALLET_STATE = 'walletState';
