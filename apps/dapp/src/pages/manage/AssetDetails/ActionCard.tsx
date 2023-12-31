import type { FC } from 'react';
import type { Investment } from '@/api/types';
import type { Loading } from '@/utils/loading-value';
import { RequestActionFn } from '@/hooks/use-api-manager';
import styled from 'styled-components';
import { AsyncButton } from '@/components/commons/Button';
import { Text } from '@/components/commons/Text';
import { LoadingText } from '@/components/commons/LoadingText';
import { FlowOverlay as InvestOverlay } from '@/flows/invest';
import { FlowOverlay as ExitOverlay } from '@/flows/exit';
import raisedStyles from '@/styles/mixins/cards/raised';
import { textH1 } from '@/styles/mixins/text-styles';
import { ProviderApi, SignerApi } from '@/api/api';
import { ApiCache } from '@/api/cache';
import breakpoints from '@/styles/responsive-breakpoints';
import { isReserveToken } from '@/utils/api-utils';

type ActionCardProps = {
  papi: ProviderApi;
  sapi?: SignerApi;
  cache: ApiCache;
  investment: Investment;
  apy: Loading<string>;
  receiptTokenBalance: Loading<string>;
  receiptTokenBalanceUsd: Loading<string>;
  setActiveFlow: (Flow: JSX.Element | undefined) => void;
  requestActionWithSigner: RequestActionFn;
};

export const ActionCard: FC<ActionCardProps> = ({
  cache,
  investment,
  apy,
  receiptTokenBalance,
  receiptTokenBalanceUsd,
  setActiveFlow,
  requestActionWithSigner,
}) => {
  function hidePanel() {
    setActiveFlow(undefined);
  }

  const receiptToken = investment.receiptToken.symbol;

  async function showInvestFlow(papi: ProviderApi, sapi: SignerApi) {
    // Filter out the reserve token from the UI (may be added as an 'advanced mode' in a future release)
    const allAcceptedTokens = await investment.acceptedInvestTokens();
    const acceptedTokens = allAcceptedTokens.filter(
      (value) => !isReserveToken(investment, value)
    );

    setActiveFlow(
      <InvestOverlay
        papi={papi}
        sapi={sapi}
        cache={cache}
        investment={investment}
        acceptedTokens={acceptedTokens}
        hidePanel={hidePanel}
      />
    );
  }

  async function showExitFlow(papi: ProviderApi, sapi: SignerApi) {
    // Filter out the reserve token from the UI (may be added as an 'advanced mode' in a future release)
    const allAcceptedTokens = await investment.acceptedExitTokens();
    const acceptedTokens = allAcceptedTokens.filter(
      (value) => !isReserveToken(investment, value)
    );

    setActiveFlow(
      <ExitOverlay
        papi={papi}
        sapi={sapi}
        cache={cache}
        investment={investment}
        acceptedTokens={acceptedTokens}
        hidePanel={hidePanel}
      />
    );
  }

  return (
    <Container>
      <H1>YOUR TOKENS</H1>
      <TokenBalances>
        <TokenBalanceRow>
          <VerticalFlex>
            <Text>{receiptToken}</Text>
            <InfoText>
              <LoadingText value={apy} />% APY
            </InfoText>
          </VerticalFlex>
          <VerticalFlex>
            <TokenBalance>
              <LoadingText value={receiptTokenBalance} />
            </TokenBalance>
            <InfoText>
              <LoadingText value={receiptTokenBalanceUsd} /> USD
            </InfoText>
          </VerticalFlex>
        </TokenBalanceRow>
      </TokenBalances>
      <VerticalFlex>
        <ActionRow>
          <AsyncButton
            secondary
            label="Deposit"
            onClick={async () =>
              requestActionWithSigner(investment.chain.id, showInvestFlow)
            }
          />
          <InfoText small>
            Deposit with{' '}
            <Highlight>{investment.supportedAssetsDescription}</Highlight> and
            receive <Highlight>{receiptToken}</Highlight>.
          </InfoText>
        </ActionRow>
        <ActionRow>
          <AsyncButton
            secondary
            label="Exit"
            onClick={async () =>
              requestActionWithSigner(investment.chain.id, showExitFlow)
            }
          />
          <InfoText small>
            Exit <Highlight>{investment.receiptToken.symbol}</Highlight> to
            receive{' '}
            <Highlight>{investment.supportedAssetsDescription}</Highlight>.
          </InfoText>
        </ActionRow>
      </VerticalFlex>
    </Container>
  );
};

const H1 = styled.h1`
  margin: 0;
`;

const VerticalFlex = styled.div`
  display: flex;
  flex-direction: column;
`;

const Container = styled(VerticalFlex)`
  box-sizing: border-box;
  ${raisedStyles}
  height: fit-content;
  min-width: 0;
  width: 100%;
  padding: 2.5rem;

  ${breakpoints.md(`
    min-width: 31rem;
  `)}
`;

const InfoText = styled(Text)`
  display: inline-block;
  color: ${({ theme }) => theme.colors.greyLight};

  ${breakpoints.md(`
    display: inline-block;
  `)}
`;

const TokenBalances = styled.div`
  display: flex;
  flex-direction: column;
  padding-top: 2.5rem;
  padding-bottom: 1.875rem;
`;

const TokenBalanceRow = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;

  :not(:first-child) {
    margin-top: 2.2rem;
  }

  ${VerticalFlex}:not(:first-child) {
    text-align: right;
  }
`;

const TokenBalance = styled.p`
  ${textH1}
  margin: 0;
`;

const ActionRow = styled.div`
  display: flex;
  align-items: center;
  gap: 1.25rem;

  :not(:last-child) {
    margin-bottom: 1.875rem;
  }
`;

const Highlight = styled.span`
  color: ${({ theme }) => theme.colors.white};
`;
