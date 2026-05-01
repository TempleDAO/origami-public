pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {
    ITokenizedBalanceSheetVault
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { IOrigamiTeleportableToken } from "contracts/interfaces/common/omnichain/IOrigamiTeleportableToken.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

/**
 * @title Origami Tokenized Balance Sheet Vault
 * @notice A bit more of an opinionated version for our reference implementations
 */
interface IOrigamiTokenizedBalanceSheetVault is ITokenizedBalanceSheetVault, IOrigamiTeleportableToken {
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
    /// @param assetAmounts The per token total of assets to seed the vault with
    /// @param liabilityAmounts The per token total of liabilities to seed the vault with
    /// @param sharesToMint The number of shares to mint to the receiver
    /// @param receiver Receives the initial shares and liabilities
    /// @param newMaxTotalSupply The initial maximum total supply cap allowed for this vault
    /// @param balanceSheetData Any encoded state required by the implementation to allocate the total assets
    ///        and liabilities. For example if the total needs to be split across multiple positions.
    function seed(
        uint256[] calldata assetAmounts,
        uint256[] calldata liabilityAmounts,
        uint256 sharesToMint,
        address receiver,
        uint256 newMaxTotalSupply,
        bytes calldata balanceSheetData
    ) external;

    /// @notice Set the max total supply allowed for this vault
    /// @dev Will revert if the current totalSupply is zero as
    /// `seedDeposit()` needs to be called first
    function setMaxTotalSupply(uint256 maxTotalSupply) external;

    /// @notice Update the current tokens hash based on the assetTokens and liabilityTokens
    /// in the balance sheet
    function updateCurrentTokensHash() external;

    /// @notice Allows the caller to burn their own supply of vault shares.
    function burn(uint256 amount) external;

    /// @notice Set the helper to calculate current off-chain/subgraph integration
    function setTokenPrices(address tokenPrices) external;

    /// @notice Set the Origami delegated manager
    function setManager(address manager) external;

    //============================================================================================//
    //                                          VIEWS                                             //
    //============================================================================================//

    /**
     * @notice Returns the addresses of the underlying tokens which represent the ASSETS in the Vault's balance sheet
     * @dev
     * - MUST be ERC-20 token contracts.
     * - MUST NOT revert.
     *
     * NOTE: tokens MAY be added or removed over time.
     */
    function assetTokens() external view returns (address[] memory tokens);

    /**
     * @notice Returns the addresses of the underlying tokens which represent the LIABILITIES in the Vault's balance
     * sheet
     * @dev
     * - MUST be ERC-20 token contracts.
     * - MUST NOT revert.
     *
     * NOTE: tokens MAY be added or removed over time.
     */
    function liabilityTokens() external view returns (address[] memory tokens);

    /// @dev To report whether a token is invalid, an asset, or a liability in this balance sheet
    enum AssetOrLiability {
        INVALID,
        ASSET,
        LIABILITY
    }

    /// @notice Return whether the input tokenAddress is part of the balance sheet assets or liabilities, and the index
    /// of that address in the respective assetTokens() or liabilityTokens() list
    /// - kind === ASSET if an asset
    /// - kind === LIABILITY if a liability
    /// - kind === INVALID if not an asset or liability (index will be zero in this case)
    function matchToken(address tokenAddress) external view returns (AssetOrLiability kind, uint256 index);

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

    /// @notice The helper contract to retrieve Origami USD prices
    /// @dev Required for off-chain/subgraph integration
    function tokenPrices() external view returns (ITokenPrices);

    /// @notice The Origami contract managing the application of
    /// the deposit tokens into the underlying protocol
    function manager() external view returns (address);
}
