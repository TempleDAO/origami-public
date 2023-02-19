pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/RepricingToken.sol)

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRepricingToken} from "../interfaces/common/IRepricingToken.sol";
import {CommonEventsAndErrors} from "./CommonEventsAndErrors.sol";
import {Operators} from "./access/Operators.sol";

/// @notice A re-pricing token which implements the ERC20 interface.
/// Each minted RepricingToken represents 1 share.
/// 
///  pricePerShare = numShares * totalReserves / totalSupply
/// So operators can increase the totalReserves in order to increase the pricePerShare
abstract contract RepricingToken is IRepricingToken, ERC20Permit, Ownable, Operators {
    using SafeERC20 for IERC20;

    /// @notice The token used to track reserves for this investment
    address public override immutable reserveToken;

    /// @notice The total number of `reserveToken()` this investment holds.
    uint256 public override totalReserves;

    event IssueSharesFromReserves(address indexed user, address indexed recipient, uint256 reserveTokenAmount, uint256 sharesAmount);
    event RedeemReservesFromShares(address indexed user, address indexed recipient, uint256 sharesAmount, uint256 reserveTokenAmount);
    event ReservesAdded(uint256 amount);
    event ReservesRemoved(uint256 amount);

    constructor(string memory _name, string memory _symbol, address _reserveToken)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {
        reserveToken = _reserveToken;
    }

    /// @notice Grant `_account` the operator role
    function addOperator(address _account) external override onlyOwner {
        _addOperator(_account);
    }

    /// @notice Revoke the operator role from `_account`
    function removeOperator(address _account) external override onlyOwner {
        _removeOperator(_account);
    }

    /// @notice Owner can recover tokens
    function recoverToken(address _token, address _to, uint256 _amount) external onlyOwner {
        // If the _token is the reserve token, the owner can only remove any surplus reserves (ie donation reserves).
        // It can't dip into the actual reserves
        if (_token == reserveToken) {
            uint256 bal = IERC20(reserveToken).balanceOf(address(this));
            if (_amount > (bal - totalReserves)) revert CommonEventsAndErrors.InvalidAmount(_token, _amount);
        }
        
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Returns the number of decimals used to get its user representation.
    /// @dev Uses the underlying reserve token's decimals
    function decimals() public view override returns (uint8) {
        return ERC20(reserveToken).decimals();
    }

    /// @notice The price for a single share in terms of the `reserveToken`
    function reservesPerShare() external view override returns (uint256) {
        return sharesToReserves(10 ** decimals());
    }
    
    /// @notice How many reserve tokens given a number of shares
    function sharesToReserves(uint256 shares) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();

        // Returns 0 if no shares yet allocated
        return (_totalSupply == 0)
            ? 0
            : shares * totalReserves / _totalSupply;
    }

    /// @notice How many shares given a number of reserve tokens
    function reservesToShares(uint256 reserves) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();

        // Returns shares = 1:1 if no shares yet allocated
        // Not worth having a special check for totalReserves=0, it can revert
        return (_totalSupply == 0)
            ? reserves
            : reserves * _totalSupply / totalReserves;
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
        _addReserves(reserveTokenAmount);
    }

    function _redeemReservesFromShares(
        uint256 sharesAmount, 
        address from, 
        uint256 minReserveTokenAmount
    ) internal returns (uint256 reserveTokenAmount) {
        if (balanceOf(from) < sharesAmount) revert CommonEventsAndErrors.InsufficientBalance(address(this), sharesAmount, balanceOf(from));

        reserveTokenAmount = sharesToReserves(sharesAmount);
        if (reserveTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (reserveTokenAmount < minReserveTokenAmount) revert CommonEventsAndErrors.Slippage(minReserveTokenAmount, reserveTokenAmount);

        // Burn the users shares and remove the reserves
        _burn(from, sharesAmount);
        _removeReserves(reserveTokenAmount);
    }

    /// @notice Add reserve tokens, increasing the pricePerShare()
    function addReserves(uint256 amount) external override onlyOperators {
        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), amount);
        _addReserves(amount);
    }

    /// @dev Reserve tokens should be transferred into this contract PRIOR to calling this function
    function _addReserves(uint256 amount) private {
        emit ReservesAdded(amount);
        totalReserves += amount;
        assert(IERC20(reserveToken).balanceOf(address(this)) >= totalReserves);
    }

    /// @dev Reserve tokens need be transferred out of the contract AFTER calling this function
    function _removeReserves(uint256 amount) private {
        emit ReservesRemoved(amount);
        totalReserves -= amount;
        assert((IERC20(reserveToken).balanceOf(address(this)) - amount) >= totalReserves);
    }
}
