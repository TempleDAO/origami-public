// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/GMX_MintableBaseToken.sol";

contract GMX_GLP is GMX_MintableBaseToken {
    constructor() public GMX_MintableBaseToken("GMX LP", "GLP", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "GLP";
    }
}
