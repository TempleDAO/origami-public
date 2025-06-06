pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { IOrigamiTeleportableToken } from "contracts/interfaces/common/omnichain/IOrigamiTeleportableToken.sol";

/**
 * @title Origami Tokenized Balance Sheet Vault
 * @notice A bit more of an opinionated version for our reference implementations
 */
interface IOrigamiTokenizedBalanceSheetVault is 
    ITokenizedBalanceSheetVault,
    IOrigamiTeleportableToken
{
    //============================================================================================//
    //                                           ERRORS                                           //
    //============================================================================================//
    
    /// @dev Attempted to deposit more assets than the max amount for `receiver`.
    error ExceededMaxJoinWithToken(address receiver, address tokenAddress, uint256 tokenAmount, uint256 max);

    /// @dev Attempted to mint more shares than the max amount for `receiver`.
    error ExceededMaxJoinWithShares(address receiver, uint256 shares, uint256 max);

    /// @dev Attempted to withdraw more assets than the max amount for `receiver`.
    error ExceededMaxExitWithToken(address owner, address tokenAddress, uint256 tokenAmount, uint256 max);

    /// @dev Attempted to redeem more shares than the max amount for `receiver`.
    error ExceededMaxExitWithShares(address owner, uint256 shares, uint256 max);
    
    //============================================================================================//
    //                                           EVENTS                                           //
    //============================================================================================//

    /// @dev What kind of fees - either Join or Exit
    enum FeeType {
        JOIN_FEE,
        EXIT_FEE
    }

    /// @dev Either join or exit fees have been applied
    event InKindFees(FeeType feeType, uint256 feeBps, uint256 feeAmount);

    /// @dev Emit when the max total supply has been changed
    event MaxTotalSupplySet(uint256 maxTotalSupply);

    /// @dev May be emitted if the vault sets a TokenPrices contract (used within the UI only)
    event TokenPricesSet(address indexed tokenPrices);

    /// @dev May be emitted if the vault sets a manager contract for delegated logic
    event ManagerSet(address indexed manager);

    //============================================================================================//
    //                                          ADMIN                                             //
    //============================================================================================//

    /// @notice Elevated access seeds the vault, specifying each of the asset amounts, the liability amounts,
    /// and the shares to joinWithShares. This determines the initial share price of each asset and liability.
    function seed(
        uint256[] calldata assetAmounts,
        uint256[] calldata liabilityAmounts,
        uint256 sharesToMint,
        address receiver,
        uint256 newMaxTotalSupply
    ) external;

    /// @notice Set the max total supply allowed for this vault
    /// @dev Will revert if the current totalSupply is zero as
    /// `seedDeposit()` needs to be called first
    function setMaxTotalSupply(uint256 maxTotalSupply) external;

    /// @notice Allows the caller to burn their own supply of vault shares.
    function burn(uint256 amount) external;

    //============================================================================================//
    //                                          VIEWS                                             //
    //============================================================================================//

    /// @notice The current joinWithShares or joinWithTokens fee in basis points.
    function joinFeeBps() external view returns (uint256);

    /// @notice The current exitToShares or exitToTokens fee in basis points.
    function exitFeeBps() external view returns (uint256);

    /// @notice The maxiumum total supply of shares for this vault.
    /// @dev may be set up to type(uint256).max
    function maxTotalSupply() external view returns (uint256 shares);

    /// @notice The available shares which can be minted as of now, under the maxTotalSupply
    /// @dev If maxTotalSupply() is type(uint256).max, then this will also be type(uint256).max
    function availableSharesCapacity() external view returns (uint256 shares);

    /// @notice Whether joinWithShares and joinWithAssets are currently paused
    function areJoinsPaused() external view returns (bool);

    /// @notice Whether exitToShares and exitToAssets are currently paused
    function areExitsPaused() external view returns (bool);
}