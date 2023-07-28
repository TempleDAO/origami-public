import { FC, useMemo } from 'react';
import type { MetricsResp } from '@/api/api';
import type { Investment } from '@/api/types';
import { Loading, isReady, loading, newLoading } from '@/utils/loading-value';

import styled from 'styled-components';
import { LoadingText } from '@/components/commons/LoadingText';
import { LoadingComponent } from '@/components/commons/LoadingComponent';
import { Icon } from '@/components/commons/Icon';
import { lmap } from '@/utils/loading-value';
import { formatNumber, formatPercent } from '@/utils/formatNumber';
import { investmentKeyByName } from '@/utils/api-utils';

import breakpoints from '@/styles/responsive-breakpoints';
import sunkenStyles from '@/styles/mixins/cards/sunken';
import { textH1, textH3 } from '@/styles/mixins/text-styles';
import { ApiCache } from '@/api/cache';
import { ApyTooltip } from '@/components/commons/ApyTooltip';

type InvestmentMetrics = {
  key: string;
  investment: Investment;
  metrics: Loading<MetricsResp>;
};

const ICON_SIZE = 34;

export const LandingPageMetrics: FC<{ cache: ApiCache }> = ({ cache }) => {
  const metrics = useMemo(
    () =>
      lmap(cache.investments, (investments) => {
        const result: InvestmentMetrics[] = [];
        for (const investment of investments) {
          result.push({
            key: investmentKeyByName(investment),
            investment,
            metrics: newLoading(cache.metrics.get(investment)),
          });
        }
        result.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
        return result;
      }),
    [cache.investments, cache.metrics]
  );

  return (
    <BadgesContainer>
      {isReady(metrics) ? (
        metrics.value.map((metrics) => (
          <MetricsBadge key={metrics.key}>
            <InvestmentInfo>
              <Icon
                iconName={metrics.investment.icon}
                size={ICON_SIZE}
                hasBackground
              />
              <MetricHeader>
                <h2>{metrics.investment.name}</h2>
                <p>
                  <MetricSubtext>{metrics.investment.chain.name}</MetricSubtext>
                </p>
              </MetricHeader>
            </InvestmentInfo>
            <ApyTooltip>
              <Metric key={`${metrics.key} - APY`}>
                <h2>APY</h2>
                <p>
                  <LoadingText
                    value={lmap(metrics.metrics, (v) => formatPercent(v.apy))}
                  />{' '}
                  <MetricSubtext>%</MetricSubtext>
                </p>
              </Metric>
            </ApyTooltip>
            <Metric key={`${metrics.key} - TVL`}>
              <h2>TVL</h2>
              <p>
                $
                <LoadingText
                  value={lmap(metrics.metrics, (v) => formatNumber(v.tvl))}
                />{' '}
                <MetricSubtext>USD</MetricSubtext>
              </p>
            </Metric>
          </MetricsBadge>
        ))
      ) : (
        <>
          <EmptyMetricsBatch />
          <EmptyMetricsBatch />
        </>
      )}
    </BadgesContainer>
  );
};

const EmptyMetricsBatch = () => {
  return (
    <MetricsBadge>
      <InvestmentInfo>
        <LoadingIcon width={50} height={50} />
        <MetricHeader>
          <h2>
            <LoadingText value={loading()} />
          </h2>
        </MetricHeader>
      </InvestmentInfo>
      <Metric>
        <h2>APY</h2>
        <p>
          <LoadingText value={loading()} /> <MetricSubtext>%</MetricSubtext>
        </p>
      </Metric>
      <Metric>
        <h2>TVL</h2>
        <p>
          $
          <LoadingText value={loading()} /> <MetricSubtext>USD</MetricSubtext>
        </p>
      </Metric>
    </MetricsBadge>
  );
};

const BadgesContainer = styled.div`
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 25px;
  justify-content: center;
  margin-top: 30px;

  ${breakpoints.xl(`
  flex-direction: column;
`)}
`;

const MetricsBadge = styled.div`
  ${sunkenStyles}

  display: flex;
  flex-direction: column;
  padding: 20px 30px;
  box-sizing: border-box;
  gap: 25px;
  height: 22.5rem;

  align-self: center;

  background-color: ${({ theme }) => theme.colors.bgMid};
  border-radius: 2.5rem;

  ${breakpoints.smOnly(`
  height: 18rem;
`)}

  ${breakpoints.xl(`
  flex-direction: row;
  height: 10rem;
  gap: 98px;
  padding: 40px 60px;
`)};
`;

const InvestmentInfo = styled.div`
  display: flex;
  align-items: center;
  gap: 1.25rem;
`;

const LoadingIcon = styled(LoadingComponent)`
  border-radius: 99999px;
`;

const MetricHeader = styled.div`
  display: flex;
  flex-direction: column;
  width: 10rem;

  h2 {
    margin: 0;
  }

  p {
    margin: 0;
    ${textH1}
  }

  ${breakpoints.sm(`
    width: 15rem;
  `)}
`;

const Metric = styled.div`
  display: flex;
  flex-direction: column;
  text-transform: uppercase;
  width: 15rem;

  h2 {
    margin: 0;
  }

  p {
    margin: 0;
    ${textH1}
  }
`;

const MetricSubtext = styled.span`
  ${textH3}
  color: ${({ theme }) => theme.colors.greyLight};
`;
