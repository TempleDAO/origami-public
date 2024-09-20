import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.SUSDSpS = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    COW_SWAPPER: '0x1966dc8ff30Bc4AeDEd27178642253b3cCC9AA3f',
    TOKEN: '0x5f58879Fe3a4330B6D85c1015971Ea6e5175AeDD',
    MANAGER: '0x582957C7a35CDfeAAD1Ca4b87AE03913eAAd0Be0',
  };
  
  return addrs;
}
