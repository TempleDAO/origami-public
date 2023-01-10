import type { FC } from 'react';
import type { Token, Investment } from '@/api/types';
import type { Loading } from '@/utils/loading-value';
import { DBN_ZERO, DecimalBigNumber } from '@/utils/decimal-big-number';

import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { Text } from '@/components/commons/Text';
import { LoadingText } from '@/components/commons/LoadingText';
import { LoadingComponent } from '@/components/commons/LoadingComponent';
import { isReady, lmap, ready, loading } from '@/utils/loading-value';
import { formatDecimalBigNumber, formatPercent } from '@/utils/formatNumber';
import { noop } from '@/utils/noop';
import { textH3 } from '@/styles/mixins/text-styles';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { ProviderApi } from '@/api/api';

export type AssetHolding = {
  investment: Investment;
  token: Token;
  usdPrice: DecimalBigNumber;
  apr: number;
  balance: DecimalBigNumber;
};

type AssetHoldingsProps = {
  assetHoldings: Loading<AssetHolding>;
  handleSelect: (investment: Investment) => void;
};

type AssetsTableProps = {
  holdings: Loading<AssetHolding[]>;
  handleSelect: (investment: Investment) => void;
};

const ICON_SIZE = 26;

export const AssetsTable: FC<AssetsTableProps> = ({
  holdings,
  handleSelect,
}) => (
  <Table>
    <Row css="">
      <Item col={2}>
        <Subtext>APR</Subtext>
      </Item>
      <Item col={3}>
        <Subtext>CHAIN</Subtext>
      </Item>
      <Item col={4}>
        <Subtext>BALANCE</Subtext>
      </Item>
    </Row>
    {isReady(holdings) ? (
      holdings.value.map((assetHoldings) => (
        <AssetHoldings
          key={assetHoldings.token.symbol}
          assetHoldings={ready(assetHoldings)}
          handleSelect={handleSelect}
        />
      ))
    ) : (
      <>
        <AssetHoldings
          assetHoldings={loading<AssetHolding>()}
          handleSelect={noop}
        />
        <AssetHoldings
          assetHoldings={loading<AssetHolding>()}
          handleSelect={noop}
        />
      </>
    )}
  </Table>
);

const AssetHoldings: FC<AssetHoldingsProps> = ({
  assetHoldings,
  handleSelect,
}) => {
  const { pool, token, title, subtitle, apr, chain, balance } =
    extractHoldingsValues(assetHoldings);

  const handleClick = isReady(pool) ? () => handleSelect(pool.value) : noop;

  return (
    <AssetRow onClick={handleClick}>
      <Item0 col={1}>
        <AssetInfo>
          {isReady(token) ? (
            <Icon
              iconName={token.value.iconName}
              size={ICON_SIZE}
              hasBackground
            />
          ) : (
            <LoadingIcon width={50} height={50} />
          )}
          <VerticalFlex>
            <Primary>
              <LoadingText value={title} />
            </Primary>
            <Subtext>
              <LoadingText value={subtitle} />
            </Subtext>
          </VerticalFlex>
        </AssetInfo>
      </Item0>
      <Item col={2}>
        <ValueContainer>
          <Primary>
            <LoadingText value={apr} />
          </Primary>
          <Secondary>%</Secondary>
        </ValueContainer>
      </Item>
      <Item col={3}>
        <Secondary>
          <LoadingText value={chain} />
        </Secondary>
      </Item>
      <Item col={4}>
        <ValueContainer>
          <Primary>
            <LoadingText value={balance} />
          </Primary>
        </ValueContainer>
      </Item>
    </AssetRow>
  );
};

function extractHoldingsValues(holdings: Loading<AssetHolding>) {
  const pool = lmap(holdings, (holdings) => holdings.investment);
  const token = lmap(holdings, (holdings) => holdings.token);
  const title = lmap(
    holdings,
    (holdings) => holdings.investment.receiptToken.symbol
  );
  const subtitle = lmap(
    holdings,
    (holdings) => holdings.investment.description
  );
  const apr = lmap(holdings, (holdings) => formatPercent(holdings.apr));
  const chain = lmap(holdings, (holdings) =>
    holdings.investment.chain.name.toUpperCase()
  );
  const balance = lmap(holdings, (holdings) =>
    formatDecimalBigNumber(holdings.balance)
  );

  return {
    pool,
    token,
    title,
    subtitle,
    apr,
    chain,
    balance,
  };
}

export async function loadAssetHoldings(
  signerAddress: string,
  papi: ProviderApi
): Promise<AssetHolding[]> {
  const result: AssetHolding[] = [];
  for (const ic of papi.investments) {
    const investment = await papi.getInvestment(ic);
    const token = investment.receiptToken;
    const balance = await papi.getTokenBalance(token, signerAddress);
    if (balance.gt(DBN_ZERO)) {
      const [metrics, usdPrice] = await Promise.all([
        await investment.getMetrics(),
        await papi.getTokenUsdPrice(investment.receiptToken),
      ]);
      result.push({
        investment,
        token,
        balance: balance,
        apr: metrics.apr,
        usdPrice: usdPrice,
      });
    }
  }
  return result;
}

const VerticalFlex = styled.div`
  display: flex;
  flex-direction: column;
`;

const Table = styled(VerticalFlex)`
  gap: 0.625rem;
  margin-bottom: 2rem;
`;

const Row = styled.div`
  padding-right: 0.9375rem;
  display: grid;
  grid-template-columns: 5.5fr 1fr 1fr 1fr 1fr;
`;

const Item = styled.div<{ col: number }>`
  align-self: center;
  justify-self: center;
  ${({ col }) => `
    grid-column-start: ${col};
    grid-column-end: ${col + 1};
 `}
`;

const Item0 = styled.div<{ col: number }>`
  align-self: center;
  justify-self: start;
  ${({ col }) => `
    grid-column-start: ${col};
    grid-column-end: ${col + 1};
 `}
`;

const Primary = styled.span`
  ${textH3}
`;

const Secondary = styled.span`
  color: ${({ theme }) => theme.colors.greyLight};
`;

const Subtext = styled(Text)`
  margin: 0;
  color: ${({ theme }) => theme.colors.greyLight};
  width: fit-content;
`;

const AssetRow = styled(Row)`
  ${sunkenStyles}
  padding: 0.7rem 0.9375rem;
  border-radius: 2.5rem;
  background: ${({ theme }) =>
    `linear-gradient(to right, ${theme.colors.bgMid} 0%, ${theme.colors.bgMid} 79%,${theme.colors.bgDark} 79%,${theme.colors.bgDark} 100%)`};

  cursor: pointer;

  * {
    cursor: pointer;
    user-select: none;
  }
`;

const AssetInfo = styled.div`
  display: flex;
  align-items: center;
  gap: 1.25rem;
`;

const ValueContainer = styled.div`
  display: flex;
  align-items: center;
  gap: 0.3125rem;
`;

const LoadingIcon = styled(LoadingComponent)`
  border-radius: 99999px;
`;
