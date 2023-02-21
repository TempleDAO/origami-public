pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {MintableToken} from "contracts/common/MintableToken.sol";

contract DummyMintableToken is MintableToken {
    constructor(
        address _initialGov,
        string memory _name,
        string memory _symbol
    ) MintableToken(_name, _symbol, _initialGov) {
    }

    function revertNoMessage() external pure {
        revert();
    }
}
