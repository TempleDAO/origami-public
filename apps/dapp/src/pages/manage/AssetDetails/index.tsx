import { FC, useCallback } from 'react';

import { useState } from 'react';
import styled from 'styled-components';
import { HistoricSeries, InfoCard } from './InfoCard';
import { ActionCard } from './ActionCard';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { lmap, lmap3, newLoading } from '@/utils/loading-value';
import {
  formatDecimalBigNumber,
  formatNumber,
  formatPercent,
} from '@/utils/formatNumber';
import { SignerApi, ProviderApi } from '@/api/api';
import { HistoricPeriod, Investment } from '@/api/types';
import { ApiCache } from '@/api/cache';
import { DBN_ZERO } from '@/utils/decimal-big-number';
import breakpoints from '@/styles/responsive-breakpoints';

export type AssetDetailsProps = {
  papi: ProviderApi;
  sapi: SignerApi;
  cache: ApiCache;
  investment: Investment;
};

export const AssetDetails: FC<AssetDetailsProps> = (props) => {
  const [activeFlow, setActiveFlow] = useState<JSX.Element | undefined>();
  const token = props.investment.receiptToken;
  const tokenBalance = lmap(props.cache.balances, (balances) => {
    return balances.get(props.investment) || DBN_ZERO;
  });

  const metrics = newLoading(props.cache.metrics.get(props.investment));
  const [tokenPrice] = useAsyncLoad(
    () => props.papi.getTokenUsdPrice(token),
    [token]
  );

  const values = lmap3(
    [tokenBalance, tokenPrice, metrics],
    (tokenBalance, tokenPrice, metrics) => ({
      apr: formatPercent(metrics.apr),
      tvl: formatNumber(metrics.tvl),
      tokenBalance: formatDecimalBigNumber(tokenBalance),
      tokenPrice: formatDecimalBigNumber(tokenPrice),
      tokenValue: formatDecimalBigNumber(tokenBalance.mul(tokenPrice)),
    })
  );

  const getHistory = useCallback(
    async (period: HistoricPeriod, series: HistoricSeries) => {
      if (series.kind == 'investment-metric') {
        return series.investment.getHistoricMetric({
          metric: series.metric,
          period,
        });
      } else {
        return props.papi.getHistoricTokenUsdPrice({
          token: series.token,
          period,
        });
      }
    },
    [props.papi]
  );

  return (
    <Container>
      {/* FLOW */}

      {activeFlow}

      {/* LEFT CARD */}

      <InfoCard
        investment={props.investment}
        apr={lmap(values, (v) => v.apr)}
        tvl={lmap(values, (v) => v.tvl)}
        getHistory={getHistory}
        prices={{ receiptToken: lmap(values, (v) => v.tokenPrice) }}
      />

      {/* RIGHT CARD */}

      <ActionCard
        investment={props.investment}
        papi={props.papi}
        sapi={props.sapi}
        apr={lmap(values, (v) => v.apr)}
        setActiveFlow={setActiveFlow}
        cache={props.cache}
        receiptTokenBalance={lmap(values, (v) => v.tokenBalance)}
        receiptTokenBalanceUsd={lmap(values, (v) => v.tokenValue)}
      />
    </Container>
  );
};

const Container = styled.div`
  display: flex;
  flex-direction: column;
  gap: 2rem;
  padding-bottom: 2rem;
  ${breakpoints.lg(`
    flex-direction: row;
    gap: 3.75rem;
  `)}
`;
