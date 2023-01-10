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

type RunProps = {
  ctx: Ctx;
  state: RunOnChainState;
  setState(s: State): void;
};

export const Run: FC<RunProps> = ({ ctx, state }) => {
  const stage = state.stage.kind;
  const result = stage === 'done' && state.stage.result;

  const [investUsdPrice] = useAsyncLoad(() =>
    tokenOrNativeUsdPrice(ctx.papi, state.req.quote.from)
  );

  const [receivedUsdPrice] = useAsyncLoad(() =>
    ctx.papi.getTokenUsdPrice(ctx.investment.receiptToken)
  );

  const investAmount = state.req.quote.amount;
  const investAsset = tokenOrNativeSymbol(
    state.req.quote.investment.chain,
    state.req.quote.from
  );
  const investUsdValue = lmap(investUsdPrice, (price) =>
    formatDecimalBigNumber(price.mul(investAmount))
  );

  const receivedAmount = result
    ? result.receiptTokenAmount
    : state.req.quote.receiptTokenAmount;
  const receivedAsset = ctx.investment.receiptToken.symbol;
  const receivedUsdValue = lmap(receivedUsdPrice, (price) =>
    formatDecimalBigNumber(price.mul(receivedAmount))
  );

  return (
    <FlexDownSpaced>
      <Title>INVEST</Title>
      <FlexDown>
        <div>
          <SpanH2>{formatDecimalBigNumber(investAmount)}</SpanH2>{' '}
          <SpanH3>{investAsset}</SpanH3>
        </div>
        <DivP1>
          <LoadingText value={investUsdValue} /> USD
        </DivP1>
      </FlexDown>
      <FlexRightSpaced>
        <Icon iconName="flow-down" size={40} />
        <FlexDown>
          <ActionLabel active={stage !== 'done'}>
            {stage === 'approve' && 'Awaiting wallet approval'}
            {stage === 'invest' && 'Investing'}
          </ActionLabel>
        </FlexDown>
        {stage === 'approve' && <Icon iconName="wallet" />}
        {stage === 'invest' && <Spinner size="small" />}
      </FlexRightSpaced>
      {!result && (
        <FlexDown>
          <div>
            <SpanH2>{formatDecimalBigNumber(receivedAmount)}</SpanH2>{' '}
            <SpanH3>{receivedAsset}</SpanH3>
          </div>
          <DivP1_>
            <LoadingText value={receivedUsdValue} /> USD
          </DivP1_>
          <DivP2>(estimated)</DivP2>
        </FlexDown>
      )}
      {result && (
        <>
          <FlexDown>
            <DivH3>TRANSACTION SUCCESSFUL</DivH3>
            <DivP1_>You received:</DivP1_>
            <div>
              <SpanH2>{formatDecimalBigNumber(receivedAmount)}</SpanH2>{' '}
              <SpanH3>{receivedAsset}</SpanH3>
            </div>
            <DivP1>
              <LoadingText value={receivedUsdValue} /> USD
            </DivP1>
          </FlexDown>
          <Button label="Done" onClick={ctx.onDone} />
        </>
      )}
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
  color: ${(props) => props.theme.colors.white}
`;
const DivP1_ = styled.div`
  ${textP1}
`;
const DivH3 = styled.div`
  ${textH3}
`;
const SpanH2 = styled.span`
  ${textH2}
  color: ${(props) => props.theme.colors.white}
`;
const SpanH3 = styled.span`
  ${textH3}
  color: ${(props) => props.theme.colors.greyLight}
`;
const DivP1 = styled.div`
  ${textP1}
  color: ${(props) => props.theme.colors.greyLight}
`;
const DivP2 = styled.div`
  ${textP2}
`;
const ActionLabel = styled.div<{ active: boolean }>`
  ${textP1}
  color: ${(props) =>
    props.active ? props.theme.colors.white : props.theme.colors.greyLight};
`;
