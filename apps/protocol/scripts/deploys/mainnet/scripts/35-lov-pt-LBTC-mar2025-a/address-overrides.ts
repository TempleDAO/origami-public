import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
    addrs.ORACLES.PT_LBTC_MAR_2025_LBTC = "0x205Cfc23ef26922E116135500abb4B12Ab6d4668";

    addrs.LOV_PT_LBTC_MAR_2025_A.OVERLORD_WALLET = addrs.CORE.MULTISIG;
    addrs.LOV_PT_LBTC_MAR_2025_A.MORPHO_BORROW_LEND = "0xbB57FE325e769DEDB1236525a91cDEd842143fA7";
    addrs.LOV_PT_LBTC_MAR_2025_A.TOKEN="0xD69BC314bdaa329EB18F36E4897D96A3A48C3eeF";
    addrs.LOV_PT_LBTC_MAR_2025_A.MANAGER="0x6712008CCD96751d586FdBa0DEf5495E0E22D904";

    return addrs;
}
