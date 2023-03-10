import type { FC } from 'react';

import { Button } from '@/components/commons/Button';
import { formatDecimalBigNumber } from '@/utils/formatNumber';

import { RunOnChainState, State, Ctx } from './types';
import { tokenOrNativeSymbol, tokenOrNativeUsdPrice } from '@/utils/api-utils';
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
    ? result.investTokenAmount
    : state.req.quote.expectedInvestmentAmount;
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
      {stage === 'approve' && (
        <>
          <ActionArrow busytext="Awaiting wallet approval" />
          <TxPending
            receivedAmount={receivedAmount}
            receivedAsset={receivedAsset}
            receivedUsdValue={receivedUsdValue}
          />
        </>
      )}
      {stage === 'invest' && (
        <>
          <ActionArrow busytext="Investing" />
          <TxPending
            receivedAmount={receivedAmount}
            receivedAsset={receivedAsset}
            receivedUsdValue={receivedUsdValue}
          />
        </>
      )}
      {stage === 'done' && result && (
        <>
          <ActionArrow />
          <TxSucceeded
            receivedAmount={receivedAmount}
            receivedAsset={receivedAsset}
            receivedUsdValue={receivedUsdValue}
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
