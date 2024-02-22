pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/MintableToken.sol)

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/// @notice An ERC20 token which can be minted/burnt by approved accounts
abstract contract MintableToken is IMintableToken, ERC20Permit, ERC20Burnable, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /// @notice A set of addresses which are approved to mint/burn
    mapping(address account => bool canMint) internal _minters;

    event AddedMinter(address indexed account);
    event RemovedMinter(address indexed account);

    function isMinter(address account) external view returns (bool) {
        return _minters[account];
    }

    error CannotMintOrBurn(address caller);

    constructor(string memory _name, string memory _symbol, address _initialOwner)
        ERC20(_name, _symbol) 
        ERC20Permit(_name) 
        OrigamiElevatedAccess(_initialOwner)
    {}

    function mint(address _to, uint256 _amount) external override {
        if (!_minters[msg.sender]) revert CannotMintOrBurn(msg.sender);
        _mint(_to, _amount);
    }

    function burn(address account, uint256 amount) external override {
        if (!_minters[msg.sender]) revert CannotMintOrBurn(msg.sender);
        _burn(account, amount);
    }

    function addMinter(address account) external onlyElevatedAccess {
        _minters[account] = true;
        emit AddedMinter(account);
    }

    function removeMinter(address account) external onlyElevatedAccess {
        _minters[account] = false;
        emit RemovedMinter(account);
    }

    /**
     * @notice Recover any token -- this contract should not ordinarily hold any tokens.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external virtual onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }
}