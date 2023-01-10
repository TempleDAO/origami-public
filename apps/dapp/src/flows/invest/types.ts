import type {
  InvestQuoteResp,
  InvestReq,
  InvestStage,
  ProviderApi,
  SignerApi,
} from '@/api/api';
import type { Investment, TokenOrNative } from '@/api/types';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

// Values available to every screen in the flow
export interface Ctx {
  investment: Investment;
  acceptedTokens: TokenOrNative[];
  papi: ProviderApi;
  sapi: SignerApi;
  onDone(): void;
}

// The state machine for the flow.
export type State = FormState | RunOnChainState;

export interface FormState {
  kind: 'form';
  initial?: InitialValues;
  cancelAllowed: boolean;
}

export interface RunOnChainState {
  kind: 'run';
  req: InvestReq;
  stage: InvestStage;
  cancelAllowed: boolean;
}

export interface InitialValues {
  amount: DecimalBigNumber;
  ofAsset: TokenOrNative;
  slippageBps: number;
}

export function formState(initial?: InitialValues): FormState {
  return {
    kind: 'form',
    initial,
    cancelAllowed: true,
  };
}

export function runOnChainState(
  req: InvestReq,
  stage: InvestStage
): RunOnChainState {
  return {
    kind: 'run',
    req,
    stage,
    cancelAllowed: stage.kind == 'done',
  };
}

export const start = formState;

/**
 * Run the invest method on the api, triggering UI state changes as required.
 */
export async function runInvest(
  api: Pick<SignerApi, 'invest'>,
  setState: (state: State) => void,
  quote: InvestQuoteResp,
  slippageBps: number
): Promise<void> {
  const req: InvestReq = {
    quote,
    slippageBps,
    onStage,
  };

  function onStage(stage: InvestStage) {
    setState(runOnChainState(req, stage));
  }

  try {
    await api.invest(req);
  } catch (e) {
    console.error(e);
    setState(
      formState({
        amount: req.quote.amount,
        ofAsset: req.quote.from,
        slippageBps: req.slippageBps,
      })
    );
  }
}
