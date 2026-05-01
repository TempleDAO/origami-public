pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";

contract DummyMintableTokenPermissionless is IMintableToken, ERC20Permit {
    uint8 private _decimals;
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_
    ) 
        ERC20(_name, _symbol) 
        ERC20Permit(_name) 
    {
        _decimals = decimals_;
    }

    function mint(address _to, uint256 _amount) external override {
        _mint(_to, _amount);
    }

    function deal(address _to, uint256 _amount) external {
        uint256 bal = balanceOf(_to);
        if (bal > _amount) {
            _burn(_to, bal-_amount);
        } else {
            _mint(_to, _amount-bal);
        }
    }

    function burn(address account, uint256 amount) external override {
        _burn(account, amount);
    }

    function decimals() override public view returns (uint8) {
        return _decimals;
    }
}
