import styled from 'styled-components';
import type { HistoricPeriod, PlatformMetrics } from '@/api/types';
import { LabelledValue, SmallSelection } from '../commons/SmallSelection';
import { Dispatch, SetStateAction } from 'react';

export type ChartDurationProps = {
  value: HistoricPeriod;
  onChange: (p: HistoricPeriod) => void;
};

export function ChartDurations(props: ChartDurationProps) {
  const { value, onChange } = props;
  const values: LabelledValue<HistoricPeriod>[] = [
    ['1D', 'day'],
    ['1W', 'week'],
    ['1M', 'month'],
    ['All', 'all'],
  ];
  return (
    <SmallSelection
      values={values}
      value={value}
      onChange={(v: HistoricPeriod) => onChange(v)}
    />
  );
}

type PriceSeries = 'price' | 'reservesPerShare';

export type ChartPriceSeriesProps = {
  receiptToken: string;
  reserveToken: string;
  value: PriceSeries;
  onChange: (p: PriceSeries) => void;
};

export function ChartPriceSeries(props: ChartPriceSeriesProps) {
  const values: LabelledValue<PriceSeries>[] = [
    [`${props.receiptToken}/USD`, 'price'],
    [`${props.receiptToken}/${props.reserveToken}`, 'reservesPerShare'],
  ];
  return (
    <SmallSelection
      values={values}
      value={props.value}
      onChange={(v: PriceSeries) => props.onChange(v)}
    />
  );
}

export type ChartPlatformMetricSeriesProps = {
  value: PlatformMetrics | undefined;
  onChange: (p: PlatformMetrics) => void;
  setWidgetExpanded?: Dispatch<SetStateAction<boolean>>;
  labelledValues: LabelledValue<PlatformMetrics>[];
};

export const ChartHeader = styled.div`
  display: flex;
  flex-direction: row-reverse;
  justify-content: space-between;
  padding-bottom: 0.5rem;
  padding-top: 0.25rem;
  margin-bottom: 0.5rem;
`;
