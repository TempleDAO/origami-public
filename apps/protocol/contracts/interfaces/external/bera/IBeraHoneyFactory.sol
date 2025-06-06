// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice This is the interface of HoneyFactory.
/// @author Berachain Team
interface IBeraHoneyFactory {
    /// @notice The Honey token contract.
    function honey() external view returns (IERC20);

    /// @notice Mint rate of Honey for each asset, 60.18-decimal fixed-point number representation
    function mintRates(address asset) external view returns (uint256 rate);

    /// @notice Redemption rate of Honey for each asset, 60.18-decimal fixed-point number representation
    function redeemRates(address asset) external view returns (uint256 rate);

    /// @notice Mint Honey by sending ERC20 to this contract.
    /// @dev Assest must be registered and must be a good collateral.
    /// @param amount The amount of ERC20 to mint with.
    /// @param receiver The address that will receive Honey.
    /// @param expectBasketMode The flag with which the client communicates its expectation of the basket mode
    /// status.
    /// @return The amount of Honey minted.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function mint(address asset, uint256 amount, address receiver, bool expectBasketMode) external returns (uint256);

    /// @notice Redeem assets by sending Honey in to burn.
    /// @param honeyAmount The amount of Honey to redeem.
    /// @param receiver The address that will receive assets.
    /// @param expectBasketMode The flag with which the client communicates its expectation of the basket mode
    /// status.
    /// @return The amount of assets redeemed.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function redeem(
        address asset,
        uint256 honeyAmount,
        address receiver,
        bool expectBasketMode
    ) external returns (uint256[] memory);

    /// @notice Get the status of the basket mode.
    /// @dev On mint, basket mode is enabled if all collaterals are either depegged or bad.
    /// @dev On redeem, basket mode is enabled if at least one asset is deppegged
    /// except for the collateral assets that have been fully liquidated.
    function isBasketModeEnabled(bool isMint) external view returns (bool basketMode);

    /// @notice Get the length of `registeredAssets` array.
    function numRegisteredAssets() external view returns (uint256);

    /// @notice Array of registered assets.
    function registeredAssets(uint256) external view returns (address);
}