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
  tickPercent,
  tickValue,
} from '@/components/HistoricLineChart';
import { Text } from '@/components/commons/Text';
import { useAsyncLoad } from '@/hooks/use-async-result';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { textH2, textH3 } from '@/styles/mixins/text-styles';
import { tabActiveGradientStyles } from '@/styles/mixins/tab-styles';

export type HistoricSeries =
  | { kind: 'investment-metric'; investment: Investment; metric: Metric }
  | { kind: 'token-price'; token: Token };

type InfoCardProps = {
  apr: Loading<string>;
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

export const InfoCard: FC<InfoCardProps> = ({
  apr,
  tvl,
  getHistory,
  investment,
  prices,
}) => {
  const [histPeriod, setHistPeriod] = useState<HistoricPeriod>('week');
  const [histSeries, setHistSeries] = useState<HistoricSeries>({
    kind: 'investment-metric',
    investment,
    metric: 'apr',
  });
  const [values] = useAsyncLoad(
    async () =>
      (await getHistory(histPeriod, histSeries)).map(convertHistoryPoint),
    [histPeriod, histSeries]
  );

  return (
    <Container>
      <Header investment={investment} />
      <ChartTogglers
        investment={investment}
        apr={apr}
        tvl={tvl}
        prices={prices}
        histSeries={histSeries}
        setHistSeries={setHistSeries}
      />
      <ChartContainer>
        <HistoricLineChart
          values={values}
          histPeriod={histPeriod}
          setHistPeriod={setHistPeriod}
          yTickFormat={
            histSeries.kind == 'investment-metric' &&
            histSeries.metric === 'apr'
              ? tickPercent
              : tickValue
          }
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
    <InfoText>{investment.info}</InfoText>
  </>
);

type ChartTogglersProps = {
  investment: Investment;
  apr: Loading<string>;
  tvl: Loading<string>;
  prices: {
    receiptToken: Loading<string>;
  };
  histSeries: HistoricSeries;
  setHistSeries: (series: HistoricSeries) => void;
};

const ChartTogglers: FC<ChartTogglersProps> = ({
  investment,
  apr,
  tvl,
  prices,
  histSeries,
  setHistSeries,
}) => (
  <ChartTogglesRow>
    <SeriesToggler
      active={isApr(histSeries)}
      onClick={() =>
        setHistSeries({ kind: 'investment-metric', investment, metric: 'apr' })
      }
    >
      <TogglerText>APR</TogglerText>
      <TogglerValue>
        <LoadingText value={apr} /> <TogglerValueSuffix>%</TogglerValueSuffix>
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

function isApr(hs: HistoricSeries): boolean {
  return hs.kind === 'investment-metric' && hs.metric === 'apr';
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
`;

const ChartContainer = styled.div`
  height: 260px;
  margin-bottom: 40px;
  width: 100%;
`;

const InfoText = styled(Text)`
  display: inline-block;
  color: ${({ theme }) => theme.colors.greyLight};
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
