import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.WETH_CBBTC = '0x8a6E9a8E0bB561f8cdAb1619ECc4585aaF126D73';
  addrs.LOV_WETH_CBBTC_LONG_A.OVERLORD_WALLET = '0xfa5496e089b2d171a01ec822b3a6afd26ce8831e';
  addrs.LOV_WETH_CBBTC_LONG_A.TOKEN = '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec';
  addrs.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND = '0x492844c46CEf2d751433739fc3409B7A4a5ba9A7';
  addrs.LOV_WETH_CBBTC_LONG_A.MANAGER = '0x50cf1849e32E6A17bBFF6B1Aa8b1F7B479Ad6C12';
  return addrs;
}
