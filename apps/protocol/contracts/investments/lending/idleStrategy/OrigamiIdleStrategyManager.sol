pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";
import { IOrigamiIdleStrategy } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategy.sol";

/**
 * @title Origami Idle Strategy Manager
 * @notice Manage the allocation of idle capital, allocating to an underlying protocol specific strategy.
 * This contract will keep some of the assets in situ (within a threshold), since allocating to underlying 
 * protocol may be gassy.
 * This manager is a 'borrower' of funds from the OrigamiLendingClerk, so will have an iToken debt
 * for any funds allocated into it.
 */
contract OrigamiIdleStrategyManager is IOrigamiIdleStrategyManager, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /**
     * @notice The supplied asset to the idle strategy
     */
    IERC20 public immutable override asset;

    /**
     * @notice The underlying idle strategy where `asset` balances over the `depositThreshold`
     * are deposited into.
     */
    IOrigamiIdleStrategy public override idleStrategy;

    /** 
     * @notice If true, new allocations of `asset` will be deposited into the underlying 
     * idle strategy. If false, any incoming `asset` is left to accrue in this contract
     */
    bool public override depositsEnabled;

    /**
     * @notice A buffer of tokens are maintained in the manager such that it doesn't have to churn through small
     * amounts of withdrawals from the underlying. 
     * On a withdraw if tokens need to be pulled from the underlying strategy, then an amount will be pulled
     * in order to leave a balance equal to this `withdrawalBuffer`
     * @dev To the precision of the underlying asset. Eg USDC is 6dp
     */
    uint256 public override withdrawalBuffer;

    /**
     * @notice When funds are allocated, only surplus balance greater than this `depositThreshold` are
     * allocated into the underlying idle strategy.
     * @dev To the precision of the underlying asset. Eg USDC is 6dp
     */
    uint256 public override depositThreshold;

    /**
     * @notice Track the deployed version of this contract. 
     */
    string public constant override version = "1.0.0";

    /**
     * @notice A human readable name for the borrower
     */
    string public constant override name = "IdleStrategyManager";

    constructor(
        address _initialOwner,
        address _asset
    ) OrigamiElevatedAccess(_initialOwner) {
        asset = IERC20(_asset);
    }

    /**
     * @notice Update the idle strategy to deposit into
     */
    function setIdleStrategy(address _idleStrategy) external override onlyElevatedAccess {
        if (_idleStrategy == address(0)) revert CommonEventsAndErrors.InvalidAddress(_idleStrategy);

        // Max approve the idle strategy to pull `asset`
        // and remove approval if an old one is set
        address _oldStrategy = address(idleStrategy);
        if (_oldStrategy != address(0)) {
            asset.forceApprove(_oldStrategy, 0);
        }
        asset.forceApprove(_idleStrategy, type(uint256).max);

        idleStrategy = IOrigamiIdleStrategy(_idleStrategy);
        emit IdleStrategySet(_idleStrategy);
    }

    /**
     * @notice Set whether deposits into the underlyling idle strategy are enabled or not
     */
    function setDepositsEnabled(bool value) external override onlyElevatedAccess {
        depositsEnabled = value;
        emit DepositsEnabledSet(value);
    }

    /**
     * @notice Set the depositThreshold and withdrawalBuffer
     */
    function setThresholds(
        uint256 _depositThreshold, 
        uint256 _withdrawalBuffer
    ) external override onlyElevatedAccess {
        depositThreshold = _depositThreshold;
        withdrawalBuffer = _withdrawalBuffer;
        emit ThresholdsSet(_depositThreshold, _withdrawalBuffer);
    }

    /**
     * @notice Pull in and allocate an amount of `asset` tokens
     * @dev If `depositsEnabled` then any surplus balance over the `depositThreshold`
     * is allocated into the underlying idle strategy
     */
    function allocate(uint256 amount) external override onlyElevatedAccess {
        // Pull in the asset tokens
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Allocate into the underlying idle strategy if deposits are enabled
        uint256 underlyingAllocation;
        if (depositsEnabled) {
            uint256 _balance = asset.balanceOf(address(this));
            uint256 _threshold = depositThreshold;

            if (_balance > _threshold) {
                unchecked {                
                    underlyingAllocation = _balance - _threshold;
                }
                
                idleStrategy.allocate(underlyingAllocation);
            }
        }
        emit Allocated(amount, underlyingAllocation);
    }

    /**
     * @notice Withdraw asset and send to recipient.
     * @dev Any available balance within this contract is used first before pulling
     * from the underlying idle strategy
     */
    function withdraw(uint256 amount, address recipient) external onlyElevatedAccess {
        if (amount == 0) revert CommonEventsAndErrors.InvalidParam();
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        uint256 _balance = asset.balanceOf(address(this));
        IOrigamiIdleStrategy _idleStrategy = idleStrategy;
        uint256 withdrawnFromIdleStrategy;
        if (address(_idleStrategy) != address(0)) {
            // There may be idle tokens sitting idle in the manager 
            // (ie these are not yet deposited into the underlying idle strategy)
            // So use these first, and only then fallback to pulling the rest from underlying.
            unchecked {
                withdrawnFromIdleStrategy = _balance > amount ? 0 : amount - _balance;
            }

            // Pull any remainder required from the underlying.
            if (withdrawnFromIdleStrategy != 0) {
                // So there aren't lots of small withdrawals, pull the amount required for this transaction
                // plus the threshold amount. Then future borrows don't need to withdraw from base every time.
                withdrawnFromIdleStrategy += withdrawalBuffer;

                // Pull the asset into this contract. The amount actually withdrawn may be less than requested
                // as it's capped to any actual remaining balance in the underlying
                _balance += _idleStrategy.withdraw(withdrawnFromIdleStrategy, address(this));
            }
        }

        // There should now be enough balance in this contract.
        if (amount > _balance) revert CommonEventsAndErrors.InsufficientBalance(address(asset), amount, _balance);

        // Finally send to the recipient
        emit Withdrawn(recipient, amount, withdrawnFromIdleStrategy);
        asset.safeTransfer(recipient, amount);
    }

    /**
     * @notice Allocate from the manager balance to the underlying idle strategy
     * regardless of thresholds
     */
    function allocateFromManager(uint256 amount) external override onlyElevatedAccess {
        idleStrategy.allocate(amount);
    }

    /**
     * @notice Withdraw from underlying idle strategy to the manager
     * regardless of thresholds
     */
    function withdrawToManager(uint256 amount) external override onlyElevatedAccess returns (uint256) {
        return idleStrategy.withdraw(amount, address(this));
    }

    /**
     * @notice Recover any token other than the asset
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        if (token == address(asset)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice The amount that's possible to withdraw as of now.
     * @dev Total of `asset` in this contract and also in the underlying idle strategy (that's possible to withdraw as of now)
     * Eg if supplied within aave, some of these funds may not be able to be withdrawn if at 100% utilisation.
     */
    function availableToWithdraw() external view returns (uint256) {
        IOrigamiIdleStrategy _idleStrategy = idleStrategy;
        return (address(_idleStrategy) != address(0))
            ? asset.balanceOf(address(this)) + _idleStrategy.availableToWithdraw()
            : asset.balanceOf(address(this));
    }

    /**
     * @notice The latest checkpoint the asset balance in the idle strategy manager
     * and underlying strategy
     *
     * @dev The asset value may be stale at any point in time, depending on the underyling strategy. 
     * It may optionally implement `checkpointAssetBalances()` in order to update those balances.
     */
    function latestAssetBalances() external view returns (AssetBalance[] memory assetBalances) {
        assetBalances = new AssetBalance[](1);

        // The sum of the balance in this contract, plus the underlying idle strategy (if set)
        IOrigamiIdleStrategy _idleStrategy = idleStrategy;
        uint256 assetBalance = (address(_idleStrategy) != address(0))
            ? asset.balanceOf(address(this)) + _idleStrategy.totalBalance()
            : asset.balanceOf(address(this));


        assetBalances[0] = AssetBalance(address(asset), assetBalance);
    }

    /**
     * @notice Checkpoint the underlying idle strategy to get the latest balance.
     * If no checkpoint is required (eg AToken in aave doesn't need this) then
     * calling this will be identical to just calling `latestAssetBalances()`
     */
    function checkpointAssetBalances() external override returns (
        AssetBalance[] memory assetBalances
    ) {
        assetBalances = new AssetBalance[](1);

        // The sum of the balance in this contract, plus checkpoint and get 
        // the underlying idle strategy balance (if set)
        IOrigamiIdleStrategy _idleStrategy = idleStrategy;
        uint256 assetBalance = (address(_idleStrategy) != address(0))
            ? asset.balanceOf(address(this)) + _idleStrategy.checkpointTotalBalance()
            : asset.balanceOf(address(this));

        assetBalances[0] = AssetBalance(address(asset), assetBalance);
        emit AssetBalancesCheckpoint(assetBalances);
    }
}
