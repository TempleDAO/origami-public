pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/MintableToken.sol)

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMintableToken} from "../interfaces/common/IMintableToken.sol";
import {CommonEventsAndErrors} from "../common/CommonEventsAndErrors.sol";

/// @notice An ERC20 token which can be minted/burnt, granted by the CAN_MINT role.
contract MintableToken is IMintableToken, ERC20Permit, Ownable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant CAN_MINT = keccak256("CAN_MINT");
    error CannotMintOrBurn(address caller);

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol) 
        ERC20Permit(_name) 
    {
        _setupRole(DEFAULT_ADMIN_ROLE, owner());
    }

    function mint(address _to, uint256 _amount) external override {
        if (!hasRole(CAN_MINT, msg.sender)) revert CannotMintOrBurn(msg.sender);
        _mint(_to, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        if (!hasRole(CAN_MINT, msg.sender)) revert CannotMintOrBurn(msg.sender);
        _burn(_account, _amount);
    }

    function addMinter(address _account) external onlyOwner {
        grantRole(CAN_MINT, _account);
    }

    function removeMinter(address _account) external onlyOwner {
        revokeRole(CAN_MINT, _account);
    }

    /// @notice Owner can recover tokens
    function recoverToken(address _token, address _to, uint256 _amount) external onlyOwner {
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }
}