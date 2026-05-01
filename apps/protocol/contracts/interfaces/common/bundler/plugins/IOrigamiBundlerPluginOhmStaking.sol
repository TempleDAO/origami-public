pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginOhmStaking.sol)

import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin for OHM <--> gOHM
interface IOrigamiBundlerPluginOhmStaking is IOrigamiBundlerPluginMultiAccess {
    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Stake an amount of OHM into gOHM
    /// @param ohmAmount The amount of OHM to stake.
    /// @param receiver The address that will receive the gOHM.
    function stakeToGOhm(uint256 ohmAmount, address receiver) external;

    /// @notice Stake all OHM balance into gOHM
    /// @param receiver The address that will receive the gOHM.
    function stakeBalanceToGOhm(address receiver) external;

    /// @notice Unstake an amount of gOHM into OHM
    /// @param gOhmAmount The amount of gOHM to unstake.
    /// @param receiver The address that will receive the OHM.
    function unstakeToOhm(uint256 gOhmAmount, address receiver) external;

    /// @notice Unstake all gOHM balance into OHM
    /// @param receiver The address that will receive the OHM.
    function unstakeBalanceToOhm(address receiver) external;

    /****** VIEWS ******/

    /// @notice The Olympus OHM <-> gOHm staking contract
    function OLYMPUS_STAKING() external view returns (address);

    /// @notice The Olympus OHM token
    function OHM() external view returns (address);

    /// @notice The Olympus gOHM governance token
    function GOHM() external view returns (address);

    /// @notice Quote to stake OHM into gOHM
    function stakeToGOhmQuote(uint256 ohmAmount) external view returns (uint256 gOhmAmount);

    /// @notice Quote to unstake gOHM into OHM
    function unstakeToOhmQuote(uint256 gOhmAmount) external view returns (uint256 ohmAmount);
}
