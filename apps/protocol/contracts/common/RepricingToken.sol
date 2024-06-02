pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/RepricingToken.sol)

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IRepricingToken } from "contracts/interfaces/common/IRepricingToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";

/// @notice A re-pricing token which implements the ERC20 interface.
/// Each minted RepricingToken represents 1 share.
/// 
///  reservesPerShare = numShares * totalReserves / totalSupply
/// Elevated access can add new reserves in order to increase the reservesPerShare.
/// These new reserves are vested per second, over a set period of time.
abstract contract RepricingToken is IRepricingToken, ERC20Permit, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;
    using SafeCast for uint256;

    /// @notice The fully vested reserve tokens
    /// @dev Comprised of both user deposited reserves (when new shares are issued)
    /// And also when new reserves are deposited by the protocol to increase the reservesPerShare
    /// (which vest in over time)
    uint128 public override vestedReserves;

    /// @notice Extra reserve tokens deposited by the protocol to increase the reservesPerShare
    /// @dev These vest in per second over `vestingDuration`
    uint128 public override pendingReserves;

    /// @notice When new reserves are added to increase the reservesPerShare, 
    /// they will vest over this duration (in seconds)
    uint48 public override reservesVestingDuration;

    /// @notice The time at which any accrued pendingReserves were last moved from `pendingReserves` -> `vestedReserves`
    uint48 public override lastVestingCheckpoint;

    /// @notice The token used to track reserves for this investment
    address public override immutable reserveToken;

    /// @notice The number of decimal on the reserveToken.
    uint8 internal immutable reserveTokenDecimals;

    constructor(
        string memory _name, 
        string memory _symbol, 
        address _reserveToken, 
        uint48 _reservesVestingDuration,
        address _initialOwner
    )
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        OrigamiElevatedAccess(_initialOwner)
    {
        reserveToken = _reserveToken;
        reservesVestingDuration = _reservesVestingDuration;
        reserveTokenDecimals = ERC20(reserveToken).decimals();
    }

    /// @notice Update the vesting duration for any new reserves being added.
    /// @dev This will first checkpoint any pending reserves, any carried over amount will be
    /// spread out over the new duration.
    function setReservesVestingDuration(uint48 _reservesVestingDuration) external onlyElevatedAccess {
        _checkpointAndAddReserves(vestedReserves, pendingReserves, 0);
        reservesVestingDuration = _reservesVestingDuration;
        emit ReservesVestingDurationSet(_reservesVestingDuration);
    }

    /// @notice Owner can recover tokens
    function recoverToken(address _token, address _to, uint256 _amount) external onlyElevatedAccess {
        // If the _token is the reserve token, the owner can only remove any surplus reserves (ie donation reserves).
        // It can't dip into the actual user or protocol added reserves. 
        // This includes any vested rewards plus any unvested (but pending) reserves
        if (_token == reserveToken) {
            uint256 _reservesBalance = IERC20(reserveToken).balanceOf(address(this));
            uint256 _surplusReserves = _reservesBalance - pendingReserves - uint256(vestedReserves);
            if (_amount > _surplusReserves) revert CommonEventsAndErrors.InvalidAmount(_token, _amount);
        }
        
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Returns the number of decimals used to get its user representation.
    /// @dev Uses the underlying reserve token's decimals
    function decimals() public view override returns (uint8) {
        return reserveTokenDecimals;
    }

    /// @notice The current amount of fully vested reserves plus any accrued pending reserves
    function totalReserves() public view override returns (uint256) {
        (uint128 accrued, ) = _unvestedReserves(pendingReserves);
        unchecked {
            // Unchecked safe because `accrued` was a uint128
            return uint256(accrued) + vestedReserves;
        }
    }

    /// @notice How many reserve tokens would one get given a single share, as of now
    function reservesPerShare() external view override returns (uint256) {
        return sharesToReserves(10 ** decimals());
    }
    
    /// @notice How many reserve tokens would one get given a number of shares, as of now
    function sharesToReserves(uint256 shares) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();

        // Returns reserves = 1:1 if no shares yet allocated
        // Round down for calculating reserves from shares
        return (_totalSupply == 0)
            ? shares
            : shares.mulDiv(totalReserves(), _totalSupply, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @notice How many shares would one get given a number of reserve tokens, as of now
    function reservesToShares(uint256 reserves) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();

        // Returns shares = 1:1 if no shares yet allocated
        // Not worth having a special check for totalReserves=0, it can revert with a panic
        // Round down for calculating shares from reserves
        return (_totalSupply == 0)
            ? reserves
            : reserves.mulDiv(_totalSupply, totalReserves(), OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @notice The accrued vs outstanding amount of pending reserve tokens which have
    /// not yet been fully vested.
    function unvestedReserves() external view override returns (uint256 accrued, uint256 outstanding) {
        (accrued, outstanding) = _unvestedReserves(pendingReserves);
    }

    /// @notice Add pull in and add reserve tokens, which slowly increases the reservesPerShare()
    /// @dev The new amount is vested in continuously per second over an `reservesVestingDuration`
    /// starting from now.
    /// If any amount was still pending and unvested since the previous `addReserves()`, it will be carried over.
    function addPendingReserves(uint256 amount) external override onlyElevatedAccess {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        emit PendingReservesAdded(amount);
        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), amount);

        (uint128 _vestedReserves, uint128 _pendingReserves) = _checkpointAndAddReserves(vestedReserves, pendingReserves, amount.encodeUInt128());
        _validateReservesBalance(_vestedReserves, _pendingReserves);
    }

    /// @notice Checkpoint any pending reserves as long as the `reservesVestingDuration` period has completely passed.
    /// @dev No economic benefit, but may be useful for book keeping purposes.
    function checkpointReserves() external override {
        if (block.timestamp - lastVestingCheckpoint < reservesVestingDuration) revert CannotCheckpointReserves(block.timestamp - lastVestingCheckpoint, reservesVestingDuration);
        _checkpointAndAddReserves(vestedReserves, pendingReserves, 0);
    }

    /// @notice Return the current estimated APR based on the pending reserves which are vesting per second
    /// into the totalReserves.
    /// @dev APR = annual reserve token rewards / total reserves
    function apr() external view returns (uint256 aprBps) {
        // Using the current pendingReserves which are being dripped in per second,
        // calculate the total number of reserves which would be added for the entire year.
        // The APR is then the total number of new rewards being added divided by
        // the last snapshot of vested rewards.
        uint256 _vestedReserves = vestedReserves;
        aprBps = (_vestedReserves == 0) ? 0 : (
            OrigamiMath.BASIS_POINTS_DIVISOR.mulDiv(
                pendingReserves * 365 days,
                reservesVestingDuration,  // reserve rewards per year
                OrigamiMath.Rounding.ROUND_DOWN
            ) / _vestedReserves // the last snapshot of vested rewards
        );
    }
    
    function _issueSharesFromReserves(
        uint256 reserveTokenAmount, 
        address recipient, 
        uint256 minSharesAmount
    ) internal returns (uint256 sharesAmount) {
        sharesAmount = reservesToShares(reserveTokenAmount);
        if (sharesAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (sharesAmount < minSharesAmount) revert CommonEventsAndErrors.Slippage(minSharesAmount, sharesAmount);

        // Mint shares to the user and add to the total reserves
        _mint(recipient, sharesAmount);

        uint128 _vestedReserves = vestedReserves = vestedReserves + reserveTokenAmount.encodeUInt128();
        emit VestedReservesAdded(reserveTokenAmount);

        _validateReservesBalance(_vestedReserves, pendingReserves);
    }

    /// @dev Check the invariant that the amount of reserve tokens held by this contract
    /// is at least the vestedReserves + pendingReserves
    function _validateReservesBalance(uint128 _vestedReserves, uint128 _pendingReserves) internal view {
        uint256 _balance = IERC20(reserveToken).balanceOf(address(this));
        uint256 _totalReserves;
        unchecked {
            // Unchecked safe because it upcasts from uint128 to uint256
            _totalReserves = uint256(_vestedReserves) + _pendingReserves;
        }

        if (_balance < _totalReserves) {
            revert CommonEventsAndErrors.InsufficientBalance(
                reserveToken, 
                _totalReserves, 
                _balance
            );
        }
    }

    function _redeemReservesFromShares(
        uint256 sharesAmount, 
        address from, 
        uint256 minReserveTokenAmount,
        address receiver
    ) internal returns (uint256 reserveTokenAmount) {
        if (balanceOf(from) < sharesAmount) revert CommonEventsAndErrors.InsufficientBalance(address(this), sharesAmount, balanceOf(from));

        reserveTokenAmount = sharesToReserves(sharesAmount);
        if (reserveTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (reserveTokenAmount < minReserveTokenAmount) revert CommonEventsAndErrors.Slippage(minReserveTokenAmount, reserveTokenAmount);

        // Burn the users shares and remove the reserves
        _burn(from, sharesAmount);

        (uint128 _vestedReserves, uint128 _pendingReserves) = (vestedReserves, pendingReserves);

        // In the unlikely event where the vested reserves are less than the amount to transfer,
        // force a checkpoint
        uint128 reserveTokenAmount128 = reserveTokenAmount.encodeUInt128();
        if (_vestedReserves < reserveTokenAmount128) {
            (_vestedReserves, _pendingReserves) = _checkpointAndAddReserves(_vestedReserves, _pendingReserves, 0);
        }

        vestedReserves = _vestedReserves = _vestedReserves - reserveTokenAmount128;
        emit VestedReservesRemoved(reserveTokenAmount);

        if (receiver != address(this)) {
            IERC20(reserveToken).safeTransfer(receiver, reserveTokenAmount);
        }

        _validateReservesBalance(_vestedReserves, _pendingReserves);
    }

    /// @dev Checkpoint by moving any `pendingReserves` which have vested to the `vestedReserves`.
    /// Any unvested balance is added to `newReserves` to become the new `pendingReserves` which will start
    /// vesting from now.
    function _checkpointAndAddReserves(
        uint128 oldVestedReserves, 
        uint128 oldPendingReserves, 
        uint128 newReserves
    ) internal returns (uint128 newVestedReserves, uint128 newPendingReserves) {
        (uint128 accrued, uint128 outstanding) = _unvestedReserves(oldPendingReserves);

        vestedReserves = newVestedReserves = oldVestedReserves + accrued;
        pendingReserves = newPendingReserves = outstanding + newReserves;
        lastVestingCheckpoint = uint48(block.timestamp);

        emit ReservesCheckpoint(newVestedReserves, accrued, outstanding, newReserves);
    }

    function _unvestedReserves(uint128 _pendingReserves) internal view returns (uint128 accrued, uint128 outstanding) {
        uint48 _vestingDuration = reservesVestingDuration;
        uint48 secsSinceLastCheckpoint;
        unchecked {
            secsSinceLastCheckpoint = uint48(block.timestamp) - lastVestingCheckpoint;
        }

        // The whole amount has been accrued (vested but not yet added to `vestedReserves`) 
        // if the time since the last checkpoint has passed the vesting duration
        accrued = (secsSinceLastCheckpoint >= _vestingDuration)
            ? _pendingReserves
            : _pendingReserves * secsSinceLastCheckpoint / _vestingDuration;

        // Any amount not yet vested, to be carried over
        unchecked {
            // Unchecked safe because `accrued` guaranteed to be <= `_pendingReserves`
            outstanding = _pendingReserves - accrued;
        }
    }
}
