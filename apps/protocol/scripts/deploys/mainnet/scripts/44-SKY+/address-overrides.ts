import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.SKYp.OVERLORD_WALLET = addrs.CORE.MULTISIG;
  addrs.VAULTS.SKYp.COW_SWAPPER = '0x2fcc261bB32262a150E4905F6d550D4FF05bC582';
  addrs.VAULTS.SKYp.COW_SWAPPER_2 = '0x2fcc261bB32262a150E4905F6d550D4FF05bC582';
  addrs.VAULTS.SKYp.COW_SWAPPER_3 = '0x2fcc261bB32262a150E4905F6d550D4FF05bC582';
  addrs.VAULTS.SKYp.TOKEN.address = '0x5E50A3d48982Ba8CCAfE398FB0f8881A31C4f67a';
  addrs.VAULTS.SKYp.MANAGER = '0x63eE8865A8B25919B5103d02586AaaF078Ee9102';

  return addrs;
}
