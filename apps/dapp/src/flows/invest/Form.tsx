import type { FC } from 'react';
import type { Chain } from '@wagmi/core';
import type { InvestQuoteResp } from '@/api/api';
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
import { runInvest } from './types';

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
  const [investFrom, setInvestFrom] = useState<TokenOrNative>(
    ctx.acceptedTokens[0]
  );
  const signerAddress = sapi.signerAddress;

  const options = useAdvancedOptionsState();

  const [availableBalance] = useAsyncLoad(async () => {
    if (investFrom.kind == 'native') {
      return papi.getNativeBalance(investment.chain.id, signerAddress);
    } else {
      return papi.getTokenBalance(investFrom.token, signerAddress);
    }
  }, [papi, ctx, investFrom, signerAddress]);

  const amountDecimals =
    investFrom.kind == 'native' ? 18 : investFrom.token.decimals;
  const investAmountState = useTypedFieldState(
    decimalBigNumberField(amountDecimals)
  );
  const investAmount = investAmountState.isValid()
    ? investAmountState.value()
    : undefined;
  const [debouncedInvestAmount] = useDebounce(investAmount, 500, {
    equalityFn: equals(cmpU(cmpDecimalBigNumber)),
  });

  const investFromOptions = ctx.acceptedTokens.map((token) =>
    investOption(investment.chain, token)
  );

  const [investUsdPrice] = useAsyncLoad(async () => {
    return tokenOrNativeUsdPrice(papi, investFrom);
  }, [papi, investment.chain, investFrom]);

  const investUsdValue = lmap(
    investUsdPrice,
    (price) => debouncedInvestAmount && debouncedInvestAmount.mul(price)
  );
  const receiptToken = investment.receiptToken;

  const [quote] = useAsyncResult(
    loading<InvestQuoteResp>(),
    async () => {
      if (!debouncedInvestAmount) {
        return loading();
      }
      const quote = await papi.investQuote({
        investment: investment,
        from: investFrom,
        amount: debouncedInvestAmount,
      });
      return ready(quote);
    },
    [papi, debouncedInvestAmount, investFrom, investment]
  );

  const canConfirm =
    investAmount &&
    isReady(availableBalance) &&
    investAmount.lte(availableBalance.value) &&
    isReady(quote);

  async function onConfirm() {
    if (canConfirm) {
      const slippageBps = options.slippageTolerance * 10000;
      runInvest(sapi, setState, quote.value, slippageBps);
    }
  }

  return (
    <FlexDownSpaced>
      <Title>INVEST</Title>

      <P>
        Invest with <EM>{investment.supportedAssetsDescription}</EM> and receive{' '}
        <EM>{receiptToken.symbol}</EM>.
      </P>

      <FlexDown>
        <Label>Investing in:</Label>
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
        <Label>Amount to invest:</Label>
        <FlexRightSpaced>
          <FieldDbn
            autoFocus
            value={investAmountState.text}
            onChange={investAmountState.setText}
            max={availableBalance}
            maxLabel="MAX"
          />
          <div>
            <InvestTokenSelect
              id={selectId}
              instanceId={selectId}
              options={investFromOptions}
              value={investOption(investment.chain, investFrom)}
              onChange={(newOption) =>
                newOption && setInvestFrom((newOption as InvestOption).value)
              }
            />
          </div>
        </FlexRightSpaced>
      </FlexDown>

      <AdvancedOptions {...options} />

      <HR />

      <Label>You will receive:</Label>
      <FlexDown>
        <FontLarger>
          <SpanH2>
            {investAmountState.isModified() ? (
              <LoadingText
                value={lmap(quote, (q) =>
                  formatDecimalBigNumber(q.receiptTokenAmount)
                )}
              />
            ) : (
              0
            )}
          </SpanH2>
          &nbsp;{receiptToken.symbol}
        </FontLarger>
        <div>
          {investAmountState.isModified() ? (
            <LoadingText
              value={lmap(investUsdValue, (v) =>
                v ? formatDecimalBigNumber(v) : ''
              )}
            />
          ) : (
            0
          )}{' '}
          USD
        </div>
        <div>(Estimated)</div>
      </FlexDown>
      <Button label="Confirm" onClick={onConfirm} disabled={!canConfirm} />
    </FlexDownSpaced>
  );
};

interface InvestOption {
  label: string;
  value: TokenOrNative;
}

function investOption(chain: Chain, value: TokenOrNative): InvestOption {
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

const InvestTokenSelect = styled(Select)`
  width: 110px;
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
