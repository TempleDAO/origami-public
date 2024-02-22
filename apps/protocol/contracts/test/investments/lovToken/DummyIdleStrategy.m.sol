pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract DummyIdleStrategy is OrigamiAbstractIdleStrategy {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    // How much is available (vs not available) out of the balance
    uint256 public availableSplit;

    constructor(
        address _initialOwner,
        address _asset,
        uint128 _availableSplit
    ) OrigamiAbstractIdleStrategy(_initialOwner, _asset) {
        if (_availableSplit > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        availableSplit = _availableSplit;
    }

    /**
     * @notice Allocate any idle funds in this contract, into the underlying protocol
     */
    function allocate(uint256 amount) external override {
        emit Allocated(amount);
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Optimistically pull funds out of the underlying protocol and to the recipient.
     * @dev If the strategy doesn't have that amount available, with withdraw the max amount
     * and report that in the `amountOut` return variable
     */
    function withdraw(uint256 amount, address recipient) external override returns (uint256 amountOut) {
        // Cap the amount that can be withdrawn to the available fraction
        uint256 _available = availableToWithdraw();
        amountOut = (amount > _available) 
            ? _available
            : amount;

        emit Withdrawn(amountOut, recipient);
        asset.safeTransfer(recipient, amountOut);
    }

    /**
     * @notice Recover any token other than the asset
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        if (token == address(asset)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice The amount that's possible to withdraw as of now.
     * @dev Total of `asset` which is possible to withdraw
     * Eg if supplied within aave, some of these funds may not be able to be withdrawn if at 100% utilisation.
     */
    function availableToWithdraw() public override view returns (uint256 available) {
        (,available) = totalBalance().splitSubtractBps(
            availableSplit
        );
    }

    /**
     * @notice The total balance deposited and accrued, 
     * regardless if it is currently available to withdraw or not
     */
    function totalBalance() public override view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}