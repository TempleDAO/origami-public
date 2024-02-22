pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/IRepricingToken.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

/// @notice A re-pricing token which implements the ERC20 interface.
/// Each minted RepricingToken represents 1 share.
/// 
///  pricePerShare = numShares * totalReserves / totalSupply
/// Elevated access can increase the totalReserves in order to increase the pricePerShare
interface IRepricingToken is IERC20, IERC20Permit {
    /// @notice The token used to track reserves for this investment
    function reserveToken() external view returns (address);

    /// @notice The fully vested reserve tokens
    /// @dev Comprised of both user deposited reserves (when new shares are issued)
    /// And also when new reserves are deposited by the protocol to increase the reservesPerShare
    /// (which vest in over time)
    function vestedReserves() external returns (uint256);

    /// @notice Extra reserve tokens deposited by the protocol to increase the reservesPerShare
    /// @dev These vest in per second over `vestingDuration`
    function pendingReserves() external returns (uint256);

    /// @notice When new reserves are added to increase the reservesPerShare, 
    /// they will vest over this duration (in seconds)
    function reservesVestingDuration() external returns (uint256);

    /// @notice The time at which any accrued pendingReserves were last moved from `pendingReserves` -> `vestedReserves`
    function lastVestingCheckpoint() external returns (uint256);

    /// @notice The current amount of fully vested reserves plus any accrued pending reserves
    function totalReserves() external view returns (uint256);

    /// @notice How many reserve tokens would one get given a single share, as of now
    function reservesPerShare() external view returns (uint256);

    /// @notice How many reserve tokens would one get given a number of shares, as of now
    function sharesToReserves(uint256 shares) external view returns (uint256);

    /// @notice How many shares would one get given a number of reserve tokens, as of now
    function reservesToShares(uint256 reserves) external view returns (uint256);

    /// @notice The accrued vs outstanding amount of pending reserve tokens which have
    /// not yet been fully vested.
    function unvestedReserves() external view returns (uint256 accrued, uint256 outstanding);

    /// @notice Add pull in and add reserve tokens, which slowly increases the pricePerShare()
    /// @dev The new amount is vested in continuously per second over an `reservesVestingDuration`
    /// starting from now.
    /// If any amount was still pending and unvested since the previous `addReserves()`, it will be carried over.
    function addPendingReserves(uint256 amount) external;

    /// @notice Checkpoint any pending reserves as long as the `reservesVestingDuration` period has completely passed.
    /// @dev No economic benefit, but may be useful for book keeping purposes.
    function checkpointReserves() external;

    /// @notice Return the current estimated APR based on the pending reserves which are vesting per second
    /// into the totalReserves.
    /// @dev APR = annual reserve token rewards / total reserves
    function apr() external view returns (uint256 aprBps);
}