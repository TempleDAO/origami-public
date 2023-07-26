import type {
  ExitQuoteResp,
  ExitReq,
  ExitStage,
  ProviderApi,
  SignerApi,
} from '@/api/api';
import type { Investment, TokenOrNative } from '@/api/types';
import { DecimalBigNumber } from '@/utils/decimal-big-number';

export interface Ctx {
  investment: Investment;
  acceptedTokens: TokenOrNative[];
  papi: ProviderApi;
  sapi: SignerApi;
  onDone(): void;
}

export type State = FormState | RunOnChainState;

export interface FormState {
  kind: 'form';
  initial?: InitialValues;
  cancelAllowed: boolean;
}

export interface RunOnChainState {
  kind: 'run';
  req: ExitReq;
  stage: ExitStage;
  cancelAllowed: boolean;
}

export interface InitialValues {
  amount: DecimalBigNumber;
  toAsset: TokenOrNative;
}

export function formState(initial?: InitialValues): FormState {
  return {
    kind: 'form',
    initial,
    cancelAllowed: true,
  };
}

export function runOnChainState(
  req: ExitReq,
  stage: ExitStage
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
export async function runExit(
  api: Pick<SignerApi, 'exit'>,
  setState: (state: State) => void,
  quote: ExitQuoteResp
): Promise<void> {
  const req: ExitReq = {
    quote,
    onStage,
  };

  function onStage(stage: ExitStage) {
    setState(runOnChainState(req, stage));
  }

  try {
    await api.exit(req);
  } catch (e) {
    console.error(e);
    setState(
      formState({
        amount: req.quote.exitAmount,
        toAsset: req.quote.to,
      })
    );
  }
}
