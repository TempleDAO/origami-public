pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/ITokenPrices.sol)

/// @title Token Prices
/// @notice A utility contract to pull token prices from on-chain.
/// @dev composable functions (uisng encoded function calldata) to build up price formulas
interface ITokenPrices {
    /// @notice How many decimals places are the token prices reported in
    function decimals() external view returns (uint8);

    /// @notice Retrieve the price for a given token.
    /// @dev If not mapped, or an underlying error occurs, FailedPriceLookup will be thrown.
    /// @dev 0x000...0 is the native chain token (ETH/AVAX/etc)
    function tokenPrice(address token) external view returns (uint256 price);

    /// @notice Retrieve the price for a list of tokens.
    /// @dev If any aren't mapped, or an underlying error occurs, FailedPriceLookup will be thrown.
    /// @dev Not particularly gas efficient - wouldn't recommend to use on-chain
    function tokenPrices(address[] memory tokens) external view returns (uint256[] memory prices);
}