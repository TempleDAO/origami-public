import type { FC } from 'react';
import type { Token, Investment } from '@/api/types';
import { lmap, Loading } from '@/utils/loading-value';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

import styled, { css } from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { Text } from '@/components/commons/Text';
import { LoadingText } from '@/components/commons/LoadingText';
import { LoadingComponent } from '@/components/commons/LoadingComponent';
import { isReady, loading } from '@/utils/loading-value';
import { formatDecimalBigNumber, formatPercent } from '@/utils/formatNumber';
import { textH3, textH5 } from '@/styles/mixins/text-styles';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { MetricsResp } from '@/api/api';
import breakpoints from '@/styles/responsive-breakpoints';
import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';
import { InvestmentNameAndDescription } from '@/components/commons/InvestmentNameAndDescription';
import { ApyTooltip } from '@/components/commons/ApyTooltip';

export type AssetHolding = {
  investment: Investment;
  token: Token;
  balance: DecimalBigNumber;
  metrics: Loading<MetricsResp>;
  price: Loading<DecimalBigNumber>;
};

type AssetsTableProps = {
  holdings: Loading<AssetHolding[]>;
  handleSelect: (investment: Investment) => void;
};

const ICON_SIZE = 26;

export const AssetsTable: FC<AssetsTableProps> = ({
  holdings,
  handleSelect,
}) => {
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);
  return (
    <Table>
      {isDesktop && (
        <Row css="">
          <Item col={1}></Item>
          <ApyTooltip>
            <Item col={2}>
              <Subtext>APY</Subtext>
            </Item>
          </ApyTooltip>
          <Item col={3}>
            <Subtext>PRICE</Subtext>
          </Item>
          <Item col={4}>
            <Subtext>CHAIN</Subtext>
          </Item>
          <Item col={5}>
            <Subtext>BALANCE</Subtext>
          </Item>
        </Row>
      )}
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
};

type AssetsTableRowProps = {
  holding: AssetHolding;
  handleSelect: (investment: Investment) => void;
};

const AssetsTableRow: FC<AssetsTableRowProps> = ({ holding, handleSelect }) => {
  const { investment, token, balance } = holding;
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);
  return (
    <AssetRow onClick={() => handleSelect(investment)}>
      <Item0 col={1}>
        <AssetInfo>
          <Icon iconName={token.iconName} size={ICON_SIZE} hasBackground />
          <InvestmentNameAndDescription
            name={investment.receiptToken.symbol}
            description={investment.description}
            tokenExplorerUrl={investment.chain.explorer.tokenUrl(
              investment.contractAddress.address
            )}
          />
        </AssetInfo>
      </Item0>
      <Item col={2}>
        <ApyTooltip>
          <ValueContainer>
            <Primary>
              <LoadingText
                value={lmap(holding.metrics, (metrics) =>
                  formatPercent(metrics.apy)
                )}
                suffix={<ValueSuffix> % {!isDesktop && ' APY'}</ValueSuffix>}
              />
            </Primary>
          </ValueContainer>
        </ApyTooltip>
      </Item>
      <Item col={3}>
        <ValueContainer>
          <LoadingText
            value={lmap(holding.price, (price) =>
              formatDecimalBigNumber(price)
            )}
            suffix={<ValueSuffix> USD {!isDesktop && ' PRICE'}</ValueSuffix>}
          />
        </ValueContainer>
      </Item>
      <Item col={4}>
        <Icon iconName={investment.chain.iconName} size={ICON_SIZE} />
      </Item>
      <Balance col={5}>
        <ValueContainer>
          {!isDesktop && <ValueSuffix>YOUR BALANCE: </ValueSuffix>}
          <Primary>{formatDecimalBigNumber(balance)}</Primary>
        </ValueContainer>
      </Balance>
    </AssetRow>
  );
};

const EmptyAssetsTableRow = () => {
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  return (
    <AssetRow>
      <Item0 col={1}>
        <AssetInfo>
          <LoadingIcon width={ICON_SIZE * 2} height={ICON_SIZE * 2} />
          <VerticalFlex>
            <Primary>
              <LoadingText value={loading()} />
            </Primary>
            <Subtext>
              <LoadingText value={loading()} />
            </Subtext>
            {!isDesktop && <EmptySpace />}
          </VerticalFlex>
        </AssetInfo>
      </Item0>
      <Item col={2}>
        <ValueContainer>
          <Primary>
            <LoadingText
              value={loading()}
              suffix={<ValueSuffix>{' %'}</ValueSuffix>}
            />
          </Primary>
        </ValueContainer>
      </Item>
      <Item col={3}>
        <ValueContainer>
          <Primary>
            <LoadingText value={loading()} />
          </Primary>
        </ValueContainer>
      </Item>
      <Item col={4}>
        <Secondary>
          <LoadingIcon width={ICON_SIZE * 2} height={ICON_SIZE * 2} />
        </Secondary>
      </Item>
      <Balance col={5}>
        <ValueContainer>
          <Primary>
            <LoadingText value={loading()} />
          </Primary>
        </ValueContainer>
      </Balance>
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

const Primary = styled.span`
  transition: 300ms ease color;
  ${textH3}
`;

const Row = styled.div`
  padding: 0.7rem 0.9375rem;
  display: grid;
  grid-template-columns: 1fr 1fr;
  &:hover {
    ${Primary} {
      color: ${({ theme }) => theme.colors.greyLight};
    }
  }

  ${breakpoints.md(`
      grid-template-columns: 4.5fr 1fr 1fr 1fr 1fr;

  `)}
`;

const Item = styled.div<{ col: number }>`
  text-align: center;
  align-self: center;
  ${({ col }) => css`
    grid-row: 2;
    grid-column: ${col - 1};
    margin: 0.5rem;
    justify-self: flex-start;

    ${breakpoints.md(`
      justify-self: center;
      grid-row: 1;
      grid-column: ${col};
      margin: 0;
    `)}
  `};
`;

const Item0 = styled.div<{ col: number }>`
  align-self: center;
  justify-self: start;
  grid-column: 1/-1;
  ${breakpoints.md(`
    grid-column: 1;
  `)}
`;

const Balance = styled(Item)<{ col: number }>`
  grid-row: 3;
  grid-column: 1/-1;
  ${({ col }) => css`
    ${breakpoints.md(`
    grid-row: 1;
    grid-column: ${col};
  `)}
  `}
`;

const Secondary = styled.span`
  ${textH3};
  color: ${({ theme }) => theme.colors.greyLight};
`;

const Subtext = styled(Text)`
  margin: 0;
  color: ${({ theme }) => theme.colors.greyLight};
  width: fit-content;
`;

const AssetRow = styled(Row)`
  ${sunkenStyles}
  border-radius: 2.5rem;
  ${({ theme }) => css`
    background: ${theme.colors.bgMid};
    ${breakpoints.md(`
    background: linear-gradient(to right, ${theme.colors.bgMid} 0%, ${theme.colors.bgMid} 88%,${theme.colors.bgDark} 88%,${theme.colors.bgDark} 100%)};
  `)}
  `}

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
  ${textH3};
  align-items: center;
  gap: 0.3125rem;
`;

const LoadingIcon = styled(LoadingComponent)`
  border-radius: 99999px;
`;

const ValueSuffix = styled.span`
  ${textH5};
  color: ${({ theme }) => theme.colors.greyLight};
`;

const EmptySpace = styled.div`
  padding: 0.7rem;
`;
