import { Dispatch, SetStateAction, useState } from 'react';

import { HistoricPeriod, PlatformMetrics } from '@/api/types';
import { FlexDown } from '@/flows/common/components';
import {
  ChartDurations,
  ChartHeader,
  HistoricLineChart,
  convertHistoryPoint,
} from '@/components/Charts';
import styled from 'styled-components';
import { formatNumber } from '@/utils/formatNumber';
import {
  Card,
  CardContent,
  CardHeader,
  GridValue,
  SuffixSpan,
} from '@/components/Card';
import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';
import { ProviderApi } from '@/api/api';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { LoadingText } from '@/components/commons/LoadingText';
import { Loading, lmap } from '@/utils/loading-value';
import { textH3 } from '@/styles/mixins/text-styles';

interface PlatformMetricsWidgetProps {
  platformMetricsExpanded: boolean;
  setPlatformMetricsExpanded: Dispatch<SetStateAction<boolean>>;
  setVaultExpanded: Dispatch<SetStateAction<number | undefined>>;
  platformTvl: Loading<number>;
  papi: ProviderApi;
}

export const PlatformMetricsWidget = (props: PlatformMetricsWidgetProps) => {
  const {
    platformMetricsExpanded,
    setPlatformMetricsExpanded,
    setVaultExpanded,
    platformTvl,
    papi,
  } = props;
  const [histSeries, setHistSeries] =
    useState<PlatformMetrics | undefined>('tvl');
  const [histPeriod, setHistPeriod] = useState<HistoricPeriod>('week');

  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  const onCardClick = () => {
    setPlatformMetricsExpanded(!platformMetricsExpanded);
    setHistSeries(histSeries);
    setVaultExpanded(undefined);
  };

  const [values] = useAsyncLoad(async () => {
    if (!papi || !histSeries) return [];
    return (
      await papi.getHistoricPlatformMetric({
        metric: histSeries,
        period: histPeriod,
      })
    ).map(convertHistoryPoint);
  }, [papi, histSeries, histPeriod]);

  return (
    <FlexDown>
      <MetricsLabel onClick={onCardClick}>TVL</MetricsLabel>
      <Card isExpanded={platformMetricsExpanded}>
        <CardHeader onClick={onCardClick}>
          <InvestmentName style={{ maxWidth: isDesktop ? 'auto' : 150 }}>
            PLATFORM METRICS
          </InvestmentName>
          <FlexDown>
            <GridValue
              active={platformMetricsExpanded && histSeries === 'tvl'}
              onClick={() => {
                platformMetricsExpanded;
                setHistSeries('tvl');
              }}
            >
              <LoadingText
                value={lmap(platformTvl, formatNumber)}
                suffix={<SuffixSpan> USD {!isDesktop && ' TVL'}</SuffixSpan>}
              />
            </GridValue>
          </FlexDown>
        </CardHeader>
        <CardContent>
          {platformMetricsExpanded && (
            <Graph>
              <ChartHeader>
                <ChartDurations value={histPeriod} onChange={setHistPeriod} />
              </ChartHeader>
              <HistoricLineChart
                chartData={values}
                selectedInterval={histPeriod}
                histSeries={'tvl'}
              />
            </Graph>
          )}
        </CardContent>
      </Card>
    </FlexDown>
  );
};

const Graph = styled.div`
  display: flex;
  padding-top: 1.5rem;
  flex-direction: column;
  align-items: stretch;
  justify-content: center;
  grid-column: 1/-1;
  div {
    margin-bottom: 0;
  }
`;

const MetricsLabel = styled.div`
  ${textH3}
  margin: 0 65px 10px 0;
  align-self: flex-end;
  color: ${({ theme }) => theme.colors.greyLight};
  cursor: pointer;
`;

const InvestmentName = styled.div`
  ${textH3}
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms color ease;
`;
