pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/IRepricingToken.sol)

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

/// @notice A re-pricing token which implements the ERC20 interface.
/// Each minted RepricingToken represents 1 share.
/// 
///  pricePerShare = numShares * totalReserves / totalSupply
/// So operators can increase the totalReserves in order to increase the pricePerShare
interface IRepricingToken is IERC20, IERC20Permit {
    /// @notice The token used to track reserves for this investment
    function reserveToken() external view returns (address);

    /// @notice The total number of `reserveToken()` this investment holds.
    function totalReserves() external view returns (uint256);

    /// @notice The price for a single share in terms of the `reserveToken`
    function reservesPerShare() external view returns (uint256);

    /// @notice Add reserve tokens, increasing the pricePerShare()
    function addReserves(uint256 amount) external;

    /// @notice Remove reserve tokens, reducing the pricePerShare()
    function removeReserves(uint256 amount) external;
}