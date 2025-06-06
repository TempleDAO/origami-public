import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.CORE.TOKEN_PRICES.V4 = '0x787c6666213624D788522d516847978D7F348902';
  addrs.VAULTS.hOHM.OVERLORD_WALLET = addrs.CORE.MULTISIG;
  addrs.VAULTS.hOHM.TOKEN = '0x10d16E2A026C4b5264A2aAC51cA65749cDf2037E';
  addrs.VAULTS.hOHM.MANAGER = '0xAf7868a9BB72E16B930D50636519038d7F057470';
  addrs.VAULTS.hOHM.SWEEP_SWAPPER = '0x4B7099FD879435a087C364aD2f9E7B3f94d20bBe';
  addrs.VAULTS.hOHM.TELEPORTER = '0x99aA73dA6309b8eC484eF2C95e96C131C1BBF7a0';
  return addrs;
}
