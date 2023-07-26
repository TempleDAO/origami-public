import type { FC } from 'react';

import { Button } from '@/components/commons/Button';
import { formatDecimalBigNumber } from '@/utils/formatNumber';

import { RunOnChainState, State, Ctx } from './types';
import { tokenOrNativeLabel, tokenOrNativeUsdPrice } from '@/utils/api-utils';
import { useAsyncLoad } from '@/hooks/use-async-result';
import { LoadingText } from '@/components/commons/LoadingText';
import { lmap } from '@/utils/loading-value';
import {
  FlexDownSpaced,
  FlexDown,
  SpanH2,
  SpanH3,
  DivP1,
  ActionArrow,
  TxPending,
  TxSucceeded,
  TxFailed,
} from '../common/components';
import { Title } from './Form';

type RunProps = {
  ctx: Ctx;
  state: RunOnChainState;
  setState(s: State): void;
};

export const Run: FC<RunProps> = ({ ctx, state }) => {
  const stage = state.stage.kind;
  const result = stage === 'done' && state.stage.result;
  const receiptToken = ctx.investment.receiptToken;

  const receiptTokenAmount = state.req.quote.exitAmount;
  const [receiptTokenPrice] = useAsyncLoad(() =>
    ctx.papi.getTokenUsdPrice(receiptToken)
  );
  const receptTokenUsdValue = lmap(receiptTokenPrice, (p) =>
    receiptTokenAmount.mul(p)
  );

  const exitToAsset = tokenOrNativeLabel(state.req.quote.to);
  const exitToAmount = result
    ? result.amountOut
    : state.req.quote.expectedToAmount;
  const [exitToPrice] = useAsyncLoad(() =>
    tokenOrNativeUsdPrice(ctx.papi, state.req.quote.to)
  );
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
      {stage === 'approve' && (
        <>
          <ActionArrow busytext="Awaiting wallet approval" />
          <TxPending
            receivedAmount={exitToAmount}
            receivedAsset={exitToAsset}
            receivedUsdValue={exitToUsdValueStr}
          />
        </>
      )}
      {stage === 'exit' && (
        <>
          <ActionArrow busytext="Exiting" />
          <TxPending
            receivedAmount={exitToAmount}
            receivedAsset={exitToAsset}
            receivedUsdValue={exitToUsdValueStr}
          />
        </>
      )}
      {stage === 'done' && result && (
        <>
          <ActionArrow />
          <TxSucceeded
            receivedAmount={exitToAmount}
            receivedAsset={exitToAsset}
            receivedUsdValue={exitToUsdValueStr}
            txHash={result.txHash}
            transactionUrl={ctx.investment.chain.explorer.transactionUrl}
          />
          <Button label="Done" onClick={ctx.onDone} />
        </>
      )}
      {stage === 'txfail' && (
        <>
          <ActionArrow />
          <TxFailed
            message={state.stage.message}
            txHash={state.stage.txhash}
            transactionUrl={ctx.investment.chain.explorer.transactionUrl}
          />
          <Button label="OK" onClick={ctx.onDone} />
        </>
      )}
    </FlexDownSpaced>
  );
};
