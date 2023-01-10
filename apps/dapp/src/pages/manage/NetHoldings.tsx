import type { FC, MouseEventHandler } from 'react';
import type { HistoricPeriod, HistoryPoint } from '@/api/types';
import type { Loading } from '@/utils/loading-value';

import styled from 'styled-components';
import { LoadingText } from '@/components/commons/LoadingText';
import { lmap } from '@/utils/loading-value';
import { formatNumber, formatPercent } from '@/utils/formatNumber';
import { textH2, textH3 } from '@/styles/mixins/text-styles';
import { noop } from '@/utils/noop';

type NetHoldings = {
  currentNetApr: Loading<number>;
  currentNetValue: Loading<number>;
};

export type FetchHistoryCb = (
  period: HistoricPeriod
) => Promise<HistoryPoint[]>;

export const NetHoldings: FC<NetHoldings> = ({
  currentNetApr,
  currentNetValue,
}) => {
  return (
    <VerticalFlex>
      <Heading
        currentNetApr={currentNetApr}
        currentNetValue={currentNetValue}
      />
    </VerticalFlex>
  );
};

const Heading: FC<{
  currentNetApr: Loading<number>;
  currentNetValue: Loading<number>;
}> = ({ currentNetApr, currentNetValue }) => {
  return (
    <HeadingContainer>
      <Title>YOUR NET HOLDINGS</Title>
      <TogglerRow>
        <SeriesToggler
          active={false}
          onClick={noop}
          text={'NET APR'}
          value={lmap(currentNetApr, formatPercent)}
          suffix={'%'}
        />
        <SeriesToggler
          active={false}
          onClick={noop}
          text={'PORTFOLIO VALUE'}
          value={lmap(currentNetValue, formatNumber)}
          suffix={'USD'}
        />
      </TogglerRow>
    </HeadingContainer>
  );
};

type SeriesTogglerProps = {
  active: boolean;
  onClick: MouseEventHandler;
  text: string;
  value: Loading<string>;
  suffix: string;
};

const SeriesToggler: FC<SeriesTogglerProps> = ({
  active,
  onClick,
  text,
  value,
  suffix,
}) => (
  <TogglerContainer active={active} onClick={onClick}>
    <TogglerText>{text}</TogglerText>
    <TogglerValue>
      <LoadingText value={value} />
      <TogglerValueSuffix>{suffix}</TogglerValueSuffix>
    </TogglerValue>
  </TogglerContainer>
);

const VerticalFlex = styled.div`
  display: flex;
  flex-direction: column;
  flex-grow: 1;
`;

const HeadingContainer = styled.div`
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  margin: 30px;
`;

const Title = styled.h1`
  margin: 0;
`;

const TogglerContainer = styled(VerticalFlex)<{ active?: boolean }>`
  cursor: pointer;
  border-bottom: 2px solid transparent;

  ${({ active }) => active && `border-bottom: 2px solid white;`}

  transition: all .5s ease;
`;

const TogglerRow = styled.div`
  display: flex;
  gap: 2.625rem;
  margin-top: 20px;
`;

const TogglerText = styled.h3`
  margin: 0;
  color: ${({ theme }) => theme.colors.greyLight};
`;

const TogglerValue = styled.span`
  ${textH2}
`;

const TogglerValueSuffix = styled.span`
  ${textH3}

  padding-left: 0.25rem;
  color: ${({ theme }) => theme.colors.greyLight};
`;
