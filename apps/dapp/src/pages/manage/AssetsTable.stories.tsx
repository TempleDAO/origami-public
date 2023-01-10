import type { AssetHolding } from './AssetsTable';

import React from 'react';
import { action } from '@storybook/addon-actions';
import { AssetsTable } from './AssetsTable';
import { ready, loading } from '@/utils/loading-value';
import { DBN_ZERO, DBN_ONE_HUNDRED } from '@/utils/decimal-big-number';
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
    apr: 100,
    balance: DBN_ONE_HUNDRED,
    usdPrice: DBN_ZERO,
  },
  {
    investment: GMXLP,
    token: GMXLP.receiptToken,
    apr: 100,
    balance: DBN_ONE_HUNDRED,
    usdPrice: DBN_ZERO,
  },
];
