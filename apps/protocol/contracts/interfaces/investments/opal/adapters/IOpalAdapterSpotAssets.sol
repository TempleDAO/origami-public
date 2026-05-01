pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/adapters/IOpalAdapterSpotAssets.sol)

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Spot Assets
/// @notice An OPAL Adapter which simply holds a balance of fixed ERC20 asset tokens (no liabilities)
interface IOpalAdapterSpotAssets is IOpalAdapter {
    /// @notice Encode the immutable args for cloning
    function encodeImmutableArgs(address[] calldata _assets) external view returns (bytes memory);

    /// @notice Encode the initialization args
    function encodeInitArgs(address _initialOwner) external view returns (bytes memory);

    /// @notice The number of assets which this adapter tracks balances for
    function numAssets() external view returns (uint8);

    /// @notice The set of assets which this adapter holds and is counted towards it's balance sheet.
    function assets() external view returns (address[] memory);
}
