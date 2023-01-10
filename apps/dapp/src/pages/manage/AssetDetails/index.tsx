import { FC, useCallback } from 'react';

import { useState } from 'react';
import styled from 'styled-components';
import { HistoricSeries, InfoCard } from './InfoCard';
import { ActionCard } from './ActionCard';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { lmap } from '@/utils/loading-value';
import {
  formatDecimalBigNumber,
  formatNumber,
  formatPercent,
} from '@/utils/formatNumber';
import { SignerApi, ProviderApi } from '@/api/api';
import { HistoricPeriod, Investment } from '@/api/types';

export type AssetDetailsProps = {
  papi: ProviderApi;
  sapi: SignerApi;
  investment: Investment;
};

export const AssetDetails: FC<AssetDetailsProps> = (props) => {
  const [activeFlow, setActiveFlow] = useState<JSX.Element | undefined>();
  const receiptToken = props.investment.receiptToken;
  const userAddress = props.sapi.signerAddress;

  const [values] = useAsyncLoad(async () => {
    const metrics = await props.investment.getMetrics();
    const tokenPrice = await props.papi.getTokenUsdPrice(receiptToken);
    const receiptTokenBalance = await props.papi.getTokenBalance(
      receiptToken,
      userAddress
    );

    return {
      apr: formatPercent(metrics.apr),
      tvl: formatNumber(metrics.apr),
      receiptTokenPrice: formatDecimalBigNumber(tokenPrice),
      receiptTokenBalance: formatDecimalBigNumber(receiptTokenBalance),
      receiptTokenBalanceUsd: formatDecimalBigNumber(
        receiptTokenBalance.mul(tokenPrice)
      ),
    };
  });

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
        prices={{ receiptToken: lmap(values, (v) => v.receiptTokenPrice) }}
      />

      {/* RIGHT CARD */}

      <ActionCard
        investment={props.investment}
        papi={props.papi}
        sapi={props.sapi}
        apr={lmap(values, (v) => v.apr)}
        setActiveFlow={setActiveFlow}
        receiptTokenBalance={lmap(values, (v) => v.receiptTokenBalance)}
        receiptTokenBalanceUsd={lmap(values, (v) => v.receiptTokenBalanceUsd)}
      />
    </Container>
  );
};

const Container = styled.div`
  display: flex;
  gap: 3.75rem;
  padding-bottom: 2rem;
`;
