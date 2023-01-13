import type { FC } from 'react';
import type { Token, Investment } from '@/api/types';
import { lmap, Loading } from '@/utils/loading-value';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { Text } from '@/components/commons/Text';
import { LoadingText } from '@/components/commons/LoadingText';
import { LoadingComponent } from '@/components/commons/LoadingComponent';
import { isReady, loading } from '@/utils/loading-value';
import { formatDecimalBigNumber, formatPercent } from '@/utils/formatNumber';
import { textH3 } from '@/styles/mixins/text-styles';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { MetricsResp } from '@/api/api';

export type AssetHolding = {
  investment: Investment;
  token: Token;
  balance: DecimalBigNumber;
  metrics: Loading<MetricsResp>;
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
      holdings.value.map((holding) => (
        <AssetsTableRow
          key={holding.token.symbol}
          holding={holding}
          handleSelect={handleSelect}
        />
      ))
    ) : (
      <>
        <EmptyAssetsTableRow />
        <EmptyAssetsTableRow />
      </>
    )}
  </Table>
);

type AssetsTableRowProps = {
  holding: AssetHolding;
  handleSelect: (investment: Investment) => void;
};

const AssetsTableRow: FC<AssetsTableRowProps> = ({ holding, handleSelect }) => {
  const { investment, token, balance } = holding;
  return (
    <AssetRow onClick={() => handleSelect(investment)}>
      <Item0 col={1}>
        <AssetInfo>
          <Icon iconName={token.iconName} size={ICON_SIZE} hasBackground />
          <VerticalFlex>
            <Primary>{investment.receiptToken.symbol}</Primary>
            <Subtext>{investment.description}</Subtext>
          </VerticalFlex>
        </AssetInfo>
      </Item0>
      <Item col={2}>
        <ValueContainer>
          <Primary>
            <LoadingText
              value={lmap(holding.metrics, (metrics) =>
                formatPercent(metrics.apr)
              )}
            />
          </Primary>
          <Secondary>%</Secondary>
        </ValueContainer>
      </Item>
      <Item col={3}>
        <Secondary>{investment.chain.name}</Secondary>
      </Item>
      <Item col={4}>
        <ValueContainer>
          <Primary>{formatDecimalBigNumber(balance)}</Primary>
        </ValueContainer>
      </Item>
    </AssetRow>
  );
};

const EmptyAssetsTableRow = () => {
  return (
    <AssetRow>
      <Item0 col={1}>
        <AssetInfo>
          <LoadingIcon width={50} height={50} />
          <VerticalFlex>
            <Primary>
              <LoadingText value={loading()} />
            </Primary>
            <Subtext>
              <LoadingText value={loading()} />
            </Subtext>
          </VerticalFlex>
        </AssetInfo>
      </Item0>
      <Item col={2}>
        <ValueContainer>
          <Primary>
            <LoadingText value={loading()} />
          </Primary>
          <Secondary>%</Secondary>
        </ValueContainer>
      </Item>
      <Item col={3}>
        <Secondary>
          <LoadingText value={loading()} />
        </Secondary>
      </Item>
      <Item col={4}>
        <ValueContainer>
          <Primary>
            <LoadingText value={loading()} />
          </Primary>
        </ValueContainer>
      </Item>
    </AssetRow>
  );
};

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
