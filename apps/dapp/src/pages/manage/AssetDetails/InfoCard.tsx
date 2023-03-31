import type { FC } from 'react';
import type {
  HistoricPeriod,
  Metric,
  HistoryPoint,
  Investment,
  Token,
} from '@/api/types';
import type { Loading } from '@/utils/loading-value';

import { useState } from 'react';
import styled from 'styled-components';
import { InfoIcon } from './InfoIcon';
import { Icon } from '@/components/commons/Icon';
import { LoadingText } from '@/components/commons/LoadingText';
import { Tooltip } from '@/components/commons/Tooltip';
import {
  convertHistoryPoint,
  HistoricLineChart,
  tickSeries,
} from '@/components/HistoricLineChart';
import { useAsyncLoad } from '@/hooks/use-async-result';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { textH2, textH3 } from '@/styles/mixins/text-styles';
import { tabActiveGradientStyles } from '@/styles/mixins/tab-styles';
import {
  ChartDurations,
  ChartHeader,
  ChartPriceSeries,
} from '@/components/ChartControls';
import { InvestmentInfo } from '@/components/commons/InvestmentInfo';

export type HistoricSeries =
  | { kind: 'investment-metric'; investment: Investment; metric: Metric }
  | { kind: 'token-price'; token: Token };

type InfoCardProps = {
  apy: Loading<string>;
  tvl: Loading<string>;
  investment: Investment;
  getHistory: (
    period: HistoricPeriod,
    series: HistoricSeries
  ) => Promise<HistoryPoint[]>;
  prices: {
    receiptToken: Loading<string>;
  };
};

type MetricOrPrice = Metric | 'price';

export const InfoCard: FC<InfoCardProps> = ({
  apy,
  tvl,
  getHistory,
  investment,
  prices,
}) => {
  const [histPeriod, setHistPeriod] = useState<HistoricPeriod>('week');
  const [histSeries, setHistSeries] = useState<HistoricSeries>({
    kind: 'investment-metric',
    investment,
    metric: 'apy',
  });
  const [values] = useAsyncLoad(
    async () =>
      (await getHistory(histPeriod, histSeries)).map(convertHistoryPoint),
    [histPeriod, histSeries]
  );

  const metricOrPrice =
    histSeries.kind == 'investment-metric' ? histSeries.metric : 'price';
  function setMetricOrPrice(m: MetricOrPrice) {
    switch (m) {
      case 'price':
        setHistSeries({ kind: 'token-price', token: investment.receiptToken });
        break;
      default:
        setHistSeries({ kind: 'investment-metric', investment, metric: m });
        break;
    }
  }

  return (
    <Container>
      <Header investment={investment} />
      <ChartTogglers
        investment={investment}
        apy={apy}
        tvl={tvl}
        prices={prices}
        histSeries={histSeries}
        setHistSeries={setHistSeries}
      />
      <ChartContainer>
        <ChartHeader>
          <ChartDurations value={histPeriod} onChange={setHistPeriod} />
          {(metricOrPrice === 'price' ||
            metricOrPrice === 'reservesPerShare') && (
            <ChartPriceSeries
              receiptToken={investment.receiptToken.symbol}
              reserveToken={investment.reserveToken.symbol}
              value={metricOrPrice}
              onChange={(v) => setMetricOrPrice(v)}
            />
          )}
        </ChartHeader>
        <HistoricLineChart
          values={values}
          yTickFormat={tickSeries(
            histSeries.kind == 'investment-metric' ? histSeries.metric : 'price'
          )}
        />
      </ChartContainer>
    </Container>
  );
};

const Header: FC<{ investment: Investment }> = ({ investment }) => (
  <>
    <HeaderContainer>
      <Icon
        iconName={investment.receiptToken.iconName}
        size={32}
        hasBackground
      />
      <VerticalFlex>
        <Title>{investment.receiptToken.symbol}</Title>
        <Subtitle>{investment.description.toUpperCase()}</Subtitle>
      </VerticalFlex>
    </HeaderContainer>
    <InvestmentInfo>{investment.info}</InvestmentInfo>
  </>
);

type ChartTogglersProps = {
  investment: Investment;
  apy: Loading<string>;
  tvl: Loading<string>;
  prices: {
    receiptToken: Loading<string>;
  };
  histSeries: HistoricSeries;
  setHistSeries: (series: HistoricSeries) => void;
};

const ChartTogglers: FC<ChartTogglersProps> = ({
  investment,
  apy,
  tvl,
  prices,
  histSeries,
  setHistSeries,
}) => (
  <ChartTogglesRow>
    <SeriesToggler
      active={isApy(histSeries)}
      onClick={() =>
        setHistSeries({ kind: 'investment-metric', investment, metric: 'apy' })
      }
    >
      <TogglerText>APY</TogglerText>
      <TogglerValue>
        <LoadingText value={apy} /> <TogglerValueSuffix>%</TogglerValueSuffix>
      </TogglerValue>
    </SeriesToggler>
    <SeriesToggler
      active={isPrice(histSeries)}
      onClick={() =>
        setHistSeries({ kind: 'token-price', token: investment.receiptToken })
      }
    >
      <TogglerText>PRICE</TogglerText>
      <TogglerValue>
        <LoadingText value={prices.receiptToken} />{' '}
        <TogglerValueSuffix>USD</TogglerValueSuffix>
      </TogglerValue>
    </SeriesToggler>
    <SeriesToggler
      active={isTvl(histSeries)}
      onClick={() =>
        setHistSeries({ kind: 'investment-metric', investment, metric: 'tvl' })
      }
    >
      <Tooltip
        content={`Total Value Locked in the ${investment.name} Investment.`}
      >
        <TogglerText>
          TVL <InfoIcon />
        </TogglerText>
      </Tooltip>
      <TogglerValue>
        <LoadingText value={tvl} />
      </TogglerValue>
    </SeriesToggler>
  </ChartTogglesRow>
);

function isApy(hs: HistoricSeries): boolean {
  return hs.kind === 'investment-metric' && hs.metric === 'apy';
}

function isTvl(hs: HistoricSeries): boolean {
  return hs.kind === 'investment-metric' && hs.metric === 'tvl';
}

function isPrice(hs: HistoricSeries): boolean {
  return hs.kind === 'token-price';
}

const VerticalFlex = styled.div`
  display: flex;
  flex-direction: column;
`;

const Container = styled(VerticalFlex)`
  border-radius: 1.25rem;
  background-color: ${({ theme }) => theme.colors.bgMid};
  ${sunkenStyles}
  padding: 1rem;
  width: 100%;
`;

const ChartContainer = styled.div`
  height: 260px;
  margin-bottom: 40px;
  width: 100%;
`;

const HeaderContainer = styled.div`
  display: flex;
  align-items: center;
  gap: 1.25rem;
  margin-bottom: 1.25rem;
`;

const Title = styled.h1`
  margin: 0;
  line-height: 2.0625rem;
`;

const Subtitle = styled.h3`
  margin: 0;
  color: ${({ theme }) => theme.colors.greyLight};
  line-height: 1.3125rem;
`;

const ChartTogglesRow = styled.div`
  display: flex;
  max-width: 25rem;
  justify-content: space-between;
  margin-top: 2.5rem;
  margin-bottom: 0.5rem;
`;

const TogglerValue = styled.span`
  ${textH2}
  transition: 300ms ease color;
`;

const SeriesToggler = styled(VerticalFlex)<{ active?: boolean }>`
  cursor: pointer;
  ${({ active }) => active && tabActiveGradientStyles};
  &:hover {
    ${TogglerValue} {
      color: ${({ theme }) => theme.colors.greyLight};
    }
  }
`;

const TogglerText = styled.h3`
  margin: 0;
  color: ${({ theme }) => theme.colors.greyLight};
`;

const TogglerValueSuffix = styled.span`
  ${textH3}

  color: ${({ theme }) => theme.colors.greyLight};
`;
