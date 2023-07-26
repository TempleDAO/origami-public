import type { AssetHolding } from './AssetsTable';

import React from 'react';
import { action } from '@storybook/addon-actions';
import { AssetsTable } from './AssetsTable';
import { ready, loading, newLoading } from '@/utils/loading-value';
import { DBN_ONE_HUNDRED, DecimalBigNumber } from '@/utils/decimal-big-number';
import { gmxInvestment, glpInvestment } from '@/api/test';

export default {
  title: 'Components/Content/AssetsTable',
  component: AssetsTable,
};

export const Default = () => (
  <AssetsTable
    holdings={ready(mockHoldings)}
    handleSelect={(investment) =>
      action(`selected ${investment.receiptToken.symbol}`)
    }
  />
);

export const Loading = () => (
  <AssetsTable
    holdings={loading()}
    handleSelect={(investment) =>
      action(`selected ${investment.receiptToken.symbol}`)
    }
  />
);

const GMX = gmxInvestment();
const GMXLP = glpInvestment();

const mockHoldings: AssetHolding[] = [
  {
    investment: GMX,
    token: GMX.receiptToken,
    balance: DBN_ONE_HUNDRED,
    metrics: newLoading({
      apy: 0.25,
      tvl: 1000000,
    }),
    price: newLoading(DecimalBigNumber.parseUnits('44.22', 2)),
  },
  {
    investment: GMXLP,
    token: GMXLP.receiptToken,
    balance: DBN_ONE_HUNDRED,
    metrics: newLoading({
      apy: 0.27,
      tvl: 2000000,
    }),
    price: newLoading(DecimalBigNumber.parseUnits('1.12', 2)),
  },
];
