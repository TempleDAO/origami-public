import { useState } from 'react';

export interface FlowState<C, S> {
  ctx: C;
  state: S;
  setState(state: S): void;
}

export function useFlowState<C, S>(ctx: C, initial: () => S): FlowState<C, S> {
  const [state, setState] = useState<S>(initial);
  return {
    ctx,
    state,
    setState,
  };
}
