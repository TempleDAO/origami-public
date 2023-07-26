import { BigDecimal, BigInt } from '@graphprotocol/graph-ts';

import { BIG_DECIMAL_1, BIG_INT_0, BIG_INT_1 } from './constants';

export const DEFAULT_DECIMALS = 18;

export function pow(base: BigDecimal, exponent: number): BigDecimal {
  let result = base;

  if (exponent == 0) {
    return BigDecimal.fromString('1');
  }

  for (let i = 2; i <= exponent; i++) {
    result = result.times(base);
  }

  return result;
}

export function toDecimal(
  value: BigInt,
  decimals: number = DEFAULT_DECIMALS,
): BigDecimal {
  let precision = BigInt.fromI32(10)
    .pow(<u8>decimals)
    .toBigDecimal();

  return value.divDecimal(precision);
}

export function ipow(base: BigDecimal, exp: number): BigDecimal {
  let biExp = BigInt.fromI32(<i32>exp)
  let result = BIG_DECIMAL_1;
  while (biExp.sqrt() > BIG_INT_0) {
    if (biExp.bitAnd(BIG_INT_1) != BIG_INT_0) {
      result = result.times(base);
    }
    biExp = biExp.rightShift(1);
    base = base.times(base);
  }
  return result;
}
