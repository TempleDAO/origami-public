import { BigNumber } from 'ethers';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { HistoricMetricReq, MetricsResp } from './api';

export type ChainId = number;

export interface ContractAddress {
  address: string;
  chainId: ChainId;
}

export interface Chain {
  id: ChainId;
  name: string;
  nativeCurrency: NativeCurrency;
  explorer: ChainExplorer;
  rpcUrl: string;
  walletRpcUrl: string;
  subgraphUrl: string;
  iconName: string;
}

export interface ChainExplorer {
  transactionUrl(txhash: string): string;
  tokenUrl(tokenHash: string): string;
}

export interface NativeCurrency {
  symbol: string;
  name: string;
  decimals: number;
}

export interface TokenConfig extends ContractAddress {
  // If not provided, these will be read from on chain
  symbol?: string;
  decimals?: number;
}

export interface Token {
  config: TokenConfig;
  symbol: string;
  iconName: string;
  decimals: number;

  formatLocale(v: DecimalBigNumber): string;
  formatUnits(v: DecimalBigNumber): string;
  parseUnits(v: string): DecimalBigNumber;
  fromBN(v: BigNumber): DecimalBigNumber;
  toBN(v: DecimalBigNumber): BigNumber;
}

export interface InvestmentConfig {
  contractAddress: ContractAddress;
  icon: string;
  name: string;
  description: string;
  supportedAssetsDescription: string;
  info: string;
  moreInfoUrl?: string;
}

export type PriceContractConfig = ContractAddress;

export interface Investment extends InvestmentConfig {
  chain: Chain;

  receiptToken: Token;
  acceptedInvestTokens(): Promise<TokenOrNative[]>;
  acceptedExitTokens(): Promise<TokenOrNative[]>;
  getMetrics(): Promise<MetricsResp>;
  getHistoricMetric(req: HistoricMetricReq): Promise<HistoryPoint[]>;
}

export type TokenOrNative =
  | { kind: 'token'; token: Token }
  | { kind: 'native'; chain: Chain };

export type HistoricPeriod = 'day' | 'week' | 'month' | 'all';

export interface HistoryPoint {
  t: Date;
  v: number;
}

export type Metric = 'tvl' | 'apy';
