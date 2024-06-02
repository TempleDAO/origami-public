pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice An Origami Idle Strategy, which can allocate and withdraw funds in 3rd
 * party protocols for yield and capital efficiency.
 */
interface IOrigamiIdleStrategy {
    event Allocated(uint256 amount);
    event Withdrawn(uint256 amount, address indexed recipient);

    /**
     * @notice The supplied asset to the idle strategy
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Allocate funds into the underlying protocol
     */
    function allocate(uint256 amount) external;

    /**
     * @notice Optimistically pull funds out of the underlying protocol and to the recipient.
     * @dev If the strategy doesn't have that amount available, with withdraw the max amount
     * and report that in the `amountOut` return variable
     */
    function withdraw(uint256 amount, address recipient) external returns (uint256 amountOut);

    /**
     * @notice Some strategies may need to update state in order to calculate
     * the latest balance. 
     * By default, this will return the same as totalBalance
     */
    function checkpointTotalBalance() external returns (uint256);

    /**
     * @notice The amount that's possible to withdraw as of now.
     * @dev Total of `asset` which is possible to withdraw
     * Eg if supplied within aave, some of these funds may not be able to be withdrawn if at 100% utilisation.
     */
    function availableToWithdraw() external view returns (uint256);

    /**
     * @notice The total balance deposited and accrued, 
     * regardless if it is currently available to withdraw or not
     */
    function totalBalance() external view returns (uint256);
}
