import React from 'react';

import { FieldDbn } from './FieldDbn';
import { loading, ready } from '@/utils/loading-value';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { useTypedFieldState } from '@/utils/fields/hooks';
import { decimalBigNumberField } from '@/utils/fields/ethers';

export default {
  title: 'Components/Commons/FieldDBN',
  component: FieldDbn,
};

export const Basic = () => {
  const decimals = 6;
  const field = useTypedFieldState(decimalBigNumberField(decimals));
  return (
    <FieldDbn
      decimals={decimals}
      value={field.text}
      onChange={field.setText}
      max={ready(DecimalBigNumber.parseUnits('100', decimals))}
    />
  );
};

export const WithExtraMaxDecimals = () => {
  const decimals = 6;
  const field = useTypedFieldState(decimalBigNumberField(decimals));
  return (
    <FieldDbn
      decimals={decimals}
      value={field.text}
      onChange={field.setText}
      max={ready(DecimalBigNumber.parseUnits('100.000042', decimals))}
    />
  );
};

export const Loading = () => {
  const decimals = 6;
  const field = useTypedFieldState(decimalBigNumberField(decimals));
  return (
    <FieldDbn
      decimals={decimals}
      value={field.text}
      onChange={field.setText}
      max={loading()}
    />
  );
};

export const Error = () => {
  const decimals = 6;
  const field = useTypedFieldState(decimalBigNumberField(decimals));
  return (
    <FieldDbn
      decimals={decimals}
      value={field.text}
      onChange={field.setText}
      max={ready(DecimalBigNumber.parseUnits('100.000001', decimals))}
      error={true}
    />
  );
};
