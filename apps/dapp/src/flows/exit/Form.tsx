import type { FC } from 'react';
import type { Chain } from '@wagmi/core';
import type { ExitQuoteResp } from '@/api/api';
import type { FormState, State, Ctx } from './types';

import { useState, useId } from 'react';
import styled from 'styled-components';
import { useDebounce } from 'use-debounce';
import { Button } from '@/components/commons/Button';
import { Select } from '@/components/commons/Select';
import { Icon } from '@/components/commons/Icon';
import { LoadingText } from '@/components/commons/LoadingText';
import { isReady, lmap, loading, ready } from '@/utils/loading-value';
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
import { tokenOrNativeUsdPrice } from '@/utils/api-utils';
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

  const exitToOptions = ctx.acceptedTokens.map((token) =>
    exitOption(investment.chain, token)
  );

  const [exitUsdPrice] = useAsyncLoad(async () => {
    return tokenOrNativeUsdPrice(papi, exitTo);
  }, [papi, investment.chain, exitTo]);

  const exitUsdValue = lmap(
    exitUsdPrice,
    (price) => debouncedExitAmount && debouncedExitAmount.mul(price)
  );

  const [quote] = useAsyncResult(
    loading<ExitQuoteResp>(),
    async () => {
      if (!debouncedExitAmount) {
        return loading();
      }
      const quote = await papi.exitQuote({
        investment: investment,
        receiptTokenAmount: debouncedExitAmount,
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
      const slippageBps = options.slippageTolerance * 10000;
      runExit(sapi, setState, quote.value, slippageBps);
    }
  }

  const exitToStr =
    exitTo.kind == 'token'
      ? exitTo.token.symbol
      : investment.chain.nativeCurrency.name;

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
          <Label>Token to receive:</Label>
          <Select
            id={selectId}
            instanceId={selectId}
            options={exitToOptions}
            value={exitOption(investment.chain, exitTo)}
            onChange={(newOption) =>
              newOption && setExitTo((newOption as InvestOption).value)
            }
          />
        </FlexRightSpaced>
      </FlexDown>

      <FlexDown>
        <Label>Amount to swap:</Label>
        <FlexRightSpaced>
          <FieldDbn
            value={exitAmountState.text}
            onChange={exitAmountState.setText}
            max={availableBalance}
            maxLabel="MAX"
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
                value={lmap(quote, (q) => formatDecimalBigNumber(q.toAmount))}
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
              value={lmap(exitUsdValue, (v) =>
                v ? formatDecimalBigNumber(v) : ''
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

function exitOption(chain: Chain, value: TokenOrNative): InvestOption {
  const label =
    value.kind == 'native' ? chain.nativeCurrency.symbol : value.token.symbol;
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

const Label = styled.div`
  ${textP1}
  color: ${({ theme }) => theme.colors.white};
  margin-bottom: 0.5rem;
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
