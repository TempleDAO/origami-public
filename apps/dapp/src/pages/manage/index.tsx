import { ProviderApi, SignerApi } from '@/api/api';
import { Chain, Investment } from '@/api/types';
import { useApiManager } from '@/hooks/use-api-manager';
import {
  ApiCache,
  BalanceMap,
  MetricsVMap,
  TokenPricesVMap,
} from '@/api/cache';
import { useMemo, useState } from 'react';
import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { Text } from '@/components/commons/Text';

import {
  isReady,
  lmap,
  lmap2,
  Loading,
  newLoading,
} from '@/utils/loading-value';

import { AssetHolding } from './AssetsTable';
import { AssetDetails } from './AssetDetails';
import { AssetsTable } from './AssetsTable';
import { NetHoldings } from './NetHoldings';
import { Button } from '@/components/commons/Button';
import { textH5 } from '@/styles/mixins/text-styles';
import { ConnectWalletButton } from '@/components/commons/ConnectWalletButton';
import { Link } from '@/components/commons/Link';
import { DBN_ZERO } from '@/utils/decimal-big-number';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { asyncNever } from '@/utils/noop';

export function Page() {
  const am = useApiManager();
  const [selectedInvestment, setSelectedInvestment] =
    useState<Investment | undefined>();

  return (
    <PageContent
      papi={am.papi}
      sapi={am.walletConnect}
      walletAddress={am.wallet?.address}
      cache={am.cache}
      selectedInvestment={selectedInvestment}
      setSelectedInvestment={setSelectedInvestment}
    />
  );
}
interface PageContentProps {
  papi: ProviderApi;
  sapi(chain: Chain): Promise<SignerApi | undefined>;
  walletAddress: string | undefined;
  cache: ApiCache;
  selectedInvestment: Investment | undefined;
  setSelectedInvestment(i: Investment | undefined): void;
}

export function PageContent(props: PageContentProps) {
  const cache = props.cache;

  const userHoldings = useMemo(
    () =>
      lmap2([cache.investments, cache.balances], (investments, balances) =>
        calcAssetHoldings(
          investments,
          balances,
          cache.metrics,
          cache.tokenPrices
        )
      ),
    [cache.investments, cache.balances, cache.metrics, cache.tokenPrices]
  );

  const [metrics] = useAsyncLoad(
    () => calcPortfolioMetrics(props.papi, userHoldings),
    [props.papi, userHoldings]
  );

  if (!props.walletAddress) {
    return (
      <EmptyStateWrapper>
        <p>Connect your wallet to view and manage your holdings</p>
        <ConnectWalletButton />
      </EmptyStateWrapper>
    );
  }

  if (userHoldings.state === 'ready' && userHoldings.value.length === 0) {
    return (
      <EmptyStateWrapper>
        <p>You Currently have no deposits in Origami</p>
        <Link removedecoration href="/deposit">
          <Button wide label="VIEW OPPORTUNITIES" />
        </Link>
      </EmptyStateWrapper>
    );
  }

  return (
    <VerticalFlex css="width: 100%;">
      {props.selectedInvestment ? (
        <>
          <BackButton onClick={() => props.setSelectedInvestment(undefined)}>
            <BackIcon size={16} />
            <BackButtonLabel>BACK TO ALL ASSETS</BackButtonLabel>
          </BackButton>
          <AssetDetails
            papi={props.papi}
            sapi={props.sapi}
            cache={props.cache}
            investment={props.selectedInvestment}
          />
        </>
      ) : (
        <>
          <GraphRewardsSection>
            <NetHoldings
              currentNetApy={lmap(metrics, (m) => m.apy)}
              currentNetValue={lmap(metrics, (m) => m.tvl)}
            />
          </GraphRewardsSection>
          <HoldingsBreakdownSection as="section">
            <BreakdownTitle>HOLDINGS BREAKDOWN</BreakdownTitle>
            <AssetsTable
              holdings={userHoldings}
              handleSelect={props.setSelectedInvestment}
            />
          </HoldingsBreakdownSection>
        </>
      )}
    </VerticalFlex>
  );
}

interface PortfolioMetrics {
  apy: number;
  tvl: number;
}

function calcAssetHoldings(
  investments: Investment[],
  balances: BalanceMap,
  metricsMap: MetricsVMap,
  pricesMap: TokenPricesVMap
): AssetHolding[] {
  const result: AssetHolding[] = [];
  for (const investment of investments) {
    const balance = balances.get(investment);
    if (balance && balance.gt(DBN_ZERO)) {
      const token = investment.receiptToken;
      const metrics = newLoading(metricsMap.get(investment));
      const price = newLoading(pricesMap.get(investment));
      result.push({ investment, token, balance, metrics, price });
    }
  }
  return result;
}

async function calcPortfolioMetrics(
  papi: ProviderApi,
  userHoldings: Loading<AssetHolding[]>
): Promise<PortfolioMetrics> {
  // First check everything is ready.
  if (!isReady(userHoldings)) {
    return asyncNever();
  }
  for (const uh of userHoldings.value) {
    if (!isReady(uh.metrics)) {
      return asyncNever();
    }
  }

  let tvl = 0;
  let apy = 0;
  for (const uh of userHoldings.value) {
    if (isReady(uh.metrics)) {
      const usdPrice = await papi.getTokenUsdPrice(uh.investment.receiptToken);
      const value = Number(uh.balance.mul(usdPrice).formatUnits(2));
      tvl += value;
      apy += uh.metrics.value.apy * value;
    }
  }
  apy = apy / tvl;
  return {
    apy,
    tvl,
  };
}

const VerticalFlex = styled.div`
  display: flex;
  flex-direction: column;
`;

const EmptyStateWrapper = styled.div`
  margin: auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  max-width: 18rem;
  text-align: center;
  p {
    ${textH5};
    text-transform: uppercase;
    font-weight: bold;
  }
`;

const GraphRewardsSection = styled.section`
  display: flex;
  gap: 3.75rem;
`;

const HoldingsBreakdownSection = styled(VerticalFlex)`
  margin-top: 3.75rem;
`;

const BreakdownTitle = styled.h2`
  margin: 0;
  margin-bottom: 1.25rem;
`;

const BackButton = styled.div`
  display: flex;
  align-items: center;
  justify-content: start;
  gap: 1.25rem;

  width: fit-content;
  margin-bottom: 3rem;

  cursor: pointer;

  * {
    cursor: pointer;
    user-select: none;
  }
  &:hover {
    * {
      color: ${({ theme }) => theme.colors.white};
    }
  }
`;

const BackButtonLabel = styled(Text)`
  display: inline-block;
  color: ${({ theme }) => theme.colors.greyLight};
  text-decoration: underline;
  transition: 300ms ease color;
`;

const BackIcon = styled(Icon).attrs({
  iconName: 'expand-dark',
})`
  rotate: 90deg;
`;
