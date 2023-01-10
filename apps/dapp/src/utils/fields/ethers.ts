import { formatUnits, parseUnits } from 'ethers/lib/utils';
import { BigNumber } from 'ethers';

import { regexStringFieldFns } from './primitive';
import { FieldFns } from './type';
import { DecimalBigNumber } from '../decimal-big-number';

/**
 * A validated field for editing a ethereum hex address
 */
export const ETH_ADDRESS_FIELD = regexStringFieldFns(
  '^\\s*(0x[0-9a-fA-F]{40})\\s*$', // trims whitespace
  'an eth hex address',
  1 //  group 1 from the regexp match
);

/**
 * A validated field for editing an erc20 token amount with the
 * specified number of decimals.
 */
export function tokenAmountField(decimals: number): FieldFns<BigNumber> {
  const re = new RegExp('^([0-9]*[.])?[0-9]+$');

  return {
    toText(v: BigNumber) {
      return formatUnits(v, decimals);
    },
    validate(text: string) {
      if (!text.match(re)) {
        return 'must be a number';
      } else {
        return null;
      }
    },
    fromText(text) {
      return parseUnits(text, decimals);
    },
    equals(v1, v2) {
      return v1 === v2;
    },
  };
}

/**
 * A validated field for editing an erc20 token amount with the
 * specified number of decimals.
 */
export function decimalBigNumberField(
  decimals: number
): FieldFns<DecimalBigNumber> {
  const re = new RegExp('^([0-9]*[.])?[0-9]+$');

  return {
    toText(v: DecimalBigNumber) {
      return v.formatUnits(decimals);
    },
    validate(text: string) {
      if (!text.match(re)) {
        return 'must be a number';
      } else {
        return null;
      }
    },
    fromText(text) {
      return DecimalBigNumber.parseUnits(text, decimals);
    },
    equals(v1, v2) {
      return v1 === v2;
    },
  };
}
