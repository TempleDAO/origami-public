import { BigDecimal, BigInt, Bytes } from '@graphprotocol/graph-ts';


export const BIG_INT_1E18 = BigInt.fromString('1000000000000000000');
export const BIG_INT_1E7 = BigInt.fromString('10000000');
export const BIG_INT_0 = BigInt.fromI32(0);
export const BIG_INT_1 = BigInt.fromI32(1);
export const CACHE_INTERVAL = BigInt.fromI32(600); // 10 minutes

export const BIG_DECIMAL_1E18 = BigDecimal.fromString('1e18');
export const BIG_DECIMAL_1E8 = BigDecimal.fromString('1e8');
export const BIG_DECIMAL_1E7 = BigDecimal.fromString('1e7');
export const BIG_DECIMAL_365 = BigDecimal.fromString('365');
export const BIG_DECIMAL_100 = BigDecimal.fromString('100');
export const BIG_DECIMAL_1 = BigDecimal.fromString('1');
export const BIG_DECIMAL_0 = BigDecimal.fromString('0');
export const BIG_DECIMAL_YEAR = BigDecimal.fromString('31536000');

export const OWNER = '0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165'
export const TOKEN_PRICES = Bytes.fromHexString('0x303125ce3d60c9b6c4ca3d6f034ad4ceede708b3')
