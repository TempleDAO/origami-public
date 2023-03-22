import styled from 'styled-components';
import type { HistoricPeriod } from '@/api/types';
import { LabelledValue, SmallSelection } from './commons/SmallSelection';

export type ChartDurationProps = {
  value: HistoricPeriod;
  onChange: (p: HistoricPeriod) => void;
};

export function ChartDurations(props: ChartDurationProps) {
  const values: LabelledValue<HistoricPeriod>[] = [
    ['1D', 'day'],
    ['1W', 'week'],
    ['1M', 'month'],
    ['All', 'all'],
  ];
  return (
    <SmallSelection
      values={values}
      value={props.value}
      onChange={(v: HistoricPeriod) => props.onChange(v)}
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

export const ChartFooter = styled.div`
  display: flex;
  flex-direction: row-reverse;
  justify-content: space-between;
`;
