import { useState } from 'react';
import styled from 'styled-components';
import { InvestGrid, InvestGridItem } from './InvestGrid';
import { FlowOverlay } from '@/flows/invest';
import { MetricsResp, ProviderApi, SignerApi } from '@/api/api';
import { Chain, InvestmentConfig } from '@/api/types';
import { getValue, lmap, Loading, newLoading } from '@/utils/loading-value';
import { useApiManager } from '@/hooks/use-api-manager';
import { ApiCache } from '@/api/cache';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

export function Page() {
  const am = useApiManager();
  return (
    <PageContent
      papi={am.papi}
      walletAddress={am.wallet?.address}
      cache={am.cache}
      walletConnect={am.walletConnect}
    />
  );
}

interface PageContentProps {
  papi: ProviderApi;
  walletAddress: string | undefined;
  cache: ApiCache;
  walletConnect(chain: Chain): Promise<SignerApi>;
}

export const PageContent = (props: PageContentProps) => {
  const { papi, walletConnect } = props;
  const [activeFlow, setActiveFlow] = useState<JSX.Element | undefined>();
  const investments = getValue(props.cache.investments) || [];

  function hidePanel() {
    setActiveFlow(undefined);
  }

  async function onInvest(ic: InvestmentConfig) {
    const investment = await papi.getInvestment(ic);
    const sapi = await walletConnect(investment.chain);
    const acceptedTokens = await investment.acceptedInvestTokens();
    const flow = (
      <FlowOverlay
        papi={papi}
        sapi={sapi}
        investment={investment}
        acceptedTokens={acceptedTokens}
        cache={props.cache}
        hidePanel={hidePanel}
      />
    );
    setActiveFlow(flow);
  }

  const gridItems = investments.map((investment) => {
    const metrics = newLoading(props.cache.metrics.get(investment));
    const tokenPrice = newLoading(props.cache.tokenPrices.get(investment));
    return makeInvestGridItem(
      papi,
      investment,
      metrics,
      tokenPrice,
      props.walletAddress ? () => onInvest(investment) : undefined
    );
  });

  return (
    <FlexDown>
      <Title>INVESTMENT VAULTS</Title>
      <InfoBox>
        Origami provides auto-compounding investment vaults on a carefully
        selected set of protocols. No staking or locking required.
        <br />
        Your assets are put to work in the most optimal way, and you can exit at
        any time.
      </InfoBox>
      <InvestGrid items={gridItems} expanded={0} />
      {activeFlow}
    </FlexDown>
  );
};

function makeInvestGridItem(
  papi: ProviderApi,
  ic: InvestmentConfig,
  metrics: Loading<MetricsResp>,
  tokenPrice: Loading<DecimalBigNumber>,
  onInvest?: () => Promise<void>
): InvestGridItem {
  const chain = papi.chains.get(ic.contractAddress.chainId)?.name || '??';
  return {
    icon: ic.icon,
    name: ic.name,
    description: ic.description,
    tokenPrice: tokenPrice,
    apy: lmap(metrics, (m) => m.apy),
    tvl: lmap(metrics, (m) => m.tvl),
    chain,
    info: ic.info,
    moreInfoUrl: ic.moreInfoUrl,
    getHistory: async (period, metricOrPrice) => {
      const investment = await papi.getInvestment(ic);
      if (metricOrPrice == 'price') {
        return papi.getHistoricTokenUsdPrice({
          token: investment.receiptToken,
          period,
        });
      } else {
        return investment.getHistoricMetric({
          period,
          metric: metricOrPrice,
        });
      }
    },
    onInvest,
  };
}

export const InfoBox = styled.div`
  color: ${({ theme }) => theme.colors.greyLight};
  align-self: stretch;
`;

const FlexDown = styled.div`
  display: flex;
  flex-direction: column;
`;

const Title = styled.div`
  font-size: 1.5rem;
  font-weight: bold;
  margin-top: 20px;
  margin-bottom: 1rem;
`;
