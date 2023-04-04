import { ProviderApi } from '@/api/api';
import {
  ChainId,
  ContractAddress,
  Investment,
  Token,
  TokenConfig,
  TokenOrNative,
} from '@/api/types';
import { BigNumber } from 'ethers';
import { DecimalBigNumber } from './decimal-big-number';
import { formatDecimalBigNumber } from './formatNumber';
import { tokenLabelMap } from '@/config';

export function newToken(
  symbol: string,
  iconName: string,
  decimals: number,
  config: TokenConfig
): Token {
  return {
    symbol,
    iconName,
    decimals,
    parseUnits: (s: string) => DecimalBigNumber.parseUnits(s, decimals),
    formatUnits: (v: DecimalBigNumber) => v.formatUnits(decimals),
    formatLocale: (v: DecimalBigNumber) => formatDecimalBigNumber(v),
    fromBN: (v: BigNumber) => DecimalBigNumber.fromBN(v, decimals),
    toBN: (v: DecimalBigNumber) => v.toBN(decimals),
    config,
  };
}

export function tokenOrNativeSymbol(ofAsset: TokenOrNative): string {
  switch (ofAsset.kind) {
    case 'native':
      return ofAsset.chain.nativeCurrency.symbol;
    case 'token': {
      return ofAsset.token.symbol;
    }
  }
}

export function tokenOrNativeLabel(ofAsset: TokenOrNative): string {
  const symbol = tokenOrNativeSymbol(ofAsset);
  return tokenLabelMap[symbol] || symbol;
}

export async function tokenOrNativeUsdPrice(
  providerApi: Pick<ProviderApi, 'getNativeUsdPrice' | 'getTokenUsdPrice'>,
  investFrom: TokenOrNative
): Promise<DecimalBigNumber> {
  if (investFrom.kind == 'native') {
    return providerApi.getNativeUsdPrice(investFrom.chain.id);
  } else {
    return providerApi.getTokenUsdPrice(investFrom.token);
  }
}

export async function tokenOrNativeAvailableBalance(
  providerApi: Pick<ProviderApi, 'getNativeBalance' | 'getTokenUsdPrice'>,
  investFrom: TokenOrNative,
  address: string
): Promise<DecimalBigNumber> {
  if (investFrom.kind == 'native') {
    return providerApi.getNativeBalance(investFrom.chain.id, address);
  } else {
    return providerApi.getTokenUsdPrice(investFrom.token);
  }
}

export function tokenOrNativeAmountDecimals(from: TokenOrNative): number {
  if (from.kind === 'native') {
    return from.chain.nativeCurrency.decimals;
  } else {
    return from.token.decimals;
  }
}

/// unique string key for a ChainId
export function chainIdKey(id: ChainId): string {
  return '' + id;
}

/// unique string key for a token
export function tokenKey(t: Token): string {
  return contractAddressKey(t.config);
}

/// unique string key for a token
export function contractAddressKey(ca: ContractAddress): string {
  return ca.address + '/' + ca.chainId;
}

/// unique string key for an investment
export function investmentKey(i: Investment): string {
  return i.contractAddress.address + '/' + i.contractAddress.chainId;
}

/// unique string key for an investment, where sorting by chain name and investment
/// name is important
export function investmentKeyByName(i: Investment): string {
  return (
    i.chain.name +
    '/' +
    i.chain.id +
    '/' +
    i.name +
    '/' +
    i.contractAddress.address
  );
}
