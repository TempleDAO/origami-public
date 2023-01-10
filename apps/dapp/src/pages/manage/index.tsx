import { ProviderApi, SignerApi } from '@/api/api';
import { Investment } from '@/api/types';
import { useApiManager } from '@/hooks/use-api-manager';

import { useMemo, useState } from 'react';
import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { Text } from '@/components/commons/Text';

import { lmap } from '@/utils/loading-value';

import { AssetHolding, loadAssetHoldings } from './AssetsTable';
import { AssetDetails } from './AssetDetails';
import { AssetsTable } from './AssetsTable';
import { NetHoldings } from './NetHoldings';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { asyncNever } from '@/utils/noop';
import { Button } from '@/components/commons/Button';
import { textH5 } from '@/styles/mixins/text-styles';
import { ConnectWalletButton } from '@/components/commons/ConnectWalletButton';
import { Link } from '@/components/commons/Link';

export function Page() {
  const am = useApiManager();
  const [selectedInvestment, _setSelectedInvestment] =
    useState<Investment | undefined>();

  async function setSelectedInvestment(
    investment: Investment | undefined
  ): Promise<void> {
    if (investment) {
      await am.connectSigner(investment.chain.id);
    }
    _setSelectedInvestment(investment);
  }

  return (
    <PageContent
      papi={am.papi}
      sapi={am.sapi}
      selectedInvestment={selectedInvestment}
      setSelectedInvestment={setSelectedInvestment}
    />
  );
}
interface PageContentProps {
  papi: ProviderApi;
  sapi?: SignerApi;
  selectedInvestment: Investment | undefined;
  setSelectedInvestment(i: Investment | undefined): void;
}

export function PageContent(props: PageContentProps) {
  const signerAddress = props.sapi?.signerAddress;

  const [userHoldings] = useAsyncLoad(
    () => loadUserHoldingsIfSigner(signerAddress, props.papi),
    [signerAddress, props.papi]
  );

  const metrics = useMemo(
    () => lmap(userHoldings, calcPortfolioMetrics),
    [userHoldings]
  );

  if (!props.sapi) {
    return (
      <EmptyStateWrapper>
        <p>Connect your wallet to view and manage your holdings</p>
        <ConnectWalletButton usePrimaryStyling />
      </EmptyStateWrapper>
    );
  }

  if (userHoldings.state === 'ready' && userHoldings.value.length === 0) {
    return (
      <EmptyStateWrapper>
        <p>You Currently have no investments in Origami</p>
        <Link removedecoration href="/invest">
          <Button wide label="VIEW OPPORTUNITIES" />
        </Link>
      </EmptyStateWrapper>
    );
  }

  return (
    <VerticalFlex css="width: 100%;">
      {props.selectedInvestment && props.sapi ? (
        <>
          <BackButton onClick={() => props.setSelectedInvestment(undefined)}>
            <BackIcon size={16} />
            <BackButtonLabel>BACK TO ALL ASSETS</BackButtonLabel>
          </BackButton>
          <AssetDetails
            papi={props.papi}
            sapi={props.sapi}
            investment={props.selectedInvestment}
          />
        </>
      ) : (
        <>
          <GraphRewardsSection>
            <NetHoldings
              currentNetApr={lmap(metrics, (m) => m.apr)}
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

async function loadUserHoldingsIfSigner(
  signerAddress: string | undefined,
  papi: ProviderApi
): Promise<AssetHolding[]> {
  if (signerAddress == undefined) {
    return asyncNever();
  } else {
    return loadAssetHoldings(signerAddress, papi);
  }
}

interface PortfolioMetrics {
  apr: number;
  tvl: number;
}

function calcPortfolioMetrics(userHoldings: AssetHolding[]): PortfolioMetrics {
  let tvl = 0;
  let apr = 0;
  for (const uh of userHoldings) {
    const value = Number(uh.balance.mul(uh.usdPrice).formatUnits(2));
    tvl += value;
    apr += uh.apr * value;
  }
  apr = apr / tvl;
  return {
    apr,
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
`;

const BackButtonLabel = styled(Text)`
  display: inline-block;
  color: ${({ theme }) => theme.colors.greyLight};
  text-decoration: underline;
`;

const BackIcon = styled(Icon).attrs({
  iconName: 'expand-dark',
})`
  rotate: 90deg;
`;
