import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { VMap } from '@/utils/vmap';
import {
  ChainId,
  HistoricPeriod,
  HistoryPoint,
  Investment,
  Token,
  TokenOrNative,
  Metric,
  TokenConfig,
  InvestmentConfig,
  Chain,
} from './types';

/**
 * Endpoints that can be called without a connected wallet
 */
export interface ProviderApi {
  chains: VMap<ChainId, Chain>;
  investments: InvestmentConfig[];

  getToken(config: TokenConfig): Promise<Token>;

  getInvestment(config: InvestmentConfig): Promise<Investment>;

  getNativeBalance(chain: ChainId, address: string): Promise<DecimalBigNumber>;
  getTokenBalance(token: Token, address: string): Promise<DecimalBigNumber>;

  getNativeUsdPrice(chain: ChainId): Promise<DecimalBigNumber>;
  getTokenUsdPrice(token: Token): Promise<DecimalBigNumber>;
  getHistoricTokenUsdPrice(
    req: HistoricTokenUsdPriceReq
  ): Promise<HistoryPoint[]>;

  investQuote(req: InvestQuoteReq): Promise<InvestQuoteResp>;
  exitQuote(req: ExitQuoteReq): Promise<ExitQuoteResp>;
}

/**
 * Endpoints that require a connected wallet
 */
export interface SignerApi {
  // The address of the current signer
  signerAddress: string;

  // The chain of the current signer.
  chainId: ChainId;

  invest(req: InvestReq): Promise<InvestResp>;

  exit(req: ExitReq): Promise<ExitResp>;
}

export interface MetricsResp {
  tvl: number;
  apy: number;
}

export interface HistoricTokenUsdPriceReq {
  token: Token;
  period: HistoricPeriod;
}

export interface HistoricMetricReq {
  metric: Metric;
  period: HistoricPeriod;
}

export interface InvestQuoteReq {
  investment: Investment;
  amount: DecimalBigNumber;
  from: TokenOrNative;
  slippageBps: number;
  deadline: number;
}

export interface InvestQuoteResp extends InvestQuoteReq {
  expectedInvestmentAmount: DecimalBigNumber;
  minInvestmentAmount: DecimalBigNumber;
  feeBps: DecimalBigNumber[];
  encodedQuote: unknown;
}

export interface InvestReq {
  quote: InvestQuoteResp;
  onStage?(stage: InvestStage): void;
}

export type InvestStage =
  | { kind: 'approve' }
  | { kind: 'invest' }
  | { kind: 'txfail'; message: string; txhash?: string }
  | { kind: 'done'; result: InvestResp };

export interface InvestResp {
  investTokenAmount: DecimalBigNumber;
  txHash: string;
}

export interface ExitQuoteReq {
  investment: Investment;
  exitAmount: DecimalBigNumber;
  to: TokenOrNative;
  slippageBps: number;
  deadline: number;
}

export interface ExitQuoteResp extends ExitQuoteReq {
  expectedToAmount: DecimalBigNumber;
  minToAmount: DecimalBigNumber;
  feeBps: DecimalBigNumber[];
  encodedQuote: unknown;
}

export interface ExitReq {
  quote: ExitQuoteResp;
  onStage?(stage: ExitStage): void;
}

export type ExitStage =
  | { kind: 'approve' }
  | { kind: 'exit' }
  | { kind: 'txfail'; message: string; txhash?: string }
  | { kind: 'done'; result: ExitResp };

export interface ExitResp {
  amountOut: DecimalBigNumber;
  txHash: string;
}
