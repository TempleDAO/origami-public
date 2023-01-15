import { useState } from 'react';
import styled from 'styled-components';

import type { HistoricPeriod, Metric, HistoryPoint } from '@/api/types';

import { Icon } from '@/components/commons/Icon';
import { LoadingText } from '@/components/commons/LoadingText';
import {
  convertHistoryPoint,
  HistoricLineChart,
  tickPercent,
  tickValue,
} from '@/components/HistoricLineChart';
import { AsyncButton } from '@/components/commons/Button';

import { useAsyncLoad } from '@/hooks/use-async-result';
import { useMediaQuery } from '@/hooks/use-media-query';

import { formatNumber, formatPercent } from '@/utils/formatNumber';
import { lmap, Loading } from '@/utils/loading-value';

import { theme } from '@/styles/theme';
import { textH3, textH5, textP1 } from '@/styles/mixins/text-styles';
import { tabActiveGradientStyles } from '@/styles/mixins/tab-styles';
import breakpoints from '@/styles/responsive-breakpoints';
import sunkenStyles from '@/styles/mixins/cards/sunken';

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
    <HeadingGrid>
      <Heading col={2}>APR</Heading>
      <Heading col={3}>TVL</Heading>
      <Heading col={4}>CHAIN</Heading>
    </HeadingGrid>
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
  histSeries: Metric;
  setHistSeries(s: Metric): void;
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
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  return (
    <Card>
      <CardContent>
        <IconNameHolder onClick={onExpand}>
          <Icon iconName={item.icon} hasBackground />
          <NameHolder row={0}>
            <LPName>{item.name}</LPName>
            <LPDescription>{item.description}</LPDescription>
          </NameHolder>
        </IconNameHolder>

        <GridValue
          active={isExpanded && histSeries === 'apr'}
          onClick={() => {
            isExpanded || onExpand();
            setHistSeries('apr');
          }}
        >
          <LoadingText
            value={lmap(item.apr, formatPercent)}
            suffix={<SuffixSpan> % {!isDesktop && ' APR'}</SuffixSpan>}
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
            suffix={<SuffixSpan>{!isDesktop && '  TVL'}</SuffixSpan>}
          />
        </GridValue>
        <GridValue subdued>{item.chain.toUpperCase()}</GridValue>
        {isDesktop && (
          <ButtonHolder>
            <AsyncButton
              label="INVEST"
              secondary
              wide
              onClick={item.onInvest}
            />
          </ButtonHolder>
        )}
        {isExpanded && (
          <ExpandedItemFragment
            item={item}
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
  histSeries: Metric;
  setHistPeriod(s: HistoricPeriod): void;
  histPeriod: HistoricPeriod;
}

function ExpandedItemFragment({
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
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  return (
    <>
      <Graph>
        <HistoricLineChart
          values={values}
          histPeriod={histPeriod}
          setHistPeriod={setHistPeriod}
          yTickFormat={histSeries === 'apr' ? tickPercent : tickValue}
        />
      </Graph>
      <InfoBox>
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
      {!isDesktop && (
        <ButtonHolder>
          <AsyncButton label="INVEST" secondary wide onClick={item.onInvest} />
        </ButtonHolder>
      )}
    </>
  );
}

const CardColumn = styled.section`
  margin: 1rem 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
`;

const HeadingGrid = styled.div`
  width: 100%;
  display: none;
  grid-template-columns: 3fr 1fr 1fr 1fr 1fr;
  ${breakpoints.md(`
    display: grid;
  `)}
`;

const Heading = styled.div<{ col: number }>`
  justify-self: center;
  color: ${({ theme }) => theme.colors.greyLight};
  grid-column: ${({ col }) => col};
  display: none;
  ${breakpoints.md(`
    display: inline-block;
  `)}
`;

const Card = styled.div`
  padding: 1rem;
  border-radius: 2.5rem;
  background-color: ${({ theme }) => theme.colors.bgMid};
  ${sunkenStyles};
`;

const CardContent = styled.div`
  display: grid;
  row-gap: 1rem;
  grid-template-columns: 1fr 1fr 1fr;
  ${breakpoints.md(`
    grid-template-columns: 3fr 1fr 1fr 1fr 1fr;
  `)}
`;

const IconNameHolder = styled.div`
  cursor: pointer;
  display: flex;
  gap: 1rem;
  grid-column: 1/-1;
  ${breakpoints.md(`
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
  ${breakpoints.md(`
    min-height: unset;
  `)}

  &:hover {
    color: ${({ theme }) => theme.colors.greyLight};
  }
`;

const LPName = styled.div`
  ${textH3}
  color: ${({ theme }) => theme.colors.white};
  transition: 300ms color ease;
`;

const NameHolder = styled.div<{ row: number }>`
  display: flex;
  flex-direction: column;
  &:hover {
    ${LPName} {
      color: ${({ theme }) => theme.colors.greyLight};
    }
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

  ${breakpoints.md(`
    margin-bottom: 0;
    grid-column: 5;
    button {
    min-width: initial;
  }
  `)}
`;

const LPDescription = styled.div`
  ${textP1}
  color: ${({ theme }) => theme.colors.greyLight};
`;

const Graph = styled.div`
  height: 18.75rem;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: center;
  grid-column: 1/-1;
  div {
    margin-bottom: 0;
  }
  ${breakpoints.md(`
    grid-column: 1/4;
  `)}
`;

export const InfoBox = styled.div`
  color: ${({ theme }) => theme.colors.greyLight};
  align-self: stretch;
  margin: 0;

  p {
    margin: 0;
  }
  grid-column: 1/-1;
  ${breakpoints.md(`
      grid-column: 4 / span 2;
      margin: 0 1rem;
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
