import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
    addrs.ORACLES.SKY_MKR = "0x205Cfc23ef26922E116135500abb4B12Ab6d4668";
    addrs.ORACLES.MKR_USDS = "0xbB57FE325e769DEDB1236525a91cDEd842143fA7";
    addrs.ORACLES.SKY_USDS = "0xD69BC314bdaa329EB18F36E4897D96A3A48C3eeF";

    addrs.VAULTS.SUSDSpS.COW_SWAPPER_2 = "0x6712008CCD96751d586FdBa0DEf5495E0E22D904";

    return addrs;
}
