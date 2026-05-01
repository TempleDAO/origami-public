import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.SKYp.REWARDS_HARVESTER = '0xBFf03dF70F0da9A31B775cba6A338B9BC6d7991b';
  return addrs;
}
