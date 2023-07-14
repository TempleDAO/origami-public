import React, { useEffect, useMemo, useState } from 'react';
import { useConnectWallet, useSetChain } from '@web3-onboard/react';
import { WalletState } from '@web3-onboard/core';

import { ProviderApi, SignerApi } from '@/api/api';
import { createProviderApi, createSignerApi, ApiConfig } from '@/api/ethers';

import { ApiCache, useCache } from '@/api/cache';
import { TERMS_OF_SERVICE_URL } from '@/urls';

import { ethers } from 'ethers';
import { ChainId } from '@/api/types';

interface ApiManager {
  papi: ProviderApi;
  sapi: SignerApi | undefined;

  cache: ApiCache;

  walletConnect(): Promise<void>;
  walletSetChain(chainId: number): Promise<void>;
  walletDisconnect(): Promise<void>;
}

export const ApiManagerContext =
  React.createContext<ApiManager | undefined>(undefined);

export function ApiManagerProvider(props: {
  apiConfig: ApiConfig;
  children?: React.ReactNode;
}) {
  const [{ wallet }, connect, disconnect] = useConnectWallet();
  const [{ connectedChain }, setChain] = useSetChain();

  const papi = useMemo(
    () => createProviderApi(props.apiConfig),
    [props.apiConfig]
  );
  const [sapi, setSApi] = useState<SignerApi | undefined>();
  const cache = useCache(papi, sapi?.signerAddress);

  useEffect(() => {
    async function setupFromWallet(wallet: WalletState | null) {
      if (wallet?.provider && connectedChain) {
        const ethersProvider = new ethers.providers.Web3Provider(
          wallet.provider,
          'any'
        );
        const signer = ethersProvider.getSigner();
        const chainId = (await ethersProvider.getNetwork()).chainId;
        const address = await ethersProvider.getSigner().getAddress();

        const termsKey = `origami.tos.${address}`;
        if (localStorage.getItem(termsKey) === null) {
          const termsMessage = `I agree to the Origami Terms of Service at:\n\n${TERMS_OF_SERVICE_URL}`;
          try {
            const signedMessage = await signer.signMessage(termsMessage);
            localStorage.setItem(termsKey, signedMessage);
          } catch (e) {
            console.error('failed to sign terms of Service', e);
            return;
          }
        }

        const sapi = createSignerApi(props.apiConfig, address, chainId, signer);
        setSApi(sapi);
      } else {
        setSApi(undefined);
      }
    }

    setupFromWallet(wallet);
  }, [wallet, connectedChain, props.apiConfig]);

  async function walletConnect() {
    await connect();
  }

  async function walletSetChain(chainId: number) {
    setChain({ chainId: '0x' + chainId.toString(16) });
  }

  async function walletDisconnect() {
    if (wallet) {
      await disconnect({ label: wallet.label });
    }
  }

  const apiManager: ApiManager = {
    papi,
    sapi,
    cache,
    walletConnect,
    walletSetChain,
    walletDisconnect,
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

export type AsyncWithSigner = (
  papi: ProviderApi,
  sapi: SignerApi
) => Promise<void>;
export type RequestActionFn = (
  chainId: ChainId,
  action: AsyncWithSigner
) => void;

// Hook to schedule running an action once a wallet has been connected and the
// appropriate wallet chain configured
export function useActionWithSigner(): RequestActionFn {
  const [reqAction, setReqAction] =
    useState<{ run: AsyncWithSigner } | undefined>();
  const [reqChain, setReqChain] = useState<ChainId>(1);

  const { papi, sapi, walletConnect, walletSetChain } = useApiManager();

  useEffect(() => {
    async function runActionWhenReady(): Promise<void> {
      const currentChain = sapi?.chainId;
      if (reqAction) {
        console.log('action requested');
        if (!sapi) {
          console.log('Connecting wallet');
          try {
            await walletConnect();
          } catch (e: unknown) {
            setReqAction(undefined);
          }
        } else {
          if (currentChain !== reqChain) {
            console.log('Selecting chain');

            try {
              await walletSetChain(reqChain);
            } catch (e: unknown) {
              setReqAction(undefined);
            }
          } else {
            console.log('running action');
            // Everything is good, lets run the action
            const action = reqAction;
            setReqAction(undefined);
            console.log('ACTDIOB', papi, sapi);
            action.run(papi, sapi);
          }
        }
      }
    }

    runActionWhenReady();
  }, [reqAction, reqChain, papi, sapi, walletConnect, walletSetChain]);

  function requestAction(chainId: ChainId, action: AsyncWithSigner) {
    setReqChain(chainId);
    setReqAction({ run: action });
  }

  return requestAction;
}
