import { ProviderApi, SignerApi } from '@/api/api';
import { Investment, TokenOrNative } from '@/api/types';
import { RightPanelOverlay } from '@/components/commons/RightPanelOverlay';
import { ApiCache } from '@/api/cache';
import { FlowState } from '@/hooks/use-flow-state';
import { FC, useState } from 'react';
import styled from 'styled-components';
import { Form } from './Form';
import { Run } from './Run';
import { State, Ctx, start } from './types';

export type FlowProps = FlowState<Ctx, State>;

export const FlowView: FC<FlowProps> = (props) => {
  switch (props.state.kind) {
    case 'form':
      return (
        <Form ctx={props.ctx} state={props.state} setState={props.setState} />
      );
    case 'run':
      return (
        <Run ctx={props.ctx} state={props.state} setState={props.setState} />
      );
  }
};

interface FlowOverlayProps {
  investment: Investment;
  acceptedTokens: TokenOrNative[];
  papi: ProviderApi;
  sapi: SignerApi;
  cache: ApiCache;
  hidePanel(): void;
}

export function FlowOverlay(props: FlowOverlayProps): JSX.Element {
  const [state, setState] = useState<State>(start);
  return (
    <RightPanelOverlay
      hidePanel={props.hidePanel}
      enableContextDismiss={state.cancelAllowed}
      maxWidthRem={70}
      Content={({ startDismiss }) => {
        const ctx = {
          ...props,
          onDone: () => {
            props.cache.refreshBalances();
            startDismiss();
          },
        };
        return (
          <FlowContainer>
            <FlowView ctx={ctx} state={state} setState={setState} />
          </FlowContainer>
        );
      }}
    />
  );
}

const FlowContainer = styled.div`
  margin: 20px;
`;
