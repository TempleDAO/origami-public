pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/access/OrigamiElevatedAccessUpgradeable.sol)

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";

/**
 * @notice Inherit to add Owner roles for DAO elevated access.
 */ 
abstract contract OrigamiElevatedAccessUpgradeable is Initializable, OrigamiElevatedAccessBase {
    function __OrigamiElevatedAccess_init(address initialOwner) internal onlyInitializing {
        __OrigamiElevatedAccess_init_unchained(initialOwner);
    }

    function __OrigamiElevatedAccess_init_unchained(address initialOwner) internal onlyInitializing {
        _init(initialOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}
