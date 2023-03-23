import type { HistoryPoint } from '@/api/types';
import type { Loading } from '@/utils/loading-value';

import { useState, useCallback } from 'react';
import styled from 'styled-components';
import { format } from 'd3-format';
import { format as formatDate } from 'date-fns';
import {
  FlexibleXYPlot,
  Crosshair,
  HorizontalGridLines,
  LineSeries,
  AreaSeries,
  XAxis,
  YAxis,
  RVTickFormat,
} from 'react-vis';
import { LoadingComponent } from './commons/LoadingComponent';
import { useMediaQuery } from '@/hooks/use-media-query';
import { isReady } from '@/utils/loading-value';
import { theme } from '@/styles/theme';

import 'react-vis/dist/style.css';
import { assertNever } from '@/utils/assert';

export type ChartDataPoint = {
  x: number;
  y: number;
};

export type HistoricLineChartProps = {
  values: Loading<ChartDataPoint[]>;
  yTickFormat: RVTickFormat;
};

export function HistoricLineChart(props: HistoricLineChartProps): JSX.Element {
  const ldata = props.values;
  const { onMouseLeave, onNearestX, crosshairValues } = useCrosshairs();

  const isMediumScreen = useMediaQuery(theme.responsiveBreakpoints.md);
  const tickTotalX = isMediumScreen ? 8 : 4;

  if (!isReady(ldata)) {
    return <StyledLoader />;
  }

  const rawChartData =
    ldata.value.length === 1 ? padSingleDataPoint(ldata.value) : ldata.value;
  const chartData = stepDataPoints(rawChartData);

  const axisStyle = { text: { stroke: theme.colors.greyLight } };

  return (
    <>
      <ChartWrapper>
        <FlexibleXYPlot
          xType="time"
          margin={{ left: 50 }}
          onMouseLeave={onMouseLeave}
        >
          <HorizontalGridLines style={{ stroke: '#3A3E44' }} />
          <XAxis
            hideLine
            tickSize={0}
            tickTotal={tickTotalX}
            style={axisStyle}
          />
          <YAxis
            hideLine
            tickSize={0}
            tickFormat={props.yTickFormat}
            style={axisStyle}
          />
          <LineSeries
            color={theme.colors.chartLine}
            data={chartData}
            opacity={1}
            onNearestX={onNearestX}
          />
          <AreaSeries
            color={theme.colors.bgLight}
            fill={theme.colors.bgLight}
            opacity={0.6}
            data={chartData}
          />
          <Crosshair
            values={crosshairValues}
            titleFormat={([{ x }]: ChartDataPoint[]) => {
              return {
                title: 'Date',
                value: formatDate(x, 'd LLL'),
              };
            }}
            itemsFormat={([cdp]: ChartDataPoint[]) => {
              return [
                {
                  title: 'Time',
                  value: formatDate(cdp.x, 'p'),
                },
                {
                  title: 'Value',
                  value: props.yTickFormat(cdp.y),
                },
              ];
            }}
          />
        </FlexibleXYPlot>
      </ChartWrapper>
      {ldata.value.length === 0 ? (
        <NoResults>No results for this period</NoResults>
      ) : null}
    </>
  );
}

function useCrosshairs() {
  const [crosshairValues, setCrosshairValues] = useState<ChartDataPoint[]>([]);

  const onMouseLeave = useCallback(() => {
    setCrosshairValues([]);
  }, [setCrosshairValues]);

  const onNearestX = useCallback(
    (datapoint: ChartDataPoint, _event: unknown) => {
      setCrosshairValues([datapoint]);
    },
    []
  );

  return { crosshairValues, onMouseLeave, onNearestX };
}

function padSingleDataPoint(chartData: ChartDataPoint[]): ChartDataPoint[] {
  const singleDataPoint = chartData[0];
  return [singleDataPoint, { x: Date.now(), y: singleDataPoint.y }];
}

// Add extra points so that horizontal line intervals are shown between actual
// data points.
function stepDataPoints(chartData: ChartDataPoint[]): ChartDataPoint[] {
  const result: ChartDataPoint[] = [];
  let prev: ChartDataPoint | undefined = undefined;

  for (const p of chartData) {
    if (prev) {
      result.push({ x: p.x, y: prev.y });
    }
    result.push(p);
    prev = p;
  }

  return result;
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

export function tickSeries(
  series: 'tvl' | 'apy' | 'price' | 'reservesPerShare'
): (v: number) => string {
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

export function convertHistoryPoint(p: HistoryPoint): ChartDataPoint {
  return { x: p.t.getTime(), y: p.v };
}

const ChartWrapper = styled.div`
  height: 100%;
  width: 100%;
  position: relative;
  // Fix for common resizing bug with the react-vis FlexibleXYPlot component
  // https://github.com/uber-archive/react-vis/issues/1159
  .rv-xy-plot {
    position: absolute;
    overflow: hidden;
  }
`;
const StyledLoader = styled(LoadingComponent)`
  height: 16.25rem;
  height: 100%;
  width: 100%;
`;

const NoResults = styled.div`
  display: flex;
  justify-content: center;
  position: relative;
  height: 100%;
  width: 100%;
`;
