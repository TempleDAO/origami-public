pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/access/OrigamiOftElevatedAccess.sol)

import { OwnableOFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/access/OwnableOFT.sol";
import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @dev A mixin contract in order to be an adapter for the OFT owner access checks (`OwnableOFT`)
 * And Origami's `OrigamiElevatedAccess` model.
 */
contract OrigamiOftElevatedAccess is OwnableOFT, OrigamiElevatedAccessBase {
    constructor(address initialOwner) {
        _init(initialOwner);
    }

    modifier onlyOFTOwner() override {
        if (!isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
