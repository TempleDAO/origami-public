import type { FC } from 'react';
import type { ExitQuoteResp } from '@/api/api';
import type { FormState, State, Ctx } from './types';

import { useState, useId } from 'react';
import styled from 'styled-components';
import { useDebounce } from 'use-debounce';
import { Button } from '@/components/commons/Button';
import { Select } from '@/components/commons/Select';
import { Icon } from '@/components/commons/Icon';
import { LoadingText } from '@/components/commons/LoadingText';
import { isReady, lmap, lmap2, loading, ready } from '@/utils/loading-value';
import { useAsyncLoad, useAsyncResult } from '@/hooks/use-async-result';
import { runExit } from './types';

import {
  AdvancedOptions,
  useAdvancedOptionsState,
} from '@/components/AdvancedOptions';

import { formatDecimalBigNumber } from '@/utils/formatNumber';
import {
  textH1,
  textH2,
  textH3,
  textP1,
  textP2,
} from '@/styles/mixins/text-styles';
import { TokenOrNative } from '@/api/types';
import { decimalBigNumberField } from '@/utils/fields/ethers';
import { useTypedFieldState } from '@/utils/fields/hooks';
import { FieldDbn } from '@/components/commons/FieldDbn';
import { tokenOrNativeLabel, tokenOrNativeUsdPrice } from '@/utils/api-utils';
import { cmpDecimalBigNumber, cmpU, equals } from '@/utils/compare';

type FormProps = {
  ctx: Ctx;
  state: FormState;
  setState(s: State): void;
};

export const Form: FC<FormProps> = ({ ctx, setState }) => {
  const { papi, sapi, investment } = ctx;

  const selectId = useId();
  const [exitTo, setExitTo] = useState<TokenOrNative>(ctx.acceptedTokens[0]);
  const signerAddress = sapi.signerAddress;

  const options = useAdvancedOptionsState();

  const [availableBalance] = useAsyncLoad(async () => {
    return papi.getTokenBalance(investment.receiptToken, signerAddress);
  }, [papi, ctx, investment, signerAddress]);

  const exitAmountState = useTypedFieldState(
    decimalBigNumberField(investment.receiptToken.decimals)
  );
  const exitAmount = exitAmountState.isValid()
    ? exitAmountState.value()
    : undefined;
  const [debouncedExitAmount] = useDebounce(exitAmount, 500, {
    equalityFn: equals(cmpU(cmpDecimalBigNumber)),
  });

  const exitToOptions = ctx.acceptedTokens.map((token) => exitOption(token));

  const [exitUsdPrice] = useAsyncLoad(async () => {
    return tokenOrNativeUsdPrice(papi, exitTo);
  }, [papi, investment.chain, exitTo]);

  const [quote] = useAsyncResult(
    loading<ExitQuoteResp>(),
    async () => {
      if (!debouncedExitAmount) {
        return loading();
      }
      const quote = await papi.exitQuote({
        investment: investment,
        exitAmount: debouncedExitAmount,
        slippageBps: options.slippageTolerance * 10000,
        deadline: 0,
        to: exitTo,
      });
      return ready(quote);
    },
    [papi, debouncedExitAmount, exitTo, investment]
  );

  const canConfirm =
    exitAmount &&
    isReady(availableBalance) &&
    exitAmount.lte(availableBalance.value) &&
    isReady(quote);

  async function onConfirm() {
    if (canConfirm) {
      runExit(sapi, setState, quote.value);
    }
  }

  const exitToStr = tokenOrNativeLabel(exitTo);

  return (
    <FlexDownSpaced>
      <Title>EXIT</Title>

      <P>
        Exit <EM>{investment.receiptToken.symbol}</EM> to receive{' '}
        <EM>{investment.supportedAssetsDescription}</EM>.
      </P>

      <FlexDown>
        <Label>Exiting from:</Label>
        <FlexRightSpaced>
          <Icon iconName={investment.icon} hasBackground />
          <FlexDown>
            <LPName>{investment.name}</LPName>
            <LPDescription>
              {investment.description.toUpperCase()}
            </LPDescription>
          </FlexDown>
        </FlexRightSpaced>
      </FlexDown>

      <FlexDown>
        <FlexRightSpaced>
          <Label noBottomMargin>Token to receive:</Label>
          <Select
            id={selectId}
            instanceId={selectId}
            options={exitToOptions}
            value={exitOption(exitTo)}
            onChange={(newOption) =>
              newOption && setExitTo((newOption as InvestOption).value)
            }
          />
        </FlexRightSpaced>
      </FlexDown>

      <FlexDown>
        <Label>Amount to exit:</Label>
        <FlexRightSpaced>
          <FieldDbn
            value={exitAmountState.text}
            onChange={exitAmountState.setText}
            max={availableBalance}
          />
        </FlexRightSpaced>
      </FlexDown>

      <AdvancedOptions {...options} />

      <HR />

      <Label>You will receive:</Label>
      <FlexDown>
        <FontLarger>
          <SpanH2>
            {exitAmountState.isModified() ? (
              <LoadingText
                value={lmap(quote, (q) =>
                  formatDecimalBigNumber(q.expectedToAmount)
                )}
              />
            ) : (
              0
            )}
          </SpanH2>
          &nbsp;{exitToStr}
        </FontLarger>
        <div>
          {exitAmountState.isModified() ? (
            <LoadingText
              value={lmap2([quote, exitUsdPrice], (q, p) =>
                formatDecimalBigNumber(q.expectedToAmount.mul(p))
              )}
            />
          ) : (
            0
          )}{' '}
          USD
        </div>
        <div>(estimated)</div>
      </FlexDown>
      <Button label="Confirm" onClick={onConfirm} disabled={!canConfirm} />
    </FlexDownSpaced>
  );
};

interface InvestOption {
  label: string;
  value: TokenOrNative;
}

function exitOption(value: TokenOrNative): InvestOption {
  const label = tokenOrNativeLabel(value);
  return { label, value };
}

const FlexDownSpaced = styled.div`
  color: ${({ theme }) => theme.colors.greyLight};
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 20px;
`;

const FlexDown = styled.div`
  color: ${({ theme }) => theme.colors.greyLight};
  width: 100%;
  display: flex;
  flex-direction: column;
`;

const FlexRightSpaced = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 20px;
`;

export const Title = styled.div`
  ${textH1}
  color: ${(props) => props.theme.colors.white};
`;

const Label = styled.div<{ noBottomMargin?: boolean }>`
  ${textP1}
  color: ${({ theme }) => theme.colors.white};
  ${({ noBottomMargin }) =>
    !noBottomMargin &&
    `
      margin-bottom: 0.5rem;
    `}
`;

const SpanH2 = styled.span`
  ${textH2}
  color: ${(props) => props.theme.colors.white};
`;

const HR = styled.hr`
  width: 100%;
  border: none;
  height: 1px;
  margin: 0px;
  background-color: ${({ theme }) => theme.colors.greyDark};
`;

const LPName = styled.div`
  ${textH3}
  color: ${({ theme }) => theme.colors.white};
`;

const LPDescription = styled.div`
  ${textP1}
  color: ${({ theme }) => theme.colors.greyLight};
`;

const FontLarger = styled.div`
  font-size: 1.1rem;
  font-weight: bold;
`;

const EM = styled.em`
  font-style: normal;
  color: ${({ theme }) => theme.colors.white};
  ${textP2}
`;

const P = styled.p`
  margin-block-start: 0px;
  margin-block-end: 0px;
  margin-top: 0px;
  margin-bottom: 0px;
`;
