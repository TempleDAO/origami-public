import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.SUSDSpS.OVERLORD_WALLET = addrs.CORE.MULTISIG;
  addrs.VAULTS.SUSDSpS.COW_SWAPPER = '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec';
  addrs.VAULTS.SUSDSpS.COW_SWAPPER_2 = '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec';
  addrs.VAULTS.SUSDSpS.COW_SWAPPER_3 = '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec';
  addrs.VAULTS.SUSDSpS.COW_SWAPPER_4 = '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec';
  addrs.VAULTS.SUSDSpS.TOKEN.address = '0x492844c46CEf2d751433739fc3409B7A4a5ba9A7';
  addrs.VAULTS.SUSDSpS.MANAGER = '0x50cf1849e32E6A17bBFF6B1Aa8b1F7B479Ad6C12';
  return addrs;
}
