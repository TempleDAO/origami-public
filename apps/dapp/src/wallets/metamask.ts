import { Chain } from '@/api/types';
import { ENABLE_API_LOGS } from '@/config';
import { ethers } from 'ethers';
import { AppWallet, WalletState } from './types';

/** AppWAllet implementation for metamask */
export async function createMetaMaskWallet(): Promise<AppWallet> {
  const ethereum = (window as unknown as { ethereum: LocalProvider }).ethereum;
  const provider = new ethers.providers.Web3Provider(ethereum, 'any');
  const signer = provider.getSigner();
  await provider.send('eth_requestAccounts', []);
  const address = await signer.getAddress();

  let state: WalletState = {
    address,
    connection: undefined,
  };

  async function connect(toChain: Chain): Promise<void> {
    if (state.connection && state.connection.chainId === toChain.id) {
      if (ENABLE_API_LOGS) {
        console.log(`already connected to ${toChain.name} (id ${toChain.id})`);
      }
      return;
    }

    if (ENABLE_API_LOGS) {
      console.log(`switching to ${toChain.name} (id ${toChain.id})`);
    }
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

    state = {
      ...state,
      connection: {
        chainId: toChain.id,
        signer,
      },
    };
  }

  async function disconnect(): Promise<void> {
    // Nothing to do for metamask
  }

  function getState(): WalletState {
    return state;
  }

  return { connect, disconnect, getState };
}

export type LocalProvider = {
  request: (request: {
    method: string;
    params?: Array<unknown>;
  }) => Promise<unknown>;
};
