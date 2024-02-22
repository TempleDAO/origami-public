pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";

/**
 * @title Origami Aave v3 Idle Strategy
 * @notice Supply asset into aave v3 for yield
 */
contract OrigamiAaveV3IdleStrategy is OrigamiAbstractIdleStrategy {
    using SafeERC20 for IERC20;

    /**
     * @notice The Aave v3 lending pool.
     */
    IPool public immutable lendingPool;

    /**
     * @notice The Aave rebasing aToken received when supplying `asset`
     */
    IERC20 public immutable aToken;

    constructor(
        address _initialOwner,
        address _asset,
        address _poolAddressProvider
    ) OrigamiAbstractIdleStrategy(_initialOwner, _asset) {
        lendingPool = IPool(IPoolAddressesProvider(_poolAddressProvider).getPool());
        aToken = IERC20(lendingPool.getReserveData(_asset).aTokenAddress);

        asset.forceApprove(address(lendingPool), type(uint256).max);
    }

    /**
     * @notice Allocate any idle funds in this contract, into the underlying protocol
     * In this case, it supplies into the Aave market
     */
    function allocate(uint256 amount) external override onlyElevatedAccess {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        emit Allocated(amount);
        
        asset.safeTransferFrom(msg.sender, address(this), amount);
        lendingPool.supply(address(asset), amount, address(this), 0 /* no referralCode */);
    }

    /**
     * @notice Optimistically pull funds out of the underlying protocol and to the recipient.
     * @dev If the strategy doesn't have that amount available, with withdraw the max amount
     * and report that in the `amountOut` return variable
     */
    function withdraw(uint256 amount, address recipient) external override onlyElevatedAccess returns (uint256 amountOut) {
        // Cap the amount to withdraw by the max available
        uint256 _available = availableToWithdraw();
        if (_available < amount) amount = _available;
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        emit Withdrawn(amount, recipient);
        amountOut = lendingPool.withdraw(address(asset), amount, recipient);
    }

    /**
     * @notice Recover any token other than the aToken
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        if (token == address(aToken)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice The amount that's possible to withdraw as of now.
     * @dev Total of `asset` which is possible to withdraw
     * For Aave, some of these funds may not be able to be withdrawn if at 100% utilisation.
     */
    function availableToWithdraw() public override view returns (uint256) {
        // The min of our position and what's available to withdraw from aave
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        uint256 assetBalance = asset.balanceOf(address(aToken));
        return aTokenBalance < assetBalance ? aTokenBalance : assetBalance;
    }

    /**
     * @notice The total balance deposited and accrued, 
     * regardless if it is currently available to withdraw or not
     */
    function totalBalance() public override view returns (uint256) {
        return aToken.balanceOf(address(this));
    }
}
