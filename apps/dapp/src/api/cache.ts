import { useAsyncLoad } from '@/hooks/use-async-result';
import { investmentKey } from '@/utils/api-utils';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { isReady, Loading } from '@/utils/loading-value';
import { asyncNever } from '@/utils/noop';
import { VMap } from '@/utils/vmap';
import { useEffect, useMemo, useState } from 'react';
import { MetricsResp, ProviderApi } from './api';
import { Investment } from './types';

export interface ApiCache {
  // All available investments
  investments: Loading<Investment[]>;

  // The investment balances of the current signer
  balances: Loading<BalanceMap>;
  refreshBalances(): void;

  // The metrics of each investment
  metrics: MetricsVMap;

  // The token price of each investment
  tokenPrices: TokenPricesVMap;
}

export type BalanceMap = VMap<Investment, DecimalBigNumber>;
export type MetricsVMap = VMap<Investment, MetricsResp>;
export type TokenPricesVMap = VMap<Investment, DecimalBigNumber>;

export function useCache(
  papi: ProviderApi,
  address: string | undefined
): ApiCache {
  const [investments] = useAsyncLoad(() => {
    return Promise.all(papi.investments.map((ic) => papi.getInvestment(ic)));
  }, [papi]);

  const [balances, refreshBalances] = useAsyncLoad(
    () => loadBalances(papi, address),
    [papi, address]
  );

  const [metrics, setMetrics] = useState<MetricsVMap>(
    () => new VMap(investmentKey)
  );

  const [tokenPrices, setTokenPrices] = useState<TokenPricesVMap>(
    () => new VMap(investmentKey)
  );

  useEffect(() => {
    async function loadMetrics(investment: Investment) {
      const metrics = await investment.getMetrics();
      setMetrics((mmap) => mmap.withPut(investment, metrics));
    }

    async function loadTokenPrices(investment: Investment) {
      const price = await papi.getTokenUsdPrice(investment.receiptToken);
      setTokenPrices((pmap) => pmap.withPut(investment, price));
    }

    if (isReady(investments)) {
      for (const investment of investments.value) {
        loadMetrics(investment);
        loadTokenPrices(investment);
      }
    }
  }, [investments, papi]);

  const cache = useMemo(
    () => ({
      investments,
      balances,
      refreshBalances,
      metrics,
      tokenPrices,
    }),
    [investments, balances, refreshBalances, metrics, tokenPrices]
  );

  return cache;
}

async function loadBalances(
  papi: ProviderApi,
  address: string | undefined
): Promise<VMap<Investment, DecimalBigNumber>> {
  if (!address) {
    return asyncNever();
  }
  const entries = await Promise.all(
    papi.investments.map(async (ic) => {
      const investment = await papi.getInvestment(ic);
      const balance = await papi.getTokenBalance(
        investment.receiptToken,
        address
      );
      return { k: investment, v: balance };
    })
  );
  return VMap.fromEntries(investmentKey, entries);
}
