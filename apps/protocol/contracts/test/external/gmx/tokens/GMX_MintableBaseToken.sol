// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./GMX_BaseToken.sol";
import "./interfaces/GMX_IMintable.sol";

contract GMX_MintableBaseToken is GMX_BaseToken, GMX_IMintable {

    mapping (address => bool) public override isMinter;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) public GMX_BaseToken(_name, _symbol, _initialSupply) {
    }

    modifier onlyMinter() {
        require(isMinter[msg.sender], "MintableBaseToken: forbidden");
        _;
    }

    function setMinter(address _minter, bool _isActive) external override onlyGov {
        isMinter[_minter] = _isActive;
    }

    function mint(address _account, uint256 _amount) external override onlyMinter {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyMinter {
        _burn(_account, _amount);
    }
}
