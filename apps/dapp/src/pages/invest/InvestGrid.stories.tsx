import type { HistoricPeriod, Metric, HistoryPoint } from '@/api/types';
import type { InvestGridItem } from './InvestGrid';

import { action } from '@storybook/addon-actions';

import { InvestGrid } from './InvestGrid';
import { noop } from '@/utils/noop';
import { ready } from '@/utils/loading-value';
import { arbitrum, getHistory } from '@/api/test';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

export default {
  title: 'Components/Content/InvestGrid',
  component: InvestGrid,
};

export const Default = () => <InvestGrid items={testInvestItems()} />;
export const Expanded = () => (
  <InvestGrid items={testInvestItems()} expanded={0} />
);
export const GraphLoading = () => (
  <InvestGrid items={[templeWait()]} expanded={0} />
);

function gmx(): InvestGridItem {
  return {
    icon: 'gmx',
    name: 'GMX',
    description: 'Utility token for the GMX protocol',
    apy: ready(0.121),
    tvl: ready(4860000),
    tokenPrice: ready(DecimalBigNumber.parseUnits('1.67', 2)),
    chain: arbitrum(),
    info: poolInfo('GMX'),
    receiptToken: 'ovGMX',
    reserveToken: 'oGMX',
    getHistory,
    moreInfoUrl:
      'https://arbiscan.io/token/0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
    onInvest: async () => action('onInvest gmx')(),
  };
}

function glp(): InvestGridItem {
  return {
    icon: 'glp',
    name: 'GLP',
    description: 'Liqudity token for the GMX protocol',
    apy: ready(0.067),
    tvl: ready(84800000),
    tokenPrice: ready(DecimalBigNumber.parseUnits('1.23', 2)),
    chain: arbitrum(),
    info: poolInfo('GLP'),
    receiptToken: 'ovGLP',
    reserveToken: 'oGLP',
    getHistory,
    moreInfoUrl:
      'https://arbiscan.io/token/0x4277f8f2c384827b5273592ff7cebd9f2c1ac258',
    onInvest: async () => action('onInvest glp')(),
  };
}

function testInvestItems(): InvestGridItem[] {
  return [gmx(), glp()];
}

function templeWait(): InvestGridItem {
  return { ...gmx(), getHistory: loadForever };
}

function poolInfo(s: string) {
  return `
  Info on the ${s} pool. Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book.
  `;
}

function loadForever(
  _period: HistoricPeriod,
  _series: Metric
): Promise<HistoryPoint[]> {
  return new Promise(noop);
}
