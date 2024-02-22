pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { MintableToken } from "contracts/common/MintableToken.sol";

contract DummyMintableToken is MintableToken {
    uint8 private _decimals;
    
    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        uint8 decimals_
    ) MintableToken(_name, _symbol, _initialOwner) {
        _decimals = decimals_;
    }

    function revertNoMessage() external pure {
        revert();
    }

    function decimals() override public view returns (uint8) {
        return _decimals;
    }
}
