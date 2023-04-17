import type { DataKey, AxisDomain } from 'recharts/types/util/types';

import React from 'react';
import { useTheme } from 'styled-components';
import {
  ResponsiveContainer,
  LineChart as RechartsLineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  CartesianGrid,
} from 'recharts';

type LineChartProps<T> = {
  chartData: T[];
  xDataKey: DataKey<keyof T>;
  lines: { series: DataKey<keyof T>; color: string }[];
  xTickFormatter?: (xValue: number, index: number) => string;
  yTickFormatter?: (xValue: number, index: number) => string;
  tooltipLabelFormatter?: (value: number) => string;
  tooltipValuesFormatter?: (value: number, name: string) => string[];
  legendFormatter?: (value: string) => string;
  yDomain?: AxisDomain;
};

export default function LineChart<T>(
  props: React.PropsWithChildren<LineChartProps<T>>
) {
  const {
    chartData,
    xDataKey,
    lines,
    xTickFormatter,
    yTickFormatter,
    tooltipLabelFormatter,
    tooltipValuesFormatter,
    legendFormatter,
    yDomain,
  } = props;

  const theme = useTheme();
  return (
    <ResponsiveContainer minHeight={150} minWidth={320} height={250}>
      <RechartsLineChart data={chartData}>
        <CartesianGrid vertical={false} stroke={theme.colors.greyDark} />
        {lines.map((line) => (
          <Line
            key={line.series.toString()}
            type="stepAfter"
            dataKey={line.series}
            stroke={line.color}
            strokeWidth={2}
            dot={false}
            isAnimationActive={false}
          />
        ))}
        <XAxis
          dataKey={xDataKey}
          tickFormatter={xTickFormatter}
          tick={{ stroke: theme.colors.greyLight }}
          fontSize={11}
          interval={'preserveEnd'}
          minTickGap={20}
          tickMargin={10}
          stroke="none"
        />
        <YAxis
          tickFormatter={yTickFormatter}
          tick={{ stroke: theme.colors.greyLight }}
          fontSize={11}
          interval="preserveEnd"
          domain={yDomain}
          tickMargin={10}
          stroke="none"
        />
        <Tooltip
          wrapperStyle={{ outline: 'none' }}
          contentStyle={{
            backgroundColor: theme.colors.greyDark,
            color: theme.colors.chartLine,
            borderRadius: '15px',
            border: 0,
          }}
          itemStyle={{
            backgroundColor: theme.colors.greyDark,
            color: theme.colors.white,
            fontSize: 11,
          }}
          labelStyle={{
            backgroundColor: theme.colors.greyDark,
            fontWeight: 'bold',
            fontSize: 11,
          }}
          labelFormatter={tooltipLabelFormatter}
          formatter={
            tooltipValuesFormatter
              ? (value, name, _props) => {
                  return tooltipValuesFormatter(
                    value as number,
                    name as string
                  );
                }
              : undefined
          }
        />
        {lines.length > 0 && legendFormatter && (
          <Legend verticalAlign="top" height={20} formatter={legendFormatter} />
        )}
      </RechartsLineChart>
    </ResponsiveContainer>
  );
}
