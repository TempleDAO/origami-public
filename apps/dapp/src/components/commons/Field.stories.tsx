import { Field } from './Field';
import styled from 'styled-components';
import { useTypedFieldState } from '@/utils/fields/hooks';
import { NUMBER_FIELD } from '@/utils/fields/primitive';
import {
  decimalBigNumberField,
  ETH_ADDRESS_FIELD,
  tokenAmountField,
} from '@/utils/fields/ethers';
import { Button } from './Button';

export default {
  title: 'Components/Commons/Field',
  component: Field,
};

export function Fields() {
  const numState = useTypedFieldState(NUMBER_FIELD);
  const addrState = useTypedFieldState(ETH_ADDRESS_FIELD);
  const amountState = useTypedFieldState(tokenAmountField(18));
  const dbnState = useTypedFieldState(decimalBigNumberField(18));

  const allvalid =
    numState.isValid() &&
    addrState.isValid() &&
    amountState.isValid() &&
    dbnState.isValid();

  function logValues() {
    console.log(
      'field values',
      numState.value(),
      addrState.value(),
      amountState.value(),
      dbnState.value()
    );
  }

  return (
    <Grid>
      <p>Number:</p>
      <Field state={numState} />
      <p>Eth Address:</p>
      <Field state={addrState} placeholder="0x..." />
      <p>Eth Amount:</p>
      <Field state={amountState} />
      <p>DecimalBigNumber:</p>
      <Field state={dbnState} />
      <Button label="Log values" disabled={!allvalid} onClick={logValues} />
    </Grid>
  );
}

const Grid = styled.div`
  display: grid;
  gap: 20px;
  grid-template-columns: 150px 1fr;
  align-items: center;
`;
