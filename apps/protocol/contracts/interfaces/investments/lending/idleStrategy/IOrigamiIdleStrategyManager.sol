pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

/**
 * @title Origami Idle Strategy Manager
 * @notice Manage the allocation of idle capital, allocating to an underlying protocol specific strategy.
 * This contract will keep some of the assets in situ (within a threshold), since allocating to underlying 
 * protocol may be gassy.
 * This manager is a 'borrower' of funds from the OrigamiLendingClerk, so will have an iToken debt
 * for any funds allocated into it.
 */
interface IOrigamiIdleStrategyManager is IOrigamiLendingBorrower {
    event IdleStrategySet(address indexed idleStrategy);
    event DepositsEnabledSet(bool value);
    event ThresholdsSet(uint256 depositThreshold, uint256 withdrawalBuffer);
    event Allocated(uint256 amount, uint256 idleStrategyAmount);
    event Withdrawn(address indexed recipient, uint256 amount, uint256 idleStrategyAmount);
    
    /**
     * @notice Update the idle strategy to deposit into
     */
    function setIdleStrategy(address _idleStrategy) external;

    /**
     * @notice Set whether deposits into the underlyling idle strategy are enabled or not
     */
    function setDepositsEnabled(bool value) external;

    /**
     * @notice Set the depositThreshold and withdrawalBuffer
     */
    function setThresholds(
        uint256 _depositThreshold, 
        uint256 _withdrawalBuffer
    ) external;

    /**
     * @notice Pull in and allocate an amount of `asset` tokens
     * @dev If `depositsEnabled` then any surplus balance over the `depositThreshold`
     * is allocated into the underlying idle strategy
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Withdraw asset and send to recipient.
     * @dev Any available balance within this contract is used first before pulling
     * from the underlying idle strategy
     */
    function withdraw(uint256 amount, address recipient) external;

    /**
     * @notice Allocate from the manager balance to the underlying idle strategy
     * regardless of thresholds
     */
    function allocateFromManager(uint256 amount) external;

    /**
     * @notice Optimistically withdraw from underlying idle strategy to the manager
     * regardless of thresholds
     */
    function withdrawToManager(uint256 amount) external returns (uint256);
    
    /**
     * @notice The supplied asset to the idle strategy
     */
    function asset() external view returns (IERC20);

    /**
     * @notice The underlying idle strategy where `asset` balances over the `depositThreshold`
     * are deposited into.
     */
    function idleStrategy() external view returns (IOrigamiIdleStrategy);

    /** 
     * @notice If true, new allocations of `asset` will be deposited into the underlying 
     * idle strategy. If false, any incoming `asset` is left to accrue in this contract
     */
    function depositsEnabled() external view returns (bool);

    /**
     * @notice A buffer of tokens are maintained in the manager such that it doesn't have to churn through small
     * amounts of withdrawals from the underlying. 
     * On a withdraw if tokens need to be pulled from the underlying strategy, then an amount will be pulled
     * in order to leave a balance equal to this `withdrawalBuffer`
     * @dev To the precision of the underlying asset. Eg USDC is 6dp
     */
    function withdrawalBuffer() external view returns (uint256);

    /**
     * @notice When funds are allocated, only surplus balance greater than this `depositThreshold` are
     * allocated into the underlying idle strategy.
     * @dev To the precision of the underlying asset. Eg USDC is 6dp
     */
    function depositThreshold() external view returns (uint256);
    
    /**
     * @notice The amount that's possible to withdraw as of now.
     * @dev Total of `asset` in this contract and also in the underlying idle strategy which is possible to withdraw
     * Eg if supplied within aave, some of these funds may not be able to be withdrawn if at 100% utilisation.
     */
    function availableToWithdraw() external view returns (uint256);
}
