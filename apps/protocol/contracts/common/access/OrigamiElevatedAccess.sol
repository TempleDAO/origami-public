pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/access/OrigamiElevatedAccessBase.sol)

import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";

/**
 * @notice Inherit to add Owner roles for DAO elevated access.
 */ 
abstract contract OrigamiElevatedAccess is OrigamiElevatedAccessBase {
    constructor(address initialOwner) {
        _init(initialOwner);
    }
}
