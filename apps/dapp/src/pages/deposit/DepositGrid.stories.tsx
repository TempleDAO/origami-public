import type { HistoricPeriod, Metric, HistoryPoint } from '@/api/types';
import type { DepositGridItem } from './DepositGrid';

import { action } from '@storybook/addon-actions';

import { DepositGrid } from './DepositGrid';
import { noop } from '@/utils/noop';
import { ready } from '@/utils/loading-value';
import { arbitrum, getHistory } from '@/api/test';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

export default {
  title: 'Components/Content/DepositGrid',
  component: DepositGrid,
};

export const Default = () => (
  <DepositGrid
    items={testInvestItems()}
    vaultExpanded={0}
    setVaultExpanded={action('set IExpand')}
    platformMetricsExpanded={false}
    setPlatformMetricsExpanded={action('setPlatformMetricsExpanded')}
  />
);
export const Expanded = () => (
  <DepositGrid
    items={testInvestItems()}
    vaultExpanded={0}
    setVaultExpanded={action('set IExpand')}
    platformMetricsExpanded={false}
    setPlatformMetricsExpanded={action('setPlatformMetricsExpanded')}
  />
);
export const GraphLoading = () => (
  <DepositGrid
    items={[templeWait()]}
    vaultExpanded={0}
    setVaultExpanded={action('set IExpand')}
    platformMetricsExpanded={false}
    setPlatformMetricsExpanded={action('setPlatformMetricsExpanded')}
  />
);

function gmx(): DepositGridItem {
  return {
    icon: 'gmx',
    name: 'GMX',
    description: 'Utility token for the GMX protocol',
    apy: ready(0.121),
    tvl: ready(4860000),
    tokenPrice: ready(DecimalBigNumber.parseUnits('1.67', 2)),
    chain: arbitrum(),
    info: poolInfo('GMX'),
    tokenAddr: '0xovGMX',
    receiptToken: 'ovGMX',
    reserveToken: 'oGMX',
    getHistory,
    onInvest: async () => action('onInvest gmx')(),
  };
}

function glp(): DepositGridItem {
  return {
    icon: 'glp',
    name: 'GLP',
    description: 'Liqudity token for the GMX protocol',
    apy: ready(0.067),
    tvl: ready(84800000),
    tokenPrice: ready(DecimalBigNumber.parseUnits('1.23', 2)),
    chain: arbitrum(),
    info: poolInfo('GLP'),
    tokenAddr: '0xovGLP',
    receiptToken: 'ovGLP',
    reserveToken: 'oGLP',
    getHistory,
    onInvest: async () => action('onInvest glp')(),
  };
}

function testInvestItems(): DepositGridItem[] {
  return [gmx(), glp()];
}

function templeWait(): DepositGridItem {
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
