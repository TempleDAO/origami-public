import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
    addrs.CORE.TOKEN_PRICES.V4 = "0x2D2c64cC0d2f194FAD74bbE453edAA181d8FBd1f";
    addrs.VAULTS.hOHM.TOKEN = "0x9341E3e0E4056CC9C299220931c0214bafeA907a";
    addrs.VAULTS.hOHM.MANAGER = "0xDe4dE2De1C9f7a5d527bD09CD50ef6E4d072cE91";
    addrs.VAULTS.hOHM.SWEEP_SWAPPER = "0xbE91B08822c022E4d9238c20c8Fee3b5e9c209d3";
    addrs.VAULTS.hOHM.DUMMY_DEX_ROUTER = "0x39d88cF0B7d15A7C0DE4ad7897a9b8763314d3eC";
    addrs.VAULTS.hOHM.TELEPORTER = "0xAe1C15F7189160872a5C4BC51054727df6b6EC4b";

    return addrs;
}
