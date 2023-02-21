import type { FC } from 'react';
import styled from 'styled-components';

import { Button } from '@/components/commons/Button';
import { Icon } from '@/components/commons/Icon';
import { Spinner } from '@/components/commons/Spinner';
import {
  textP1,
  textP2,
  textH3,
  textH1,
  textH2,
} from '@/styles/mixins/text-styles';
import { formatDecimalBigNumber } from '@/utils/formatNumber';

import { RunOnChainState, State, Ctx } from './types';
import { tokenOrNativeSymbol, tokenOrNativeUsdPrice } from '@/utils/api-utils';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { LoadingText } from '@/components/commons/LoadingText';
import { lmap } from '@/utils/loading-value';
import { truncateAddress } from '@/utils/truncate-address';

type RunProps = {
  ctx: Ctx;
  state: RunOnChainState;
  setState(s: State): void;
};

export const Run: FC<RunProps> = ({ ctx, state }) => {
  const stage = state.stage.kind;
  const result = stage === 'done' && state.stage.result;
  const receiptToken = ctx.investment.receiptToken;

  const receiptTokenAmount = state.req.quote.receiptTokenAmount;
  const [receiptTokenPrice] = useAsyncLoad(() =>
    ctx.papi.getTokenUsdPrice(receiptToken)
  );
  const receptTokenUsdValue = lmap(receiptTokenPrice, (p) =>
    receiptTokenAmount.mul(p)
  );

  const exitToAsset = tokenOrNativeSymbol(
    state.req.quote.investment.chain,
    state.req.quote.to
  );
  const exitToAmount = result ? result.amountOut : state.req.quote.toAmount;
  const [exitToPrice] = useAsyncLoad(() =>
    tokenOrNativeUsdPrice(ctx.papi, state.req.quote.to)
  );
  const exitToAmountStr = formatDecimalBigNumber(exitToAmount);
  const exitToUsdValueStr = lmap(exitToPrice, (p) =>
    formatDecimalBigNumber(exitToAmount.mul(p))
  );

  return (
    <FlexDownSpaced>
      <Title>EXIT</Title>
      <FlexDown>
        <div>
          <SpanH2>{formatDecimalBigNumber(receiptTokenAmount)}</SpanH2>{' '}
          <SpanH3>{receiptToken.symbol}</SpanH3>
        </div>
        <DivP1>
          <LoadingText
            value={lmap(receptTokenUsdValue, formatDecimalBigNumber)}
          />{' '}
          USD
        </DivP1>
      </FlexDown>
      <FlexRightSpaced>
        <Icon iconName="flow-down" size={40} />
        <FlexDown>
          <ActionLabel active={stage !== 'done'}>
            {stage === 'approve' && 'Awaiting wallet approval'}
            {stage === 'exit' && 'Exiting'}
          </ActionLabel>
        </FlexDown>
        {stage === 'approve' && <Icon iconName="wallet" />}
        {stage === 'exit' && <Spinner size="small" />}
      </FlexRightSpaced>
      <FlexDown>
        {result && (
          <DivH3>
            TRANSACTION SUCCESSFUL
            <StyledAnchor
              href={ctx.investment.chain.explorer.transactionUrl(result.txHash)}
              target="_blank"
              rel="noopener noreferrer"
            >
              ({truncateAddress(result.txHash)}
              <Icon iconName="open-in-new" size={20} />)
            </StyledAnchor>
          </DivH3>
        )}
        <div>
          <SpanH2>{exitToAmountStr}</SpanH2> <SpanH3>{exitToAsset}</SpanH3>
        </div>
        <DivP1_>
          <LoadingText value={exitToUsdValueStr} /> USD
        </DivP1_>
        {!result && <DivP2>(estimated)</DivP2>}
      </FlexDown>
      {result && <Button label="Done" onClick={ctx.onDone} />}
    </FlexDownSpaced>
  );
};

const FlexDownSpaced = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 20px;
`;

const FlexDown = styled.div`
  display: flex;
  flex-direction: column;
`;

const FlexRightSpaced = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  gap: 20px;
`;

export const Title = styled.div`
  ${textH1}
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 10px;
  color: ${(props) => props.theme.colors.white};
`;

const DivP1_ = styled.div`
  ${textP1}
`;

const SpanH2 = styled.span`
  ${textH2}
  color: ${(props) => props.theme.colors.white};
`;

const SpanH3 = styled.span`
  ${textH3}
  color: ${(props) => props.theme.colors.greyLight};
`;

const DivP1 = styled.div`
  ${textP1}
  color: ${(props) => props.theme.colors.greyLight};
`;

const DivP2 = styled.div`
  ${textP2}
`;

const DivH3 = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 10px;
  ${textH3};
`;

const ActionLabel = styled.div<{ active: boolean }>`
  ${textP1}
  color: ${(props) =>
    props.active ? props.theme.colors.white : props.theme.colors.greyLight};
`;

const StyledAnchor = styled.a`
  display: flex;
  ${textP2}
  color: ${(props) => props.theme.colors.white};
`;
