pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

/**
 * @notice The common logic for an Idle Strategy, which can allocate and withdraw funds in 3rd
 * party protocols for yield and capital efficiency.
 */
abstract contract OrigamiAbstractIdleStrategy is IOrigamiIdleStrategy, OrigamiElevatedAccess {
    /**
     * @notice The supplied asset to the idle strategy
     */
    IERC20 public immutable override asset;

    constructor(
        address _initialOwner,
        address _asset
    ) OrigamiElevatedAccess(_initialOwner) {
        asset = IERC20(_asset);
    }

    /**
     * @notice Allocate funds into the underlying protocol
     */
    function allocate(uint256 amount) external virtual override;

    /**
     * @notice Optimistically pull funds out of the underlying protocol and to the recipient.
     * @dev If the strategy doesn't have that amount available, with withdraw the max amount
     * and report that in the `amountOut` return variable
     */
    function withdraw(uint256 amount, address recipient) external virtual override returns (uint256 amountOut);

    /**
     * @notice Some strategies may need to update state in order to calculate
     * the latest balance. 
     * By default, this will return the same as totalBalance
     */
    function checkpointTotalBalance() external virtual override returns (uint256) {
        return totalBalance();
    }

    /**
     * @notice The amount that's possible to withdraw as of now.
     * @dev Total of `asset` which is possible to withdraw
     * Eg if supplied within aave, some of these funds may not be able to be withdrawn if at 100% utilisation.
     */
    function availableToWithdraw() external virtual override view returns (uint256);

    /**
     * @notice The total balance deposited and accrued, 
     * regardless if it is currently available to withdraw or not
     */
    function totalBalance() public virtual override view returns (uint256);

    /**
     * @notice Recover tokens sent to this contract
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external virtual;
}
