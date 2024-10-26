import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.MKR_DAI = '0x645D817611E0CDaF9cD43332c4E369B9E333471d';
  addrs.LOV_MKR_DAI_LONG_A = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    SPARK_BORROW_LEND: '0x0b5dcAf621a877dAcF3C540c1e5208C8a3eb7B23',
    TOKEN: '0x81F82957608f74441E085851cA5Cc091b23d17A2',
    MANAGER: '0x9a8164cA007ff0899140719E9aEC9a9C889CbF1E',
  };
  
  return addrs;
}
