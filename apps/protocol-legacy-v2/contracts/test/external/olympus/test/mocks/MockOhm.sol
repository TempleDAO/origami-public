// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MockERC20 as ERC20} from "./MockERC20.sol";

contract MockOhm is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public override virtual {
        _mint(to, value);
    }

    function burn(uint256 value) public virtual {
        _burn(msg.sender, value);
    }

    function burnFrom(address from, uint256 value) public virtual {
        _spendAllowance(from, msg.sender, value);
        _burn(from, value);
    }
}
