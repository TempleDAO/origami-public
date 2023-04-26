import { useEffect, useState } from 'react';
import styled from 'styled-components';
import { DepositGrid, DepositGridItem } from './DepositGrid';
import { FlowOverlay } from '@/flows/invest';
import { MetricsResp, ProviderApi, SignerApi } from '@/api/api';
import { Chain, Investment, InvestmentConfig } from '@/api/types';
import {
  getValue,
  isReady,
  lmap,
  loading,
  Loading,
  newLoading,
  ready,
} from '@/utils/loading-value';
import { useApiManager } from '@/hooks/use-api-manager';
import { ApiCache } from '@/api/cache';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { isReserveToken } from '@/utils/api-utils';
import { useConnectModal } from '@/components/commons/ConnectModal';
import { PlatformMetricsWidget } from './PlatformMetricsWidget';
import { useMediaQuery } from '@/hooks/use-media-query';
import { theme } from '@/styles/theme';

export function Page() {
  const am = useApiManager();
  const modal = useConnectModal();
  return (
    <PageContent
      papi={am.papi}
      walletAddress={am.wallet?.address}
      cache={am.cache}
      walletInitialize={modal.walletInitialize}
      walletConnect={am.walletConnect}
    />
  );
}

interface PageContentProps {
  papi: ProviderApi;
  walletAddress: string | undefined;
  cache: ApiCache;
  walletInitialize(): Promise<void>;
  walletConnect(chain: Chain): Promise<SignerApi | undefined>;
}

export const PageContent = (props: PageContentProps) => {
  const { papi, walletConnect } = props;
  const [activeFlow, setActiveFlow] = useState<JSX.Element | undefined>();
  const investments = getValue(props.cache.investments) || [];
  const [pending, setPending] = useState<InvestmentConfig | undefined>();
  const [platformMetricsExpanded, setPlatformMetricsExpanded] = useState(false);
  const [VaultExpanded, setVaultExpanded] =
    useState<number | undefined>(undefined);
  const [platformTvl, setPlatformTvl] = useState<Loading<number>>(loading());
  const isDesktop = useMediaQuery(theme.responsiveBreakpoints.md);

  function hidePanel() {
    setActiveFlow(undefined);
  }

  async function onInvest(ic: InvestmentConfig) {
    if (props.walletAddress) {
      onInvestImpl(ic);
      return;
    }

    // We are not connected to a wallet yet. So initialize the
    // wallet now, then schedule the invest flow via an effect
    await props.walletInitialize();
    setPending(ic);
  }

  async function onInvestImpl(ic: InvestmentConfig) {
    const investment = await papi.getInvestment(ic);
    const sapi = await walletConnect(investment.chain);
    if (!sapi) {
      return;
    }

    // Filter out the reserve token from the UI (may be added as an 'advanced mode' in a future release)
    const allAcceptedTokens = await investment.acceptedInvestTokens();
    const acceptedTokens = allAcceptedTokens.filter(
      (value) => !isReserveToken(investment, value)
    );

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
    return makeDepositGridItem(papi, investment, metrics, tokenPrice, () =>
      onInvest(investment)
    );
  });

  useEffect(() => {
    async function delayedInvest() {
      if (props.walletAddress && pending) {
        await onInvestImpl(pending);
        setPending(undefined);
      }
    }
    delayedInvest();
  }, [props.walletAddress, pending]); // eslint-disable-line

  useEffect(() => {
    if (!papi) return;
    (async () => {
      if (isReady(platformTvl)) return;
      const pm = await papi.getPlatformMetrics();
      setPlatformTvl(ready(pm.tvl));
      if (isDesktop) setPlatformMetricsExpanded(true);
    })();
  }, [platformMetricsExpanded, papi, platformTvl, isDesktop]);

  return (
    <>
      <FlexDown>
        <PlatformMetricsWidget
          platformMetricsExpanded={platformMetricsExpanded}
          setPlatformMetricsExpanded={setPlatformMetricsExpanded}
          setVaultExpanded={setVaultExpanded}
          platformTvl={platformTvl}
          papi={papi}
        />
      </FlexDown>
      <FlexDown>
        <HeaderText>
          Origami provides auto-compounding vaults to maximize yield for
          supported protocols.
          <br />
          Your assets are put to work in the most optimal way with no locking.
          Exit at any time!
        </HeaderText>
        <DepositGrid
          items={gridItems}
          vaultExpanded={VaultExpanded}
          setVaultExpanded={setVaultExpanded}
          platformMetricsExpanded={platformMetricsExpanded}
          setPlatformMetricsExpanded={setPlatformMetricsExpanded}
        />
        {activeFlow}
      </FlexDown>
    </>
  );
};

function makeDepositGridItem(
  papi: ProviderApi,
  ic: Investment,
  metrics: Loading<MetricsResp>,
  tokenPrice: Loading<DecimalBigNumber>,
  onInvest?: () => Promise<void>
): DepositGridItem {
  return {
    icon: ic.icon,
    name: ic.name,
    description: ic.description,
    tokenPrice: tokenPrice,
    apy: lmap(metrics, (m) => m.apy),
    tvl: lmap(metrics, (m) => m.tvl),
    chain: ic.chain,
    info: ic.info,
    tokenAddr: ic.receiptToken.config.address,
    receiptToken: ic.receiptToken.symbol,
    reserveToken: ic.reserveToken.symbol,
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

export const HeaderText = styled.div`
  color: ${({ theme }) => theme.colors.greyLight};
  align-self: stretch;
`;

const FlexDown = styled.div`
  display: flex;
  flex-direction: column;
  padding: 1rem 0;
  width: 100%;
`;
