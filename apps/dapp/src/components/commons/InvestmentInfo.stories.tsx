import React from 'react';

import { InvestmentInfo } from './InvestmentInfo';

export default {
  title: 'Components/Commons/InvestmentInfo',
  component: InvestmentInfo,
};

const info = `
# Heading l1
## Heading l2
Investors deposit GMX and are issued shares in the ovGMX vault.
\n
The price of ovGMX increases as rewards from staked GMX are harvested and auto-compounded.
\n
Yield is further boosted from staking derived esGMX and multiplier point rewards.
\n
[More info](https://www.google.com)
`;

export const WithMarkdown = () => <InvestmentInfo>{info}</InvestmentInfo>;
