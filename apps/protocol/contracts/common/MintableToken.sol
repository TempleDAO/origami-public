pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/MintableToken.sol)

import {ERC20, ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMintableToken} from "../interfaces/common/IMintableToken.sol";
import {CommonEventsAndErrors} from "../common/CommonEventsAndErrors.sol";
import {Governable} from "../common/access/Governable.sol";

/// @notice An ERC20 token which can be minted/burnt by approved accounts
abstract contract MintableToken is IMintableToken, ERC20Permit, Governable {
    using SafeERC20 for IERC20;

    /// @notice A set of addresses which are approved to mint/burn
    mapping(address => bool) internal _minters;

    event AddedMinter(address indexed account);
    event RemovedMinter(address indexed account);

    function isMinter(address account) external view returns (bool) {
        return _minters[account];
    }

    error CannotMintOrBurn(address caller);

    constructor(string memory _name, string memory _symbol, address _initialGov)
        ERC20(_name, _symbol) 
        ERC20Permit(_name) 
        Governable(_initialGov)
    {}

    function mint(address _to, uint256 _amount) external override {
        if (!_minters[msg.sender]) revert CannotMintOrBurn(msg.sender);
        _mint(_to, _amount);
    }

    function burn(address account, uint256 amount) external override {
        if (!_minters[msg.sender]) revert CannotMintOrBurn(msg.sender);
        _burn(account, amount);
    }

    function addMinter(address account) external onlyGov {
        _minters[account] = true;
        emit AddedMinter(account);
    }

    function removeMinter(address account) external onlyGov {
        _minters[account] = false;
        emit RemovedMinter(account);
    }

    /// @notice Gov can recover tokens
    function recoverToken(address _token, address _to, uint256 _amount) external onlyGov {
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }
}