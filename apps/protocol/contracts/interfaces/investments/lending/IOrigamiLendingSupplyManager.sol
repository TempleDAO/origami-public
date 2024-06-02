pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/IOrigamiLendingSupplyManager.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";
import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

/**
 * @title Origami Lending Supply Manager
 * @notice Manages the deposits/exits into an Origami oToken vault for lending purposes,
 * eg oUSDC. The supplied assets are forwarded onto a 'lending clerk' which manages the
 * collateral and debt
 * @dev supports an asset with decimals <= 18 decimal places
 */
interface IOrigamiLendingSupplyManager is IOrigamiOTokenManager, IWhitelisted {
    event LendingClerkSet(address indexed lendingClerk);
    event FeeCollectorSet(address indexed feeCollector);
    event ExitFeeBpsSet(uint256 feeBps);

    /**
     * @notice Set the clerk responsible for managing borrows, repays and debt of borrowers
     */
    function setLendingClerk(address _lendingClerk) external;

    /**
     * @notice Set the Origami fee collector address
     */
    function setFeeCollector(address _feeCollector) external;

    /**
     * @notice Set the proportion of fees retained when users exit their position.
     * @dev represented in basis points
     */
    function setExitFeeBps(uint96 feeBps) external;

    /**
     * @notice The asset which users supply
     * eg USDC for oUSDC
     */
    function asset() external view returns (IERC20Metadata);

    /**
     * @notice The Origami oToken which uses this manager
     */
    function oToken() external view returns (address);

    /**
     * @notice The Origami ovToken which wraps the oToken
     */
    function ovToken() external view returns (address);

    /**
     * @notice A circuit breaker is used to ensure no more than a cap
     * is exited in a given period
     */
    function circuitBreakerProxy() external view returns (IOrigamiCircuitBreakerProxy);

    /**
     * @notice The clerk responsible for managing borrows, repays and debt of borrowers
     */
    function lendingClerk() external view returns (IOrigamiLendingClerk);

    /**
     * @notice The address used to collect the Origami fees.
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The proportion of fees retained when users exit their position.
     * @dev represented in basis points
     */
    function exitFeeBps() external view returns (uint96);
}
