import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.PT_CORN_LBTC_DEC24_LBTC = '0x3CA5269B5c54d4C807Ca0dF7EeB2CB7a5327E77d';
  addrs.FLASHLOAN_PROVIDERS.ZEROLEND_MAINNET_BTC = '0x9581c795DBcaf408E477F6f1908a41BE43093122';
  addrs.LOV_PT_CORN_LBTC_DEC24_A.OVERLORD_WALLET = '0x781B4c57100738095222bd92D37B07ed034AB696';
  addrs.LOV_PT_CORN_LBTC_DEC24_A.TOKEN = '0x8a6E9a8E0bB561f8cdAb1619ECc4585aaF126D73';
  addrs.LOV_PT_CORN_LBTC_DEC24_A.ZEROLEND_BORROW_LEND = '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec';
  addrs.LOV_PT_CORN_LBTC_DEC24_A.MANAGER = '0x492844c46CEf2d751433739fc3409B7A4a5ba9A7';
  return addrs;
}
