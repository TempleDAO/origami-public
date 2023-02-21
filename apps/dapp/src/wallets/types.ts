import { Chain, ChainId } from '@/api/types';
import { Signer } from 'ethers';

export interface WalletState {
  address: string;
  connection: WalletConnection | undefined;
}

export interface WalletConnection {
  chainId: ChainId;
  signer: Signer;
}

/**
 * Abstract interface for wallets
 */
export interface AppWallet {
  getState(): WalletState;
  connect(chainId: Chain): Promise<void>;
  disconnect(): Promise<void>;
}
