import type { HistoricPeriod, HistoryPoint } from '@/api/types';

import LineChart from './LineChart';
import { theme } from '@/styles/theme';
import { format as formatDate } from 'date-fns';

import { isReady } from '@/utils/loading-value';
import type { Loading } from '@/utils/loading-value';
import styled from 'styled-components';
import { LoadingComponent } from '../commons/LoadingComponent';

type XAxisTickFormatter = (timestamp: number) => string;

export type ChartDataPoint = {
  x: number;
  y: number;
};

interface HistoricLineChartProps {
  chartData: Loading<ChartDataPoint[]>;
  selectedInterval: HistoricPeriod;
  legendFormatter?: (value: string) => string;
}
export default function HistoricLineChart(props: HistoricLineChartProps) {
  const { chartData, selectedInterval, legendFormatter } = props;

  if (!isReady(chartData)) {
    return <StyledLoader />;
  }

  const tickFormatters: Record<HistoricPeriod, XAxisTickFormatter> = {
    day: (timestamp) => formatDate(timestamp, 'h aaa'),
    week: (timestamp) => formatDate(timestamp, 'eee d LLL'),
    month: (timestamp) => formatDate(timestamp, 'MMM do'),
    all: (timestamp) => formatDate(timestamp, 'MMM do y'),
  };

  // const yDomain: AxisDomain = ([dataMin, dataMax]) => [dataMin - dataMin * 0.1, dataMax + dataMax * 0.1];

  const tooltipLabelFormatters: Record<HistoricPeriod, XAxisTickFormatter> = {
    ...tickFormatters,
    day: (timestamp) => formatDate(timestamp, 'MMM do, h aaa'),
  };

  const formatNumberFixedDecimals = (
    n: number | string,
    decimals = 2
  ): number => {
    if (typeof n === 'string') n = Number(n);
    return +Number(n).toFixed(decimals);
  };
  const tooltipValuesFormatter = (value: number, name: string) => [
    formatNumberFixedDecimals(value, 4).toString(),
    name,
  ];

  // Sort array by timestamp
  chartData.value.sort((a, b) => {
    return a.x - b.x;
  });

  return (
    <LineChart
      chartData={chartData.value}
      xDataKey="x"
      lines={[{ series: 'y', color: theme.colors.chartLine }]}
      xTickFormatter={tickFormatters[selectedInterval]}
      tooltipLabelFormatter={tooltipLabelFormatters[selectedInterval]}
      // yDomain={yDomain}
      legendFormatter={legendFormatter}
      tooltipValuesFormatter={(value, _) =>
        tooltipValuesFormatter(value, 'Value')
      }
    />
  );
}

export function convertHistoryPoint(p: HistoryPoint): ChartDataPoint {
  return { x: p.t.getTime(), y: p.v };
}

const StyledLoader = styled(LoadingComponent)`
  height: 16.25rem;
  height: 100%;
  width: 100%;
`;
