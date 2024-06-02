pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiMorphoBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiMorphoBorrowAndLend.sol";

/**
 * @title Origami LovToken Manager, for use with Morpho markets
 * @notice The `reserveToken` is deposited by users and supplied into Morpho as collateral
 * Upon a rebalanceDown (to decrease the A/L), the position is levered up
 */
interface IOrigamiLovTokenMorphoManager is IOrigamiLovTokenManager {
    event OraclesSet(address indexed debtTokenToReserveTokenOracle, address indexed dynamicFeePriceOracle);
    event BorrowLendSet(address indexed addr);

    /**
     * @notice Set the `reserveToken` <--> `debtToken` oracle configuration 
     */
    function setOracles(address _debtTokenToReserveTokenOracle, address _dynamicFeePriceOracle) external;

    /**
     * @notice Set the Origami Borrow/Lend position holder
     */
    function setBorrowLend(address _address) external;

    struct RebalanceUpParams {
        // The amount of `debtToken` to repay
        uint256 repayAmount;

        // The amount of `reserveToken` collateral to withdraw
        uint256 withdrawCollateralAmount;

        // The swap quote data to swap from `reserveToken` -> `debtToken`
        bytes swapData;

        // The min balance threshold for when surplus balance of `debtToken` is
        // repaid to the Morpho position
        uint256 repaySurplusThreshold;

        // The minimum acceptable A/L, will revert if below this
        uint128 minNewAL;

        // The maximum acceptable A/L, will revert if above this
        uint128 maxNewAL;
    }

    /**
     * @notice Increase the A/L by reducing liabilities.
     * Uses Morpho's callback mechanism to efficiently lever up
     */
    function rebalanceUp(RebalanceUpParams calldata params) external;

    /**
     * @notice Force a rebalanceUp ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceUp(RebalanceUpParams calldata params) external;

    struct RebalanceDownParams {
        // The amount of `reserveToken` collateral to supply
        uint256 supplyAmount;

        // The amount of `debtToken` to borrow
        uint256 borrowAmount;
        
        // The swap quote data to swap from `debtToken` -> `reserveToken`
        bytes swapData;

        // The min balance threshold for when surplus balance of `reserveToken` is added as
        // collateral to the Morpho position
        uint256 supplyCollateralSurplusThreshold;
        
        // The minimum acceptable A/L, will revert if below this
        uint128 minNewAL;

        // The maximum acceptable A/L, will revert if above this
        uint128 maxNewAL;
    }

    /**
     * @notice Decrease the A/L by increasing liabilities. 
     * Uses Morpho's callback mechanism to efficiently lever up
     */
    function rebalanceDown(RebalanceDownParams calldata params) external;

    /**
     * @notice Force a rebalanceDown ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceDown(RebalanceDownParams calldata params) external;

    /**
     * @notice The contract responsible for borrow/lend via external markets
     */
    function borrowLend() external view returns (IOrigamiMorphoBorrowAndLend);

    /**
     * @notice The oracle to convert `debtToken` <--> `reserveToken`
     */
    function debtTokenToReserveTokenOracle() external view returns (IOrigamiOracle);

    /**
     * @notice The base asset used when retrieving the prices for dynamic fee calculations.
     */
    function dynamicFeeOracleBaseToken() external view returns (address);

    /**
     * @notice The oracle to use when observing prices which are used for the dynamic fee calculations
     */
    function dynamicFeePriceOracle() external view returns (IOrigamiOracle);
}