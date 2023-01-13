import { useState } from 'react';
import styled from 'styled-components';
import { InvestGrid, Link, InvestGridItem } from './InvestGrid';
import { FlowOverlay } from '@/flows/invest';
import { MetricsResp, ProviderApi, SignerApi } from '@/api/api';
import { ChainId, InvestmentConfig } from '@/api/types';
import { getValue, lmap, Loading, newLoading } from '@/utils/loading-value';
import { useApiManager } from '@/hooks/use-api-manager';
import { ApiCache } from '@/api/cache';

export function Page() {
  const am = useApiManager();
  return (
    <PageContent
      papi={am.papi}
      sapi={am.sapi}
      cache={am.cache}
      connectSigner={am.connectSigner}
    />
  );
}

interface PageContentProps {
  papi: ProviderApi;
  sapi?: SignerApi;
  cache: ApiCache;
  connectSigner(chainId: ChainId): Promise<void>;
}

export const PageContent = (props: PageContentProps) => {
  const { papi, sapi, connectSigner } = props;
  const [activeFlow, setActiveFlow] = useState<JSX.Element | undefined>();
  const investments = getValue(props.cache.investments) || [];

  function hidePanel() {
    setActiveFlow(undefined);
  }

  async function onInvest(ic: InvestmentConfig, sapi: SignerApi) {
    const investment = await papi.getInvestment(ic);
    await connectSigner(investment.chain.id);
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
    return makeInvestGridItem(
      papi,
      investment,
      metrics,
      sapi && (() => onInvest(investment, sapi))
    );
  });

  return (
    <FlexDown>
      <Title>INVESTMENT OPPORTUNITIES</Title>
      <InfoBox>
        Origami aims to provide a rewards-boosted liquidity layer on a selection
        of low-risk, high-volume investments, to improve the usual staking of LP
        tokens for rewards. Note that Investments made in liquidity pools have
        the potential to suffer <Link>impermanent loss</Link>.
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
  onInvest?: () => Promise<void>
): InvestGridItem {
  const chain = papi.chains.get(ic.contractAddress.chainId)?.name || '??';
  return {
    icon: ic.icon,
    name: ic.name,
    description: ic.description,
    apr: lmap(metrics, (m) => m.apr),
    tvl: lmap(metrics, (m) => m.tvl),
    chain,
    info: ic.info,
    moreInfoUrl: ic.moreInfoUrl,
    getHistory: async (period, metric) => {
      const investment = await papi.getInvestment(ic);
      return investment.getHistoricMetric({ period, metric });
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
