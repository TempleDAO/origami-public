import type {
  HistoricPeriod,
  HistoryPoint,
  Chain,
  MetricOrPrice,
} from '@/api/types';

import { useState } from 'react';
import styled, { css, keyframes } from 'styled-components';

import { Icon } from '@/components/commons/Icon';
import { LoadingText } from '@/components/commons/LoadingText';
import {
  HistoricLineChart,
  convertHistoryPoint,
  ChartDurations,
  ChartHeader,
  ChartPriceSeries,
} from '@/components/Charts';
import { AsyncButton } from '@/components/commons/Button';

import { useAsyncLoad } from '@/hooks/use-async-result';
import { useMediaQuery } from '@/hooks/use-media-query';

import {
  formatDecimalBigNumber,
  formatNumber,
  formatPercent,
} from '@/utils/formatNumber';
import { lmap, Loading } from '@/utils/loading-value';

import { theme } from '@/styles/theme';
import { textH3, textH5 } from '@/styles/mixins/text-styles';
import { tabActiveGradientStyles } from '@/styles/mixins/tab-styles';
import breakpoints from '@/styles/responsive-breakpoints';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { Tooltip } from '@/components/commons/Tooltip';
import { InvestmentInfo } from '@/components/commons/InvestmentInfo';
import { FlexRight } from '@/flows/common/components';
import { InvestmentNameAndDescription } from '@/components/commons/InvestmentNameAndDescription';

export interface InvestGridItem {
  icon: string;
  name: string;
  description: string;
  tokenPrice: Loading<DecimalBigNumber>;
  receiptToken: string;
  reserveToken: string;
  apy: Loading<number>;
  tvl: Loading<number>;
  peg?: Loading<number>;
  chain: Chain;
  info: string;
  tokenAddr: string;
  getHistory(
    period: HistoricPeriod,
    series: MetricOrPrice
  ): Promise<HistoryPoint[]>;
  onInvest?(): Promise<void>;
}

export interface InvestGridProps {
  items: InvestGridItem[];
  expanded?: number;
}

export function InvestGrid(props: InvestGridProps): JSX.Element {
  const [iexpanded, setIExpanded] = useState<number | undefined>(
    props.expanded
  );
  const [histSeries, setHistSeries] = useState<MetricOrPrice>('apy');
  const [histPeriod, setHistPeriod] = useState<HistoricPeriod>('week');

  const headings = (
    <HeadingHolder>
      <HeadingGrid>
        <Heading col={2}>APY</Heading>
        <Heading col={3}>PRICE</Heading>
        <Heading col={4}>TVL</Heading>
        <Heading col={5}>CHAIN</Heading>
      </HeadingGrid>
    </HeadingHolder>
  );

  const items = props.items.map((item: InvestGridItem, i: number) => {
    return (
      <ItemFragment
        key={item.name}
        item={item}
        isExpanded={i === iexpanded}
        onExpand={() => setIExpanded(iexpanded === i ? undefined : i)}
        histPeriod={histPeriod}
        setHistPeriod={setHistPeriod}
        histSeries={histSeries}
        setHistSeries={setHistSeries}
      />
    );
  });

  return (
    <CardColumn>
      {headings}
      {items}
    </CardColumn>
  );
}

interface ItemFragmentProps {
  item: InvestGridItem;
  isExpanded: boolean;
  onExpand: () => void;
  histPeriod: HistoricPeriod;
  setHistPeriod(p: HistoricPeriod): void;
  histSeries: MetricOrPrice;
  setHistSeries(s: MetricOrPrice): void;
}

function ItemFragment({
  item,
  isExpanded,
  onExpand,
  histPeriod,
  setHistPeriod,
  histSeries,
  setHistSeries,
}: ItemFragmentProps): JSX.Element {
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.lg);

  return (
    <Card isExpanded={isExpanded}>
      <CardContent>
        <IconNameHolder onClick={onExpand}>
          <Icon iconName={item.icon} hasBackground />
          <InvestmentNameAndDescription
            name={item.name}
            description={item.description}
            tokenExplorerUrl={item.chain.explorer.tokenUrl(item.tokenAddr)}
          />
        </IconNameHolder>
        <GridValue
          active={isExpanded && histSeries === 'apy'}
          onClick={() => {
            isExpanded || onExpand();
            setHistSeries('apy');
          }}
        >
          <LoadingText
            value={lmap(item.apy, formatPercent)}
            suffix={<SuffixSpan> % {!isDesktop && ' APY'}</SuffixSpan>}
          />
        </GridValue>
        <GridValue
          active={
            isExpanded &&
            (histSeries === 'price' || histSeries === 'reservesPerShare')
          }
          onClick={() => {
            isExpanded || onExpand();
            setHistSeries('price');
          }}
        >
          <LoadingText
            value={lmap(item.tokenPrice, formatDecimalBigNumber)}
            suffix={<SuffixSpan> USD {!isDesktop && ' PRICE'}</SuffixSpan>}
          />
        </GridValue>
        <GridValue
          active={isExpanded && histSeries === 'tvl'}
          onClick={() => {
            isExpanded || onExpand();
            setHistSeries('tvl');
          }}
        >
          <LoadingText
            value={lmap(item.tvl, formatNumber)}
            suffix={<SuffixSpan> USD {!isDesktop && ' TVL'}</SuffixSpan>}
          />
        </GridValue>
        <GridValue subdued>
          <Tooltip content={item.chain.name}>
            <ChainIconHolder>
              <Icon iconName={item.chain.iconName} />
            </ChainIconHolder>
          </Tooltip>
        </GridValue>
        {isDesktop && (
          <ButtonHolder>
            <AsyncButton
              label="DEPOSIT"
              secondary
              wide
              onClick={item.onInvest}
            />
          </ButtonHolder>
        )}
        {isExpanded && (
          <ExpandedItemFragment
            item={item}
            setHistSeries={setHistSeries}
            histSeries={histSeries}
            setHistPeriod={setHistPeriod}
            histPeriod={histPeriod}
          />
        )}
      </CardContent>
    </Card>
  );
}

interface ExpandedItemFragmentProps {
  item: InvestGridItem;
  histSeries: MetricOrPrice;
  setHistSeries(s: MetricOrPrice): void;
  setHistPeriod(s: HistoricPeriod): void;
  histPeriod: HistoricPeriod;
}

function ExpandedItemFragment({
  item,
  setHistSeries,
  histSeries,
  setHistPeriod,
  histPeriod,
}: ExpandedItemFragmentProps): JSX.Element {
  const [values] = useAsyncLoad(
    async () =>
      (await item.getHistory(histPeriod, histSeries)).map(convertHistoryPoint),
    [histPeriod, histSeries]
  );
  const isLarge = useMediaQuery(theme.responsiveBreakpoints.lg);

  return (
    <>
      <Graph>
        <ChartHeader>
          <ChartDurations value={histPeriod} onChange={setHistPeriod} />
          {(histSeries === 'price' || histSeries === 'reservesPerShare') && (
            <ChartPriceSeries
              receiptToken={item.receiptToken}
              reserveToken={item.reserveToken}
              value={histSeries}
              onChange={(v) => setHistSeries(v)}
            />
          )}
        </ChartHeader>
        <HistoricLineChart
          chartData={values}
          selectedInterval={histPeriod}
          histSeries={histSeries}
        />
      </Graph>
      <InvestmentInfoForGrid>
        <InvestmentInfo>{item.info}</InvestmentInfo>
      </InvestmentInfoForGrid>
      {!isLarge && (
        <ButtonHolder>
          <AsyncButton label="DEPOSIT" secondary wide onClick={item.onInvest} />
        </ButtonHolder>
      )}
    </>
  );
}

const InvestmentInfoForGrid = styled(FlexRight)`
  grid-column: 1 / -1;

  ${breakpoints.lg(`
    grid-column: 5 / span 3;
    margin: 0 1rem;
  `)}
`;

const expandingKeyframes = keyframes`
  0% {
    height: 0;
    transition: height 0.5s;
    overflow: hidden;
  }

  100% {
    height: 367px;
    transition: height 0.5s;
    overflow: hidden;
  }
`;

const CardColumn = styled.section`
  margin: 1rem 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
`;

const HeadingHolder = styled.div`
  display: grid;
  padding-left: 1rem;
  padding-right: 1rem;
`;

const HeadingGrid = styled.div`
  width: 100%;
  display: none;
  grid-template-columns: 6fr 1fr 1fr 1fr 1fr 2fr;
  ${breakpoints.lg(`
    display: grid;
  `)}
`;

const Heading = styled.div<{ col: number }>`
  justify-self: center;
  color: ${({ theme }) => theme.colors.greyLight};
  grid-column: ${({ col }) => col};
  display: none;
  ${breakpoints.lg(`
    display: inline-block;
  `)}
`;

const Card = styled.div<{ isExpanded: boolean }>`
  display: grid;
  padding: 1rem;
  border-radius: 2.5rem;
  background-color: ${({ theme }) => theme.colors.bgMid};
  ${sunkenStyles};

  ${({ isExpanded }) =>
    isExpanded &&
    css`
      animation: ${expandingKeyframes} 0.2s linear;
    `}
`;

const CardContent = styled.div`
  display: grid;
  row-gap: 1rem;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  ${breakpoints.lg(`
    grid-template-columns: 6fr 1fr 1fr 1fr 1fr 2fr;
  `)}
`;

const IconNameHolder = styled.div`
  cursor: pointer;
  display: flex;
  gap: 1rem;
  grid-column: 1/-1;
  ${breakpoints.lg(`
    grid-column: 1;
  `)}
`;

const GridValue = styled.div<{
  active?: boolean;
  subdued?: boolean;
}>`
  ${textH3};
  display: flex;
  align-items: center;
  justify-content: center;
  text-align: center;
  color: ${({ subdued, theme }) =>
    subdued ? theme.colors.greyLight : theme.colors.white};
  border-bottom: 0.125rem solid transparent;
  ${({ active }) => active && tabActiveGradientStyles};
  transition: 300ms ease color;
  cursor: ${({ onClick }) => onClick && 'pointer'};

  min-height: 2rem;
  ${breakpoints.lg(`
    min-height: unset;
  `)}

  &:hover {
    color: ${({ theme }) => theme.colors.greyLight};
  }
`;

const ButtonHolder = styled.div`
  box-sizing: border-box;
  height: 100%;
  display: flex;
  justify-content: center;
  align-items: center;
  width: 100%;
  grid-column: 1/-1;
  margin-bottom: 1rem;

  button {
    min-width: 100%;
  }

  ${breakpoints.lg(`
    margin-bottom: 0;
    grid-column: 6;
    button {
    min-width: initial;
  }
  `)}
`;

const Graph = styled.div`
  display: flex;
  flex-direction: column;
  align-items: stretch;
  justify-content: center;
  grid-column: 1/-1;
  div {
    margin-bottom: 0;
  }
  ${breakpoints.lg(`
    grid-column: 1/5;
  `)}
`;

export const Link = styled.a`
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms ease color;
  &:hover {
    color: ${({ theme }) => theme.colors.greyLight};
  }
  cursor: pointer;
  text-decoration-line: underline;
`;

const SuffixSpan = styled.span`
  ${textH5};
  color: ${({ theme }) => theme.colors.greyLight};
`;

const ChainIconHolder = styled.div`
  display: flex;
`;
