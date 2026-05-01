import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.ORIBGT_WBERA_PEGGED = '0x3711f9F830e03Bd098F3fB9003BB54bFDdfa0C54';
  return addrs;
}
