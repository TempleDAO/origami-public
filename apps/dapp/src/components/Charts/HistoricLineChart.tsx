import type { HistoricPeriod, HistoryPoint, MetricOrPrice } from '@/api/types';

import LineChart from './LineChart';
import { theme } from '@/styles/theme';
import { format as formatDate } from 'date-fns';
import { format } from 'd3-format';

import { isReady } from '@/utils/loading-value';
import type { Loading } from '@/utils/loading-value';
import styled from 'styled-components';
import { LoadingComponent } from '../commons/LoadingComponent';
import { assertNever } from '@/utils/assert';

type XAxisTickFormatter = (timestamp: number) => string;

export type ChartDataPoint = {
  x: number;
  y: number;
};

interface HistoricLineChartProps {
  chartData: Loading<ChartDataPoint[]>;
  selectedInterval: HistoricPeriod;
  histSeries: MetricOrPrice;
  legendFormatter?: (value: string) => string;
}
export default function HistoricLineChart(props: HistoricLineChartProps) {
  const { chartData, selectedInterval, histSeries, legendFormatter } = props;

  if (!isReady(chartData)) {
    return <StyledLoader />;
  }

  const tickFormatters: Record<HistoricPeriod, XAxisTickFormatter> = {
    day: (timestamp) => formatDate(timestamp, 'h aaa'),
    week: (timestamp) => formatDate(timestamp, 'eee d LLL'),
    month: (timestamp) => formatDate(timestamp, 'MMM do'),
    all: (timestamp) => formatDate(timestamp, 'MMM do y'),
  };

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
      yTickFormatter={tickSeries(histSeries)}
      tooltipLabelFormatter={tooltipLabelFormatters[selectedInterval]}
      yDomain={['auto', 'auto']}
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

export function tickSeries(series: MetricOrPrice): (v: number) => string {
  switch (series) {
    case 'apy':
      return tickPercent;
    case 'tvl':
      return tickValue;
    case 'price':
      return tickPrice;
    case 'reservesPerShare':
      return tickPrice;
    default:
      return assertNever(series);
  }
}

export function tickPrice(v: number): string {
  return format('.3f')(v);
}

export function tickValue(v: number): string {
  return format(Math.abs(v) < 1000 ? '.3' : '.3s')(v);
}

export function tickPercent(v: number): string {
  const percentage = v * 100;

  return `${format(Math.abs(percentage) < 1000 ? '.3' : '.1s')(percentage)}%`;
}

const StyledLoader = styled(LoadingComponent)`
  height: 16.25rem;
  height: 100%;
  width: 100%;
`;
