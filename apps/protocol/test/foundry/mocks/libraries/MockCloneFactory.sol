pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { LibClone } from "solady/utils/LibClone.sol";

contract MockCloneFactory {
    event Cloned(address indexed implementation, address indexed instance);

    function create(address implementation, bytes calldata immutableArgsData) external returns (address instance) {
        instance = LibClone.clone(implementation, immutableArgsData);

        emit Cloned(implementation, instance);
    }
}
