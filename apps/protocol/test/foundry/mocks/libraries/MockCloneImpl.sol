pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { LibString } from "solady/utils/LibString.sol";

contract MockCloneImpl {
    function getArgAddress(uint256 offset) public view returns (address) {
        return ClonesImmutableReader._getArgAddress(offset);
    }

    function getArgBytes32(uint256 offset) public view returns (bytes32) {
        return ClonesImmutableReader._getArgBytes32(offset);
    }

    function getArgString(uint256 offset) public view returns (string memory) {
        return LibString.fromSmallString(ClonesImmutableReader._getArgBytes32(offset));
    }

    function getArgUint8(uint256 offset) public view returns (uint8) {
        return ClonesImmutableReader._getArgUint8(offset);
    }

    function getArgUint256(uint256 offset) public view returns (uint256) {
        return ClonesImmutableReader._getArgUint256(offset);
    }
}
