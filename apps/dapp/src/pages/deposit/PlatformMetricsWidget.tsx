import { Dispatch, SetStateAction, useState } from 'react';

import { HistoricPeriod, PlatformMetrics } from '@/api/types';
import {
  ChartDurations,
  ChartHeader,
  HistoricLineChart,
  convertHistoryPoint,
} from '@/components/Charts';
import styled from 'styled-components';
import { formatNumber } from '@/utils/formatNumber';
import { Card, CardColumn, GridValue, SuffixSpan } from '@/components/Card';
import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';
import { ProviderApi } from '@/api/api';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { LoadingText } from '@/components/commons/LoadingText';
import { Loading, lmap } from '@/utils/loading-value';
import { textH3 } from '@/styles/mixins/text-styles';
import breakpoints from '@/styles/responsive-breakpoints';
import { makeGridHeadings } from '@/components/commons/GridHeadingHolder';
import { FlexDown, FlexRightSpaced } from '@/flows/common/components';

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

  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.lg);

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

  const headings = makeGridHeadings([
    { name: '', widthWeight: 10 },
    { name: 'TVL', widthWeight: 2 },
  ]);

  return (
    <FlexDown>
      <CardColumn>
        {headings}
        <Card isExpanded={platformMetricsExpanded}>
          <CardContent>
            <TitleHolder onClick={onCardClick}>
              <Title>PLATFORM METRICS</Title>
            </TitleHolder>
            <FlexRightSpaced
              style={{ justifyContent: `${isDesktop ? 'center' : 'left'}` }}
            >
              <GridValue
                active={platformMetricsExpanded && histSeries === 'tvl'}
                onClick={onCardClick}
              >
                <LoadingText
                  value={lmap(platformTvl, formatNumber)}
                  suffix={<SuffixSpan> USD {!isDesktop && ' TVL'}</SuffixSpan>}
                />
              </GridValue>
            </FlexRightSpaced>
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
      </CardColumn>
    </FlexDown>
  );
};

const CardContent = styled.div`
  display: grid;
  row-gap: 1rem;
  grid-template-columns: 12fr 0fr;
  ${breakpoints.sm(`
    grid-template-columns: 10fr 2fr;
  `)}
`;

const TitleHolder = styled.div`
  cursor: pointer;
  display: flex;
  gap: 1rem;
  grid-column: 1/-1;
  ${breakpoints.sm(`
    grid-column: 1;
  `)}
`;

const Title = styled.div`
  ${textH3}
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms color ease;
`;

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
