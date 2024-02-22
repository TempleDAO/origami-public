// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/GMX_MintableBaseToken.sol";

contract GMX_GMX is GMX_MintableBaseToken {
    constructor() public GMX_MintableBaseToken("GMX", "GMX", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "GMX";
    }
}
