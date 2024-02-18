pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_WalletWhitelist.sol)

interface IStakeDao_WalletWhitelist {
    function approveWallet(address wallet) external;
    function admin() external view returns (address);
}
