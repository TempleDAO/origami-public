import type { FC } from 'react';

import styled from 'styled-components';
import breakpoints from '@/styles/responsive-breakpoints';
import { Loading, isReady, lmap } from '@/utils/loading-value';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { formatDecimalBigNumber } from '@/utils/formatNumber';
import { LoadingText } from './LoadingText';

export type FiledDbnProps = {
  value: string;
  onChange(value: string): void;
  decimals?: number;
  maxLabel?: string;
  max?: Loading<DecimalBigNumber>;
  className?: string;
  disabled?: boolean;
  error?: boolean;
  autoFocus?: boolean;
};

export const FieldDbn: FC<FiledDbnProps> = ({
  error,
  max,
  decimals,
  maxLabel = 'MAX',
  onChange,
  value,
  className,
  disabled,
  autoFocus,
}) => {
  const handleInput = (event: React.FormEvent<HTMLInputElement>) => {
    const val = event.currentTarget.value;

    if (val === '.') {
      onChange('0.');
      return;
    }

    // We need this extra validation here to catch multiple, or ending, dots
    const lastPeriodIndex = val.lastIndexOf('.');
    const multiplePeriods = val.indexOf('.') != lastPeriodIndex;

    // Ignore multiple periods
    if (multiplePeriods) {
      event.preventDefault();
      return;
    }

    // Ignore changes that create too many decimal places
    if (lastPeriodIndex >= 0) {
      const fractionalDecimals = val.length - lastPeriodIndex - 1;
      if (decimals != undefined && decimals < fractionalDecimals) {
        event.preventDefault();
        return;
      }
    }

    onChange(val);
  };

  const maxStr = max && lmap(max, formatDecimalBigNumber);

  return (
    <InputBox className={className} error={error}>
      {!maxStr || !max ? null : (
        <MaxButton
          onClick={() => {
            isReady(max) && onChange(max.value.formatUnits());
          }}
        >
          {maxLabel && <Description>{maxLabel}</Description>}
          <LoadingText value={maxStr} />
        </MaxButton>
      )}
      <StyledInput
        autoFocus={autoFocus}
        onChange={handleInput}
        placeholder="0.00"
        value={value}
        onKeyPress={numbersOnly}
        disabled={disabled}
      />
    </InputBox>
  );
};

const InputBox = styled.div<{ error?: boolean }>`
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  max-width: 75rem;
  min-width: 15rem;
  box-sizing: border-box;
  padding: 1rem 0.8rem;
  background-color: ${({ theme }) => theme.colors.bgMid};
  border-radius: 8px;
  border: 2px solid ${({ theme }) => theme.colors.greyDark};

  ${breakpoints.sm(`
    flex-direction: row;
    align-items: center;
  `)}

  &:focus-within {
    border: 2px solid white;
  }

  ${({ error, theme }) =>
    error &&
    `
      outline: 2px solid ${theme.colors.error};
    `}
`;

const StyledInput = styled.input.attrs(() => ({
  type: 'text',
  inputmode: 'numeric',
}))`
  padding: 0;
  font-size: 1.5rem;
  line-height: 1.5rem;
  font-weight: 700;
  color: ${({ theme }) => theme.colors.white};
  background-color: ${({ theme }) => theme.colors.bgMid};
  width: 100%;
  text-align: right;
  flex-grow: 1;
  overflow: hidden;
  border: none;
  outline: none;
`;

const Description = styled.p`
  margin: 0;
  display: inline;
  font-weight: 700;
  margin-right: 0.5rem;
  text-decoration: underline;
  color: ${({ theme }) => theme.colors.white};
`;

const MaxButton = styled.div`
  display: flex;
  align-items: center;
  cursor: pointer;
  font-size: 0.8rem;
  min-width: max-content;

  ${breakpoints.sm(`
    align-items: center;
  `)}

  ${breakpoints.lg(`
    font-size: 1rem;
  `)}
`;

//@ts-ignore
const numbersOnly = (event) => {
  if (!/\.|\d/.test(event.key)) {
    event.preventDefault();
  }
};

export const StyledFieldDbn = styled(FieldDbn)`
  ${({ error }) => error && `margin-bottom: 0.5rem;`}
`;
