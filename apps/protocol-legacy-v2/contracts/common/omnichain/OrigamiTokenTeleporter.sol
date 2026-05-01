pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/omnichain/OrigamiTokenTeleporter.sol)

import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/OFTAdapter.sol";
import { OrigamiOftElevatedAccess } from "contracts/common/access/OrigamiOftElevatedAccess.sol";

/**
 * @title Origami OFT Adapter
 * @dev A vanilla LayerZero OFTAdapter, but with OrigamiElevatedAccess for admin permissions
 * The inner token will be locked/escrowed -- not minted/burned on demand.
 */
contract OrigamiTokenTeleporter is
    OFTAdapter,
    OrigamiOftElevatedAccess
{
    constructor(
        address initialOwner_, 
        address innerToken_, 
        address lzEndpoint_, 
        address delegate_
    ) 
        OFTAdapter(innerToken_, lzEndpoint_, delegate_)
        OrigamiOftElevatedAccess(initialOwner_)
    {}
}
