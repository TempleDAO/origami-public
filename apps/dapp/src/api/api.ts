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
  ChainConfig,
  TokenConfig,
  InvestmentConfig,
} from './types';

/**
 * Endpoints that can be called without a connected wallet
 */
export interface ProviderApi {
  chains: VMap<ChainId, ChainConfig>;
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
  apr: number;
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
}

export interface InvestQuoteResp extends InvestQuoteReq {
  receiptTokenAmount: DecimalBigNumber;
  feeBps: DecimalBigNumber[];
  encodedQuote: unknown;
}

export interface InvestReq {
  quote: InvestQuoteResp;
  slippageBps: number;
  onStage?(stage: InvestStage): void;
}

export type InvestStage =
  | { kind: 'approve' }
  | { kind: 'invest' }
  | { kind: 'done'; result: InvestResp };

export interface InvestResp {
  receiptTokenAmount: DecimalBigNumber;
}

export interface ExitQuoteReq {
  investment: Investment;
  receiptTokenAmount: DecimalBigNumber;
  to: TokenOrNative;
}

export interface ExitQuoteResp extends ExitQuoteReq {
  toAmount: DecimalBigNumber;
  feeBps: DecimalBigNumber[];
  encodedQuote: unknown;
}

export interface ExitReq {
  quote: ExitQuoteResp;
  slippageBps: number;
  onStage?(stage: ExitStage): void;
}

export type ExitStage =
  | { kind: 'approve' }
  | { kind: 'exit' }
  | { kind: 'done'; result: ExitResp };

export interface ExitResp {
  amountOut: DecimalBigNumber;
}
