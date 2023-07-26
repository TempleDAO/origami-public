import type { FC } from 'react';
import type { HistoricPeriod, HistoryPoint } from '@/api/types';
import type { Loading } from '@/utils/loading-value';

import styled from 'styled-components';
import { LoadingText } from '@/components/commons/LoadingText';
import { lmap } from '@/utils/loading-value';
import { formatNumber, formatPercent } from '@/utils/formatNumber';
import { textH2, textH3 } from '@/styles/mixins/text-styles';

type NetHoldings = {
  currentNetApy: Loading<number>;
  currentNetValue: Loading<number>;
};

export type FetchHistoryCb = (
  period: HistoricPeriod
) => Promise<HistoryPoint[]>;

export const NetHoldings: FC<NetHoldings> = ({
  currentNetApy,
  currentNetValue,
}) => {
  return (
    <VerticalFlex>
      <Heading
        currentNetApy={currentNetApy}
        currentNetValue={currentNetValue}
      />
    </VerticalFlex>
  );
};

const Heading: FC<{
  currentNetApy: Loading<number>;
  currentNetValue: Loading<number>;
}> = ({ currentNetApy, currentNetValue }) => {
  return (
    <HeadingContainer>
      <Title>YOUR NET HOLDINGS</Title>
      <TogglerRow>
        <SeriesToggler
          text={'NET APY'}
          value={lmap(currentNetApy, formatPercent)}
          suffix={' %'}
        />
        <SeriesToggler
          text={'PORTFOLIO VALUE'}
          value={lmap(currentNetValue, formatNumber)}
          suffix={' USD'}
        />
      </TogglerRow>
    </HeadingContainer>
  );
};

type SeriesTogglerProps = {
  text: string;
  value: Loading<string>;
  suffix: string;
};

const SeriesToggler: FC<SeriesTogglerProps> = ({ text, value, suffix }) => (
  <VerticalFlex>
    <TogglerText>{text}</TogglerText>
    <TogglerValue>
      <LoadingText
        value={value}
        suffix={<TogglerValueSuffix>{suffix}</TogglerValueSuffix>}
      />
    </TogglerValue>
  </VerticalFlex>
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
`;

const Title = styled.h1`
  margin: 0;
`;

const TogglerRow = styled.div`
  display: flex;
  gap: 2.5rem;
  margin-top: 2rem;
`;

const TogglerText = styled.h3`
  margin: 0;
  color: ${({ theme }) => theme.colors.greyLight};
`;

const TogglerValue = styled.span`
  ${textH2}
`;

const TogglerValueSuffix = styled.span`
  ${textH3};
  color: ${({ theme }) => theme.colors.greyLight};
`;
