import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.CORE.TOKEN_PRICES.V5 = '0xc6e7DF5E7b4f2A278906862b61205850344D4e7d';

  return addrs;
}
