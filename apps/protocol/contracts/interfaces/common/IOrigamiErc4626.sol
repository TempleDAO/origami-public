pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/IOrigamiErc4626.sol)

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title Origami ERC-4626
 * @notice A fork of the openzeppelin ERC-4626, with:
 *  - `_decimalsOffset()` set to zero (OZ defaults to zero anyway)
 *  - Always has decimals() of 18dp (rather than using the underlying asset)
 *  - Deposit and Withdraw fees, which are taken from the _shares_ of the user,
 *    benefiting the existing vault holders.
 *  - Permit support
 *  - IERC165 support
 *  - Reentrancy guard on deposit/mint/withdraw/redeem
 *  - maxRedeem & maxWithdraw for address(0) returns the total vault capacity (given any caps within the implementation) 
 *    which can be withdrawn/redeemed (rather than always returning zero)
 */
interface IOrigamiErc4626 is 
    IERC4626, 
    IERC20Permit, 
    IERC165, 
    IERC5267
{
    /// @dev Attempted to deposit more assets than the max amount for `receiver`.
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    /// @dev Attempted to mint more shares than the max amount for `receiver`.
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);

    /// @dev Attempted to withdraw more assets than the max amount for `receiver`.
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    /// @dev Attempted to redeem more shares than the max amount for `receiver`.
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    /// @dev Permit deadline has expired.
    error ERC2612ExpiredSignature(uint256 deadline);

    /// @dev Mismatched signature.
    error ERC2612InvalidSigner(address signer, address tokensOwner);

    /// @dev What kind of fees - either Deposit or withdrawal
    enum FeeType {
        DEPOSIT_FEE,
        WITHDRAWAL_FEE
    }

    /// @dev Either deposit or withdrawal fees have been updated
    event FeeBpsSet(FeeType feeType, uint256 feeBps);

    /// @dev Either deposit or withdrawal fees have been applied
    event InKindFees(FeeType feeType, uint256 feeBps, uint256 feeAmount);

    /// @dev A client implementation may emit if the max total supply has been changed
    event MaxTotalSupplySet(uint256 maxTotalSupply);

    /// @notice Set the max total supply allowed for this vault
    /// @dev Will revert if the current totalSupply is zero as
    /// `seedDeposit()` needs to be called first
    function setMaxTotalSupply(uint256 maxTotalSupply) external;

    /// @notice Origami protocol seeds the initial deposit
    /// @dev The new maxTotalSupply is set and a trusted deposit
    /// is made
    function seedDeposit(
        uint256 assets,
        address receiver,
        uint256 maxTotalSupply
    ) external returns (uint256 shares);

    /// @notice The current deposit fee in basis points.
    function depositFeeBps() external view returns (uint256);

    /// @notice The current withdrawal fee in basis points.
    function withdrawalFeeBps() external view returns (uint256);

    /// @notice The current maximum total supply of vault tokens.
    function maxTotalSupply() external view returns (uint256);

    /// @notice Whether deposit/mint is currently paused
    function areDepositsPaused() external view returns (bool);

    /// @notice Whether withdrawal/redeem is currently paused
    function areWithdrawalsPaused() external view returns (bool);
}
