import { DecimalBigNumber } from './decimal-big-number';

export type Equals<T> = (v1: T, v2: T) => boolean;
export type Compare<T> = (v1: T, v2: T) => number;

export function cmpPrim<T>(v1: T, v2: T): number {
  if (v1 < v2) {
    return -1;
  } else if (v2 < v1) {
    return 1;
  }
  return 0;
}

export function cmpRev<T>(cfn: Compare<T>): Compare<T> {
  return (v1, v2) => -cfn(v1, v2);
}

export function cmp2<T>(cfn1: Compare<T>, cfn2: Compare<T>): Compare<T> {
  return (v1, v2) => {
    const c1 = cfn1(v1, v2);
    if (c1 !== 0) {
      return c1;
    }
    return cfn2(v1, v2);
  };
}

export function cmpDecimalBigNumber(
  v1: DecimalBigNumber,
  v2: DecimalBigNumber
) {
  if (v1.lt(v2)) {
    return -1;
  } else if (v2.lt(v1)) {
    return 1;
  }
  return 0;
}

export function cmpU<T>(cfn: Compare<T>): Compare<T | undefined> {
  return (v1: T | undefined, v2: T | undefined) => {
    if (v1 !== undefined && v2 !== undefined) {
      return cfn(v1, v2);
    }
    if (v1 === undefined && v2 !== undefined) {
      return -1;
    }
    if (v1 !== undefined && v2 === undefined) {
      return 1;
    }
    return 0;
  };
}

export function equals<T>(cfn: Compare<T>): Equals<T> {
  return (v1, v2) => {
    return cfn(v1, v2) === 0;
  };
}
