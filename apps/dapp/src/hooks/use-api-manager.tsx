import type { Signer } from 'ethers';
import type { Chain } from '@wagmi/core';
import type { ProviderApi, SignerApi } from '@/api/api';
import type { ChainConfig, ChainId } from '@/api/types';
import type { SupportedWallet } from '@/config/connectors';

import React, { useMemo, useState, useEffect } from 'react';
import {
  connect,
  disconnect,
  fetchSigner,
  getAccount,
  getNetwork,
  switchNetwork as wagmiSwitchNetwork,
} from '@wagmi/core';
import { createProviderApi, createSignerApi, ApiConfig } from '@/api/ethers';
import { ApiCache, useCache } from '@/api/cache';
import { CONNECTORS } from '@/config/connectors';
import { first } from '@/api/utils';
import { VMap } from '@/utils/vmap';

import { configureChains, createClient } from '@wagmi/core';
import { jsonRpcProvider } from '@wagmi/core/providers/jsonRpc';

interface ApiManager {
  papi: ProviderApi;
  sapi: SignerApi | undefined;
  wallet: WalletConnection | undefined;
  cache: ApiCache;

  switchNetwork({ chainId }: { chainId: number }): Promise<Chain>;
  disconnectSigner(): Promise<void>;
  connectSigner(walletKind: SupportedWallet, chainId?: ChainId): Promise<void>;
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
  const _wagmiClient = useMemo(() => {
    const { chains: _wagmiChains, provider } = _configureWagmiChains(
      props.apiConfig.chainConfigs
    );

    return createClient({
      autoConnect: true,
      provider,
      connectors: Object.values(CONNECTORS),
    });
  }, [props.apiConfig.chainConfigs]);

  const papi = useMemo(
    () => createProviderApi(props.apiConfig),
    [props.apiConfig]
  );

  const [wallet, setWallet] = useState<WalletConnection | undefined>();

  /**
   * wagmi manages the connection status to MetaMask via localStorage since
   * MetaMask cannot be disconnected programatically. This means we can preserve our connection
   * across page visits/refreshes for a better UX.
   */
  useEffect(() => {
    async function restoreMetaMaskConnectionOnMount() {
      const { isConnected } = getAccount();

      if (!isConnected) {
        return;
      }

      const metaMask: SupportedWallet = 'metaMask';

      const wagmiWallet = localStorage.getItem('wagmi.wallet');
      const { chain } = getNetwork();

      if (!chain?.id || wagmiWallet !== `"${metaMask}"`) {
        return;
      }

      const wallet = await createConnection(
        chain.id,
        props.apiConfig,
        metaMask
      );

      setWallet(wallet);
    }

    restoreMetaMaskConnectionOnMount();
  }, [props.apiConfig]);

  async function switchNetwork({ chainId }: { chainId: number }) {
    const network = getNetwork();

    if (network?.chain?.id === chainId) {
      return network.chain;
    }

    return wagmiSwitchNetwork({ chainId });
  }

  async function disconnectSigner() {
    await disconnect();
    setWallet(undefined);
  }

  async function connectSigner(
    walletKind: SupportedWallet,
    mChainId?: ChainId
  ) {
    if (typeof window !== undefined) {
      const newWallet = await createConnection(
        mChainId,
        props.apiConfig,
        walletKind
      );
      setWallet((oldWallet) =>
        !oldWallet || oldWallet.chainId !== newWallet.chainId
          ? newWallet
          : oldWallet
      );
    }
  }

  const cache = useCache(papi, wallet?.address);

  const apiManager: ApiManager = {
    papi,
    sapi: wallet && wallet.signerApi,
    wallet: wallet,
    cache,
    disconnectSigner,
    connectSigner,
    switchNetwork,
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
  mChainId: ChainId | undefined,
  apiConfig: ApiConfig,
  walletKind: SupportedWallet
): Promise<WalletConnection> {
  const provider = await connect({
    connector: CONNECTORS[walletKind],
    chainId: mChainId,
  });

  let chainId = provider.chain.id;

  if (provider.chain.unsupported) {
    const fallbackChainConfig = first(apiConfig.chainConfigs);

    if (!fallbackChainConfig) {
      throw Error(
        `Failed to connect: ApiConfig has no chains configured. Unable to setup fallback chain on wallet connection.`
      );
    }

    try {
      const supportedChain = await wagmiSwitchNetwork({
        chainId: fallbackChainConfig.chain.id,
      });
      chainId = supportedChain.id;
    } catch (e) {
      console.error(
        'User refused network change to a supported Origami network'
      );
    }
  }

  const signer = await fetchSigner({ chainId: chainId });

  if (!signer) {
    throw Error('Failed to get `Signer` instance when connecting to wallet');
  }

  const { address } = getAccount();

  if (!address) {
    throw Error('Failed to get account address when connecting to wallet');
  }

  const signerApi = createSignerApi(apiConfig, address, chainId, signer);

  return { signer, signerApi, chainId, address };
}

/**
 * Create a new instance of a wagmi chain configuration object from Origami's chain configurations
 * @param chainConfigs Origami supported chains configuration
 * @returns wagmi chains and provider objects
 */
function _configureWagmiChains(chainConfigs: ChainConfig[]) {
  const supportedChains = chainConfigs.map((config) => config.chain);

  const chainConfigsVmap: VMap<number, ChainConfig> = new VMap((c) =>
    c.toString()
  );

  for (const chainConfig of chainConfigs) {
    chainConfigsVmap.put(chainConfig.chain.id, chainConfig);
  }

  const wagmiChainConfig = configureChains(supportedChains, [
    jsonRpcProvider({
      rpc: (chain) => {
        const chainConfig = chainConfigsVmap.get(chain.id);

        if (!chainConfig) {
          throw new Error(
            `Unsupported chain: Missing ChainConfig for chain id ${chain.id} while instantiating JsonRpcProvider.`
          );
        }

        const rpcUrl =
          chainConfig.origamiRpcUrl ?? chain.rpcUrls.default.http[0];

        return {
          http: rpcUrl,
        };
      },
    }),
  ]);

  return wagmiChainConfig;
}

export type LocalProvider = {
  request: (request: {
    method: string;
    params?: Array<unknown>;
  }) => Promise<unknown>;
};
