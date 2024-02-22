pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/access/Whitelisted.sol)

/**
 * @title Whitelisted abstract contract
 * @notice Functionality to deny non-EOA addresses unless whitelisted
 */
interface IWhitelisted {
    event AllowAllSet(bool value);
    event AllowAccountSet(address indexed account, bool value);

    /**
     * @notice Allow all (both EOAs and contracts) without whitelisting
     */
    function allowAll() external view returns (bool);

    /**
     * @notice A mapping of whitelisted accounts (not required for EOAs)
     */
    function allowedAccounts(address account) external view returns (bool allowed);

    /**
     * @notice Allow all callers without whitelisting
     */
    function setAllowAll(bool value) external;

    /**
     * @notice Set whether a given account is allowed or not
     */
    function setAllowAccount(address account, bool value) external;
}
