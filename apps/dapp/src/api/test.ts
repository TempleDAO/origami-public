import {
  ExitQuoteReq,
  ExitQuoteResp,
  ExitReq,
  ExitResp,
  HistoricMetricReq,
  HistoricTokenUsdPriceReq,
  InvestQuoteReq,
  InvestQuoteResp,
  InvestReq,
  InvestResp,
  MetricsResp,
  ProviderApi,
  SignerApi,
} from '@/api/api';
import {
  Chain,
  ChainExplorer,
  ChainId,
  HistoricPeriod,
  HistoryPoint,
  Investment,
  InvestmentConfig,
  Metric,
  Token,
  TokenConfig,
  TokenOrNative,
} from '@/api/types';

import { useMemo } from 'react';
import { newToken, tokenKey, tokenOrNativeUsdPrice } from '@/utils/api-utils';
import { DBN_ZERO, DecimalBigNumber } from '@/utils/decimal-big-number';
import { sleep } from '@/utils/sleep';
import { VMap } from '@/utils/vmap';
import { createMemoizedAsyncValue } from '@/utils/memoized';
import { ApiCache, useCache } from '@/api/cache';

interface TestApi {
  sleepMs: number;
}

export type TestProviderApi = ProviderApi;

export type TestSignerApi = TestApi & SignerApi;

export function useTestApis(sleepMs?: number): {
  papi: TestProviderApi;
  sapi: TestSignerApi;
  cache: ApiCache;
} {
  const papi = useMemo(() => new TestProviderApiImpl(), []);
  const sapi = useMemo(() => new TestSignerApiImpl(), []);
  const cache = useCache(papi, sapi.signerAddress);

  if (sleepMs !== undefined) {
    papi.sleepMs = sleepMs;
    sapi.sleepMs = sleepMs;
  }
  return { papi, sapi, cache };
}

export function tokenUsdPrices(): VMap<Token, DecimalBigNumber> {
  const prices = new VMap<Token, DecimalBigNumber>(tokenKey);
  prices.put(dai(), DecimalBigNumber.parseUnits('1', 2));
  prices.put(gmx(), DecimalBigNumber.parseUnits('45.19', 2));
  prices.put(ovGmx(), DecimalBigNumber.parseUnits('45.19', 2));
  prices.put(glp(), DecimalBigNumber.parseUnits('0.82', 2));
  prices.put(ovGlp(), DecimalBigNumber.parseUnits('0.82', 2));
  return prices;
}

export function nativeUsdPrices(): VMap<ChainId, DecimalBigNumber> {
  const prices = new VMap<ChainId, DecimalBigNumber>((c) => c.toString());
  prices.put(ARBITRUM_ID, DecimalBigNumber.parseUnits('1800', 18));
  return prices;
}

class TestProviderApiImpl implements TestProviderApi {
  tokenPrices = tokenUsdPrices();
  nativePrices = nativeUsdPrices();

  sleepMs = 500;

  chains = new VMap<ChainId, Chain>((c) => '' + c);
  investments: InvestmentConfig[] = [gmxInvestment(), glpInvestment()];

  constructor() {
    const a = arbitrum();
    this.chains.put(a.id, {
      name: a.name,
      id: a.id,
      nativeCurrency: a.nativeCurrency,
      rpcUrl: 'http://something',
      walletRpcUrl: 'http://something',
      subgraphUrl: 'http://something',
      explorer: dummyExplorer(),
    });
  }

  async getToken(config: TokenConfig): Promise<Token> {
    const tokens: Token[] = [dai(), gmx(), ovGmx(), glp(), ovGlp()];
    for (const t of tokens) {
      if (
        config.address == t.config.address &&
        config.chainId == t.config.chainId
      ) {
        return t;
      }
    }
    throw new Error('Token not found');
  }

  async getInvestment(config: InvestmentConfig): Promise<Investment> {
    await sleep(this.sleepMs);
    const gmx = gmxInvestment();
    if (config.contractAddress.address == gmx.contractAddress.address) {
      return gmx;
    }
    const glp = glpInvestment();
    if (config.contractAddress.address == glp.contractAddress.address) {
      return glp;
    }
    throw new Error('Investment not found');
  }

  async getHistoricTokenUsdPrice(
    req: HistoricTokenUsdPriceReq
  ): Promise<HistoryPoint[]> {
    await sleep(this.sleepMs);
    return getHistory1(req.period, PRICE_DATA);
  }

  async getNativeBalance(
    _chain: ChainId,
    _address: string
  ): Promise<DecimalBigNumber> {
    await sleep(this.sleepMs);
    return DecimalBigNumber.parseUnits('10', 18);
  }
  async getTokenBalance(
    _token: Token,
    _address: string
  ): Promise<DecimalBigNumber> {
    await sleep(this.sleepMs);
    return DecimalBigNumber.parseUnits('1000', 18);
  }

  async getNativeUsdPrice(chain: ChainId): Promise<DecimalBigNumber> {
    await sleep(this.sleepMs);
    return this.nativePrices.get(chain) || DBN_ZERO;
  }

  async getTokenUsdPrice(token: Token): Promise<DecimalBigNumber> {
    await sleep(this.sleepMs);
    return this.tokenPrices.get(token) || DBN_ZERO;
  }

  async investQuote(req: InvestQuoteReq): Promise<InvestQuoteResp> {
    const investUsdAmount = (await tokenOrNativeUsdPrice(this, req.from)).mul(
      req.amount
    );
    const receiptTokenAmount = investUsdAmount.div(
      await this.getTokenUsdPrice(req.investment.receiptToken),
      req.investment.receiptToken.decimals
    );
    return {
      investment: req.investment,
      amount: req.amount,
      from: req.from,
      feeBps: [],
      receiptTokenAmount,
      encodedQuote: '',
    };
  }

  async exitQuote(req: ExitQuoteReq): Promise<ExitQuoteResp> {
    const inUsdAmount = (
      await this.getTokenUsdPrice(req.investment.receiptToken)
    ).mul(req.receiptTokenAmount);
    const toAmount = inUsdAmount.div(
      await tokenOrNativeUsdPrice(this, req.to),
      req.investment.receiptToken.decimals
    );
    return {
      investment: req.investment,
      receiptTokenAmount: req.receiptTokenAmount,
      to: req.to,
      feeBps: [],
      toAmount,
      encodedQuote: '',
    };
  }
}

class TestSignerApiImpl implements TestSignerApi {
  signerAddress = TEST_SIGNER_ADDRESS;
  sleepMs = 1000;

  chain = arbitrum();
  chainId = this.chain.id;

  async invest(req: InvestReq): Promise<InvestResp> {
    req.onStage && req.onStage({ kind: 'approve' });
    await sleep(this.sleepMs);
    req.onStage && req.onStage({ kind: 'invest' });
    await sleep(this.sleepMs);
    const result = {
      receiptTokenAmount: req.quote.receiptTokenAmount,
      txExplorerUrl: this.chain.explorer.transactionUrl('0x1234'),
    };
    req.onStage && req.onStage({ kind: 'done', result });
    return result;
  }

  async exit(req: ExitReq): Promise<ExitResp> {
    req.onStage && req.onStage({ kind: 'approve' });
    await sleep(this.sleepMs);
    req.onStage && req.onStage({ kind: 'exit' });
    await sleep(this.sleepMs);
    const result = {
      amountOut: req.quote.toAmount,
      txExplorerUrl: this.chain.explorer.transactionUrl('0x1234'),
    };
    req.onStage && req.onStage({ kind: 'done', result });
    return result;
  }
}

const TEST_SIGNER_ADDRESS = '0xSIGNER';

const ARBITRUM_ID = 42161;

export function arbitrum(): Chain {
  return {
    id: ARBITRUM_ID,
    name: 'Arbitrum One',
    nativeCurrency: {
      symbol: 'ETH',
      name: 'Ether',
      decimals: 18,
    },
    explorer: dummyExplorer(),
    rpcUrl: 'http://somewhere',
    walletRpcUrl: 'http://somewhere',
    subgraphUrl: 'http://somewhere',
  };
}

export function dummyExplorer(): ChainExplorer {
  return {
    transactionUrl: (hash) => `https:/dummy-explorer/tx/${hash}`,
    tokenUrl: (hash) => `https:/dummy-explorer/token/${hash}`,
  };
}

function dai(): Token {
  return newToken('DAI', 'dai', 18, {
    address: '0xERC20-DAI',
    chainId: ARBITRUM_ID,
  });
}

function gmx(): Token {
  return newToken('GMX', 'gmx', 18, {
    address: '0xERC20-GMX',
    chainId: ARBITRUM_ID,
  });
}

function ovGmx(): Token {
  return newToken('ovGMX', 'gmx', 18, {
    address: '0xERC20-OVGMX',
    chainId: ARBITRUM_ID,
  });
}

function glp(): Token {
  return newToken('GLP', 'glp', 18, {
    address: '0xERC20-GLP',
    chainId: ARBITRUM_ID,
  });
}

function ovGlp(): Token {
  return newToken('ovGLP', 'glp', 18, {
    address: '0xERC20-OVGLP',
    chainId: ARBITRUM_ID,
  });
}

export function gmxInvestment(): Investment {
  async function getMetrics(): Promise<MetricsResp> {
    await sleep(500);
    return {
      tvl: 1200000,
      apy: 0.0823,
    };
  }
  async function getHistoricMetric(
    req: HistoricMetricReq
  ): Promise<HistoryPoint[]> {
    await sleep(500);
    return getHistory(req.period, req.metric);
  }
  const acceptedTokens = createMemoizedAsyncValue(async () => {
    await sleep(500);
    return gmxAcceptedToken();
  });
  return {
    contractAddress: { address: '0xINVEST-GMX', chainId: arbitrum().id },
    icon: 'gmx',
    name: 'ovGMX',
    description: 'Origami investment in the GMX utility token',
    supportedAssetsDescription: 'GMX',
    receiptToken: ovGmx(),
    acceptedInvestTokens: acceptedTokens.get,
    acceptedExitTokens: acceptedTokens.get,
    getMetrics,
    getHistoricMetric,
    chain: arbitrum(),
    info: investInfo('GMX'),
    moreInfoUrl:
      'https://arbiscan.io/token/0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
  };
}

export function gmxAcceptedToken(): TokenOrNative[] {
  return [
    { kind: 'native', chain: arbitrum() },
    { kind: 'token', token: gmx() },
    { kind: 'token', token: dai() },
  ];
}

export function glpInvestment(): Investment {
  async function getMetrics(): Promise<MetricsResp> {
    await sleep(500);
    return {
      tvl: 800000,
      apy: 0.0492,
    };
  }
  async function getHistoricMetric(
    req: HistoricMetricReq
  ): Promise<HistoryPoint[]> {
    await sleep(500);
    return getHistory(req.period, req.metric);
  }
  const acceptedTokens = createMemoizedAsyncValue(async () => {
    await sleep(500);
    return gmxAcceptedToken();
  });
  return {
    contractAddress: { address: '0xINVEST-GLP', chainId: arbitrum().id },
    icon: 'glp',
    name: 'ovGLP',
    description: 'Origami investment in the GMX liquidity provider (LP) token',
    supportedAssetsDescription:
      'staked GLP or one of the underlying GLP assets',
    receiptToken: ovGlp(),
    acceptedInvestTokens: acceptedTokens.get,
    acceptedExitTokens: acceptedTokens.get,
    getMetrics,
    getHistoricMetric,
    chain: arbitrum(),
    info: investInfo('GMX LP'),
    moreInfoUrl:
      'https://arbiscan.io/token/0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
  };
}

function investInfo(s: string) {
  return `
  Info on the ${s} investment. Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book.
  `;
}

const APY_DATA = [
  { t: new Date('2022-07-01'), v: 0.1 },
  { t: new Date('2022-07-02'), v: 0.13 },
  { t: new Date('2022-07-03'), v: 0.12 },
  { t: new Date('2022-07-04'), v: 0.125 },
  { t: new Date('2022-07-05'), v: 0.16 },
  { t: new Date('2022-07-06'), v: 0.1 },
  { t: new Date('2022-07-07'), v: 0.13 },
  { t: new Date('2022-07-08'), v: 0.12 },
  { t: new Date('2022-07-09'), v: 0.125 },
  { t: new Date('2022-07-10'), v: 0.16 },
  { t: new Date('2022-07-11'), v: 0.1 },
  { t: new Date('2022-07-12'), v: 0.13 },
  { t: new Date('2022-07-13'), v: 0.12 },
  { t: new Date('2022-07-14'), v: 0.125 },
  { t: new Date('2022-07-15'), v: 0.26 },
  { t: new Date('2022-07-16'), v: 0.2 },
  { t: new Date('2022-07-17'), v: 0.23 },
  { t: new Date('2022-07-18'), v: 0.15 },
  { t: new Date('2022-07-19'), v: 0.135 },
  { t: new Date('2022-07-20T00:00'), v: 0.16 },
  { t: new Date('2022-07-20T06:00'), v: 0.162 },
  { t: new Date('2022-07-20T12:00'), v: 0.162 },
  { t: new Date('2022-07-20T18:00'), v: 0.171 },
];

const TVL_DATA = [
  { t: new Date('2022-07-01'), v: 1000000 },
  { t: new Date('2022-07-02'), v: 1200000 },
  { t: new Date('2022-07-03'), v: 1300000 },
  { t: new Date('2022-07-04'), v: 1350000 },
  { t: new Date('2022-07-05'), v: 1600000 },
  { t: new Date('2022-07-06'), v: 1700000 },
  { t: new Date('2022-07-07'), v: 1700000 },
  { t: new Date('2022-07-08'), v: 1800000 },
  { t: new Date('2022-07-09'), v: 1850000 },
  { t: new Date('2022-07-10'), v: 1600000 },
  { t: new Date('2022-07-11'), v: 1300000 },
  { t: new Date('2022-07-12'), v: 1400000 },
  { t: new Date('2022-07-13'), v: 1500000 },
  { t: new Date('2022-07-14'), v: 1500000 },
  { t: new Date('2022-07-15'), v: 1900000 },
  { t: new Date('2022-07-16'), v: 1950000 },
  { t: new Date('2022-07-17'), v: 1800000 },
  { t: new Date('2022-07-18'), v: 1800000 },
  { t: new Date('2022-07-19'), v: 1850000 },
  { t: new Date('2022-07-20T00:00'), v: 2100000 },
  { t: new Date('2022-07-20T06:00'), v: 2200000 },
  { t: new Date('2022-07-20T12:00'), v: 2200000 },
  { t: new Date('2022-07-20T18:00'), v: 2300000 },
];

const PRICE_DATA = [
  { t: new Date('2022-07-01'), v: 2.3 },
  { t: new Date('2022-07-02'), v: 2.33 },
  { t: new Date('2022-07-03'), v: 2.38 },
  { t: new Date('2022-07-04'), v: 2.75 },
  { t: new Date('2022-07-05'), v: 2.7 },
  { t: new Date('2022-07-06'), v: 2.69 },
  { t: new Date('2022-07-07'), v: 2.53 },
  { t: new Date('2022-07-08'), v: 2.22 },
  { t: new Date('2022-07-09'), v: 2.4 },
  { t: new Date('2022-07-10'), v: 2.78 },
  { t: new Date('2022-07-11'), v: 2.95 },
  { t: new Date('2022-07-12'), v: 3.02 },
  { t: new Date('2022-07-13'), v: 3.25 },
  { t: new Date('2022-07-14'), v: 3.05 },
  { t: new Date('2022-07-15'), v: 2.69 },
  { t: new Date('2022-07-16'), v: 2.68 },
  { t: new Date('2022-07-17'), v: 2.66 },
  { t: new Date('2022-07-18'), v: 2.61 },
  { t: new Date('2022-07-19'), v: 2.7 },
  { t: new Date('2022-07-20T00:00'), v: 2.72 },
  { t: new Date('2022-07-20T06:00'), v: 2.69 },
  { t: new Date('2022-07-20T12:00'), v: 2.7 },
  { t: new Date('2022-07-20T18:00'), v: 2.45 },
];

export async function getHistory(
  period: HistoricPeriod,
  series: Metric
): Promise<HistoryPoint[]> {
  return getHistory1(period, series == 'apy' ? APY_DATA : TVL_DATA);
}

export async function getHistory1(
  period: HistoricPeriod,
  data: HistoryPoint[]
): Promise<HistoryPoint[]> {
  await sleep(1000);
  function slice(data: HistoryPoint[]): HistoryPoint[] {
    switch (period) {
      case 'day':
        return data.slice(-4);
      case 'week':
        return data.slice(-11);
      case 'month':
        return data;
      case 'all':
        return data;
    }
  }
  return slice(data);
}
