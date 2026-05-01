// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IBeraHoneyFactory } from "contracts/interfaces/external/bera/IBeraHoneyFactory.sol";

/// @notice This is the factory contract for minting and redeeming Honey.
/// @author Berachain Team
interface IBeraHoneyFactoryReader {
    /// @notice The HoneyFactory contract.
    function honeyFactory() external view returns (IBeraHoneyFactory);

    /// @notice Computes the amount of collateral(s) to provide in order to obtain a given amount of Honey.
    /// @dev `asset` param is ignored if running in basket mode.
    /// @param asset The collateral to consider if not in basket mode.
    /// @param honey The desired amount of honey to obtain.
    /// @param amounts The amounts of collateral to provide.
    function previewMintCollaterals(
        address asset,
        uint256 honey
    ) external view returns (uint256[] memory amounts);

    /// @notice Given one collateral, computes the obtained Honey and the amount of collaterals expected if the basket
    /// mode is enabled.
    /// @param asset The collateral to provide.
    /// @param amount The desired amount of collateral to provide.
    /// @return collaterals The amounts of collateral to provide for every asset.
    /// @return honey The expected amount of Honey to be minted (considering also the other collaterals in basket
    /// mode).
    function previewMintHoney(
        address asset,
        uint256 amount
    ) external view returns (uint256[] memory collaterals, uint256 honey);

    /// @notice Computes the obtaineable amount of collateral(s) given an amount of Honey.
    /// @dev `asset` param is ignored if running in basket mode.
    /// @param asset The collateral to obtain if not in basket mode.
    /// @param honey The amount of honey provided.
    /// @return collaterals The amounts of collateral to obtain.
    function previewRedeemCollaterals(
        address asset,
        uint256 honey
    ) external view returns (uint256[] memory collaterals);

    /// @notice Given one desired collateral, computes the Honey to provide.
    /// @param asset The collateral to obtain.
    /// @param amount The desired amount of collateral to obtain.
    /// @return collaterals The amounts of obtainable collaterals.
    /// @return honey The amount of Honey to be provided.
    /// @dev If the basket mode is enabled, the required Honey amount will provide also other collaterals beside
    /// required `amount` of `asset`.
    function previewRedeemHoney(
        address asset,
        uint256 amount
    ) external view returns (uint256[] memory collaterals, uint256 honey);
}
