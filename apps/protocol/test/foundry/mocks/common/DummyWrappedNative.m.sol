pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (test/foundry/mocks/common/DummyWrappedNative.m.sol)

import { MintableToken } from "contracts/common/MintableToken.sol";

contract DummyWrappedNative is MintableToken {
    constructor(string memory _name, string memory _symbol, address _initialOwner)
        MintableToken(_name, _symbol, _initialOwner) 
    {}

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        // solhint-disable-next-line reason-string */
        require(balanceOf(msg.sender) >= amount, "DummyWrappedNative: insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}
