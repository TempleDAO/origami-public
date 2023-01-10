import type { HistoricPeriod, Metric, HistoryPoint } from '@/api/types';

import { Fragment, useState } from 'react';
import styled, { css } from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { LoadingText } from '@/components/commons/LoadingText';
import {
  convertHistoryPoint,
  HistoricLineChart,
  tickPercent,
  tickValue,
} from '@/components/HistoricLineChart';
import { textH3, textH5, textP1 } from '@/styles/mixins/text-styles';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { formatNumber, formatPercent } from '@/utils/formatNumber';
import { lmap, Loading } from '@/utils/loading-value';
import { AsyncButton } from '@/components/commons/Button';
import { tabActiveGradientStyles } from '@/styles/mixins/tab-styles';

export interface InvestGridItem {
  icon: string;
  name: string;
  description: string;
  apr: Loading<number>;
  tvl: Loading<number>;
  peg?: Loading<number>;
  chain: string;
  info: string;
  moreInfoUrl?: string;
  getHistory(period: HistoricPeriod, series: Metric): Promise<HistoryPoint[]>;
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
  const [histSeries, setHistSeries] = useState<Metric>('apr');
  const [histPeriod, setHistPeriod] = useState<HistoricPeriod>('day');

  const headings = (
    <Fragment key="headings">
      <Heading col={3}>APR</Heading>
      <Heading col={4}>TVL</Heading>
      <Heading col={5}>CHAIN</Heading>
    </Fragment>
  );

  const items = props.items.map((item: InvestGridItem, i: number) => {
    const row = i * 2 + 2;
    const expanded = i == iexpanded;
    return (
      <Fragment key={item.name}>
        <PoolInset row={row} />
        <ItemFragment
          row={row}
          item={item}
          expanded={expanded}
          histSeries={histSeries}
          setHistSeries={setHistSeries}
          onClick={() => setIExpanded(expanded ? undefined : i)}
        />
        {expanded && (
          <ExpandedItemFragment
            row={row}
            item={item}
            histSeries={histSeries}
            histPeriod={histPeriod}
            setHistPeriod={setHistPeriod}
          />
        )}
      </Fragment>
    );
  });

  return (
    <StyledGrid>
      {headings}
      {items}
    </StyledGrid>
  );
}

interface ItemFragmentProps {
  row: number;
  item: InvestGridItem;
  expanded: boolean;
  histSeries: Metric;
  setHistSeries(s: Metric): void;
  onClick(): void;
}

function ItemFragment({
  row,
  item,
  expanded,
  histSeries,
  setHistSeries,
  onClick,
}: ItemFragmentProps): JSX.Element {
  return (
    <Fragment>
      <IconHolder row={row} onClick={onClick}>
        <Icon iconName={item.icon} hasBackground />
      </IconHolder>
      <NameHolder row={row} onClick={onClick}>
        <LPName>{item.name}</LPName>
        <LPDescription>{item.description}</LPDescription>
      </NameHolder>
      <GridValue
        active={expanded && histSeries === 'apr'}
        row={row}
        col={3}
        onClick={() => {
          expanded || onClick();
          setHistSeries('apr');
        }}
      >
        <LoadingText
          value={lmap(item.apr, formatPercent)}
          suffix={<SuffixSpan> %</SuffixSpan>}
        />
      </GridValue>
      <GridValue
        active={expanded && histSeries === 'tvl'}
        row={row}
        col={4}
        onClick={() => {
          expanded || onClick();
          setHistSeries('tvl');
        }}
      >
        <LoadingText value={lmap(item.tvl, formatNumber)} />
      </GridValue>
      <GridValue row={row} col={5} subdued>
        {item.chain.toUpperCase()}
      </GridValue>
      <ButtonHolder row={row}>
        <AsyncButton label="INVEST" secondary wide onClick={item.onInvest} />
      </ButtonHolder>
    </Fragment>
  );
}

interface ExpandedItemFragmentProps {
  row: number;
  item: InvestGridItem;
  histSeries: Metric;
  setHistPeriod(s: HistoricPeriod): void;
  histPeriod: HistoricPeriod;
}

function ExpandedItemFragment({
  row,
  item,
  histSeries,
  setHistPeriod,
  histPeriod,
}: ExpandedItemFragmentProps): JSX.Element {
  const [values] = useAsyncLoad(
    async () =>
      (await item.getHistory(histPeriod, histSeries)).map(convertHistoryPoint),
    [histPeriod, histSeries]
  );

  const result = (
    <Fragment>
      <Graph row={row + 1}>
        <HistoricLineChart
          values={values}
          histPeriod={histPeriod}
          setHistPeriod={setHistPeriod}
          yTickFormat={histSeries === 'apr' ? tickPercent : tickValue}
        />
      </Graph>
      <InfoBox row={row + 1}>
        <p>{item.info}</p>
        {item.moreInfoUrl && (
          <p>
            <Link
              href={item.moreInfoUrl}
              target="_blank"
              rel="noopener noreferrer"
            >
              More info
            </Link>
          </p>
        )}
      </InfoBox>
    </Fragment>
  );
  return result;
}
const IconHolder = styled.div<{ row: number }>`
  cursor: pointer;
  grid-row: ${(props) => props.row};
  grid-column: 1;
  margin: 1rem 1rem 0.5rem;
`;

const ButtonHolder = styled.div<{ row: number }>`
  box-sizing: border-box;
  height: 100%;
  display: flex;
  justify-content: center;
  align-items: center;
  grid-row: ${(props) => props.row};
  grid-column: 6;
  padding: 1rem 1.5rem 0.5rem;
`;

const LPName = styled.div`
  ${textH3}
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms color ease;
`;

const NameHolder = styled.div<{ row: number }>`
  cursor: pointer;
  grid-row: ${(props) => props.row};
  grid-column: 2;
  padding: 1rem 0 0.5rem;
  &:hover {
    ${LPName} {
      color: ${({ theme }) => theme.colors.greyLight};
    }
  }
`;

const StyledGrid = styled.div`
  display: grid;
  grid-template-columns: 0.3fr 3fr 1fr 1fr 1fr 1fr;
  grid-template-rows: auto;
  align-items: center;
  row-gap: 0.5rem;
  background-color: ${({ theme }) => theme.colors.bgLight};
  margin: 2rem 0;
`;

const Heading = styled.div<{ col: number }>`
  justify-self: center;
  color: ${({ theme }) => theme.colors.greyLight};
  grid-row: 1;
  grid-column: ${(props) => props.col};
`;

const GridValue = styled.div<{
  row: number;
  col: number;
  active?: boolean;
  subdued?: boolean;
}>`
  box-sizing: border-box;
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 1rem 0 0.5rem;
  grid-row: ${(props) => props.row};
  grid-column: ${(props) => props.col};
  color: ${({ theme }) => theme.colors.white};
  border-bottom: 0.125rem solid transparent;
  ${textH3}
  border-bottom-width: 0.125rem;
  transition: 300ms ease color;

  &:hover {
    color: ${({ theme }) => theme.colors.greyLight};
  }

  ${(props) => props.active && tabActiveGradientStyles};

  ${(props) =>
    props.onClick &&
    css`
      cursor: pointer;
    `}
  ${({ subdued, theme }) =>
    subdued &&
    css`
      color: ${theme.colors.greyLight};
    `}
`;

const LPDescription = styled.div`
  ${textP1}
  color: ${({ theme }) => theme.colors.greyLight};
`;

const Graph = styled.div<{ row: number }>`
  height: 300px;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: center;
  grid-row: ${(props) => props.row};
  grid-column: 1 / 5;
`;

export const InfoBox = styled.div<{ row: number }>`
  color: ${({ theme }) => theme.colors.greyLight};
  align-self: stretch;
  grid-row: ${(props) => props.row};
  grid-column: 5 / span 2;
  margin: 0 15px;
`;

const PoolInset = styled.div<{ row: number }>`
  color: black;
  border-radius: 2.5rem;
  background-color: ${({ theme }) => theme.colors.bgMid};
  box-shadow: inset 1px 3px 5px rgba(0, 0, 0, 0.2);
  grid-row: ${(props) => props.row} / span 2;
  grid-column: 1 / -1;
  align-self: stretch;
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
