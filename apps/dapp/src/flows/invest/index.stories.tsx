import { useMemo } from 'react';
import styled from 'styled-components';
import { FlowView, FlowProps } from '.';
import { noop } from '@/utils/noop';
import {
  arbitrum,
  gmxAcceptedToken,
  gmxInvestment,
  useTestApis,
} from '@/api/test';
import { Form } from './Form';
import { Ctx, formState, runOnChainState, start } from './types';
import { Run } from './Run';
import {
  InvestQuoteResp,
  InvestReq,
  InvestResp,
  InvestStage,
  ProviderApi,
  SignerApi,
} from '@/api/api';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { useFlowState } from '@/hooks/use-flow-state';

export default {
  title: 'Flows/Invest',
  component: FlowView,
};

export const LiveFlow = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);

  const props: FlowProps = useFlowState(ctx, start);

  return (
    <Main>
      <FlowView {...props} />
    </Main>
  );
};

export const FlowFormLoading = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);

  return (
    <Main>
      <Form ctx={ctx} state={formState()} setState={noop} />
    </Main>
  );
};
FlowFormLoading.storyName = '00 Form (Loading)';

export const FlowForm = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);

  return (
    <Main>
      <Form ctx={ctx} state={formState()} setState={noop} />
    </Main>
  );
};
FlowForm.storyName = '01 Form';

export const FlowRunOnChain1 = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);

  const stage: InvestStage = { kind: 'approve' };

  return (
    <Main>
      <Run
        ctx={ctx}
        state={runOnChainState(TEST_INVEST_REQ, stage)}
        setState={noop}
      />
    </Main>
  );
};
FlowRunOnChain1.storyName = '02 Run on chain (approve)';

export const FlowRunOnChain2 = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);

  const stage: InvestStage = {
    kind: 'invest',
  };

  return (
    <Main>
      <Run
        ctx={ctx}
        state={runOnChainState(TEST_INVEST_REQ, stage)}
        setState={noop}
      />
    </Main>
  );
};
FlowRunOnChain2.storyName = '03 Run on chain (invest)';

export const FlowRunOnChain3 = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);
  const stage: InvestStage = {
    kind: 'done',
    result: TEST_INVEST_RESP,
  };

  return (
    <Main>
      <Run
        ctx={ctx}
        state={runOnChainState(TEST_INVEST_REQ, stage)}
        setState={noop}
      />
    </Main>
  );
};
FlowRunOnChain3.storyName = '04 Run on chain (done)';

export const FlowRunOnChain4 = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);
  const stage: InvestStage = {
    kind: 'txfail',
    message: 'something went wrong',
    txhash: '0x123451234567',
  };

  return (
    <Main>
      <Run
        ctx={ctx}
        state={runOnChainState(TEST_INVEST_REQ, stage)}
        setState={noop}
      />
    </Main>
  );
};
FlowRunOnChain4.storyName = '05 Run on chain (fail)';

export const FlowRunOnChain5 = () => {
  const { papi, sapi } = useTestApis();
  const ctx = useTestContext(papi, sapi);
  const stage: InvestStage = {
    kind: 'txfail',
    message:
      'Investmens paused. Origami runs daily operations on the positions to maximise yield, which incurs a 15 minute cooldown',
  };

  return (
    <Main>
      <Run
        ctx={ctx}
        state={runOnChainState(TEST_INVEST_REQ, stage)}
        setState={noop}
      />
    </Main>
  );
};
FlowRunOnChain5.storyName = '06 Run on chain (paused)';

function useTestContext(papi: ProviderApi, sapi: SignerApi): Ctx {
  return useMemo(() => {
    const investment = gmxInvestment();
    const acceptedTokens = gmxAcceptedToken();
    return { investment, acceptedTokens, papi, sapi, onDone: noop };
  }, [papi, sapi]);
}

const TEST_QUOTE: InvestQuoteResp = {
  investment: gmxInvestment(),
  amount: DecimalBigNumber.parseUnits('10', 0),
  from: { kind: 'native', chain: arbitrum() },
  expectedInvestmentAmount: DecimalBigNumber.parseUnits('35.21', 2),
  minInvestmentAmount: DecimalBigNumber.parseUnits('34.15', 2),
  slippageBps: 100,
  deadline: 0,
  feeBps: [],
  encodedQuote: '',
};

const TEST_INVEST_REQ: InvestReq = {
  quote: TEST_QUOTE,
};

const TEST_INVEST_RESP: InvestResp = {
  investTokenAmount: DecimalBigNumber.parseUnits('34.99', 2),
  txHash: '0x123451234567',
};

const Main = styled.main`
  display: flex;
  width: 80%;
  flex-direction: column;
  padding-top: 1rem;
`;
