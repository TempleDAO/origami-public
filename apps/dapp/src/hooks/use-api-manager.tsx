import { ProviderApi, SignerApi } from '@/api/api';
import { ChainConfig, ChainId } from '@/api/types';
import { createProviderApi, createSignerApi, ApiConfig } from '@/api/ethers';

import { ethers, Signer } from 'ethers';
import React, { useMemo, useState } from 'react';

interface ApiManager {
  papi: ProviderApi;
  sapi: SignerApi | undefined;
  wallet: WalletConnection | undefined;

  disconnectSigner(): Promise<void>;
  connectSigner(chainId?: ChainId): Promise<void>;
}

export interface WalletConnection {
  signer: Signer;
  signerApi: SignerApi;
  chainId: ChainId;
  address: string;
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
  const [wallet, setWallet] = useState<WalletConnection | undefined>();

  async function disconnectSigner() {
    setWallet(undefined);
  }

  async function connectSigner(mChainId?: ChainId) {
    if (typeof window !== undefined) {
      const newmm = await createConnection(papi, mChainId, props.apiConfig);
      setWallet((oldmm) =>
        !oldmm || oldmm.chainId !== newmm.chainId ? newmm : oldmm
      );
    }
  }

  const apiManager: ApiManager = {
    papi,
    sapi: wallet && wallet.signerApi,
    wallet: wallet,
    disconnectSigner,
    connectSigner,
  };
  return (
    <ApiManagerContext.Provider value={apiManager}>
      {props.children}
    </ApiManagerContext.Provider>
  );
}

export function useApiManager(): ApiManager {
  const chainSigner = React.useContext(ApiManagerContext);
  if (!chainSigner) {
    throw new Error('useChainSigner invalid outside an ChainSignerProvider');
  }
  return chainSigner;
}

/**
 * Create a new connection to the wallet, switching to and setting up the specified chain if required.
 */
async function createConnection(
  papi: ProviderApi,
  mChainId: ChainId | undefined,
  apiConfig: ApiConfig
): Promise<WalletConnection> {
  const ethereum = (window as unknown as { ethereum: LocalProvider }).ethereum;
  const provider = new ethers.providers.Web3Provider(ethereum, 'any');
  const signer = provider.getSigner();
  let chainId = await signer.getChainId();
  await provider.send('eth_requestAccounts', []);

  if (mChainId && mChainId !== chainId) {
    const toChain = papi.chains.get(mChainId);
    if (!toChain) {
      throw new Error('No config for chainid ' + mChainId);
    }
    await switchToChain(ethereum, toChain);
    chainId = toChain.id;
  }
  const address = await signer.getAddress();
  const signerApi = createSignerApi(apiConfig, address, chainId, signer);
  return { signer, signerApi, chainId, address };
}

async function switchToChain(ethereum: LocalProvider, toChain: ChainConfig) {
  console.log(`switching to ${toChain.name} (id ${toChain.id})`);
  const chainIdStr = '0x' + toChain.id.toString(16);
  try {
    await ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: chainIdStr }],
    });
  } catch (switchError: unknown) {
    if ((switchError as { code: number }).code === 4902) {
      await ethereum.request({
        method: 'wallet_addEthereumChain',
        params: [
          {
            chainId: chainIdStr,
            chainName: toChain.name,
            rpcUrls: [toChain.walletRpcUrl],
            nativeCurrency: toChain.nativeCurrency,
          },
        ],
      });
    } else {
      throw switchError;
    }
  }
}

export type LocalProvider = {
  request: (request: {
    method: string;
    params?: Array<unknown>;
  }) => Promise<unknown>;
};
