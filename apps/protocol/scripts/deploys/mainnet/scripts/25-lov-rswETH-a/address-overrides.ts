import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.RSWETH_WETH = '0x8786A226918A4c6Cd7B3463ca200f156C964031f';
  addrs.LOV_RSWETH_A = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    MORPHO_BORROW_LEND: '0x37453c92a0E3C63949ba340ee213c6C97931F96D',
    TOKEN: '0x72aC6A36de2f72BD39e9c782e9db0DCc41FEbfe2',
    MANAGER: '0xAAd4F7BB5FB661181D500829e60010043833a85B',
  };
  
  return addrs;
}
