pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev A subset of the latest ITokenizedBalanceSheetVault interface
/// which does NOT support tokensHash for joins/exits. Internally used only.
interface ITokenizedBalanceSheetVaultV1 is IERC20, IERC20Metadata {
    /// @dev Emitted during a joinWithToken or joinWithShares
    event Join(address indexed sender, address indexed owner, uint256[] assets, uint256[] liabilities, uint256 shares);

    /// @dev Emitted during a exitWithToken or exitWithShares
    event Exit(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256[] assets,
        uint256[] liabilities,
        uint256 shares
    );

    /**
     * @notice Returns the addresses of the underlying tokens which represent the ASSETS and LIABILITIES in the Vault's
     * balance sheet
     * @dev
     * - MUST be ERC-20 token contracts.
     * - MUST NOT revert.
     *
     * NOTE: tokens MAY be added or removed over time.
     */
    function tokens() external view returns (address[] memory assetTokens, address[] memory liabilityTokens);

    /**
     * @notice Returns the total amount of the ASSETS and LIABILITIES managed by this vault.
     * @dev
     * - `totalAssets` MUST return a list which is the same size and order as `assetTokens()`
     * - `totalLiabilities` MUST return a list which is the same size and order as `liabilityTokens()`
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function balanceSheet() external view returns (uint256[] memory totalAssets, uint256[] memory totalLiabilities);

    /**
     * @notice Returns the amount of shares that the Vault would exchange for the amount of `tokenAddress` provided, in
     * an ideal
     * scenario where all the conditions are met.
     * The address and exact number of tokens of one of the `tokens()` is specified.
     * The remaining assets and liabilities are derived from the current balance sheet, along with the number of shares
     * that would represent.
     *  @dev
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     * - If `tokenAddress` is not one of the `tokens()` then shares, assets and libilities MUST have zero amounts.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertFromToken(address tokenAddress, uint256 tokenAmount)
        external
        view
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Returns the amount of assets and liabilities that the Vault would exchange for the amount of shares
     * provided, in an ideal
     * scenario where all the conditions are met.
     * The assets and liabilities are derived from the current balance sheet.
     * @dev
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: this calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertFromShares(uint256 shares)
        external
        view
        returns (uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Returns the maximum amount of `tokenAddress` that can be joined into the vault for the `receiver`,
     * through a joinWithToken call
     * `tokenAddress` must represent one of the assetTokens or liabilityTokens within `tokens()`
     * @dev
     * - MUST return a limited value if receiver is subject to some limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of `tokenAddress` that may be joined.
     * - MUST NOT revert.
     * - If `tokenAddress` is not one of the `tokens()` then this MUST return 0.
     */
    function maxJoinWithToken(address tokenAddress, address receiver) external view returns (uint256 maxTokens);

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their joined at the current block, given
     * current on-chain conditions.
     * The address and exact number of tokens of one of the `tokens()` is specified.
     * The remaining assets and liabilities are derived from the current balance sheet, along with the number of shares
     * that would represent.
     * @dev
     * - MUST return the `shares` as close to and NO MORE than the exact amount of Vault shares
     *    that would be minted in a joinWithToken call in the same transaction (ie round down).
     * - MUST return the `assets` as close to and NO LESS than the exact amount of tokens
     *    transferred FROM the sender for a joinWithToken call in the same transaction (ie round up).
     * - MUST return the `liabilities` as close to and NO MORE than the exact amount of tokens
     *    transferred TO the receiver for a joinWithToken call in the same transaction (ie round down).
     * - MUST NOT account for join limits like those returned from maxJoinWithToken and should always act as though the
     *    join would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of join fees. Integrators should be aware of the existence of join fees.
     * - MUST NOT revert.
     * - If `tokenAddress` is not one of the `tokens()` then shares, assets and libilities MUST have zero amounts.
     */
    function previewJoinWithToken(address tokenAddress, uint256 tokenAmount)
        external
        view
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Mints Vault shares to receiver by transferring an exact amount of underlying tokens proportional to the
     * current balance sheet.
     * The address and exact number of tokens of one of the `tokens()` is specified.
     * The remaining assets and liabilities are derived from the current balance sheet, along with the number of shares
     * that would represent.
     * @dev
     * - MUST emit the Join event
     * - MUST revert if all of assets cannot be joined (due to join limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with all of the asset tokens
     */
    function joinWithToken(address tokenAddress, uint256 tokenAmount, address receiver)
        external
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Returns the maximum amount of the Vault shares that can be minted for the `receiver`, through a
     * joinWithShares call.
     * @dev
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of shares that may be minted.
     * - MUST NOT revert.
     */
    function maxJoinWithShares(address receiver) external view returns (uint256 maxShares);

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their joinWithShares at the current
     * block, given
     * current on-chain conditions.
     * The assets and liabilities are derived from the current balance sheet for that number of shares.
     * @dev
     * - MUST return the `assets` as close to and NO LESS than the exact amount of tokens
     *    transferred FROM the sender for a joinWithShares call in the same transaction (ie round up).
     * - MUST return the `liabilities` as close to and NO MORE than the exact amount of tokens
     *    transferred TO the receiver for a joinWithShares call in the same transaction (ie round down).
     * - MUST NOT account for mint limits like those returned from maxJoinWithShares and should always act as though the
     *    joinWithShares would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of join fees. Integrators should be aware of the existence of join fees.
     * - MUST NOT revert.
     */
    function previewJoinWithShares(uint256 shares)
        external
        view
        returns (uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Mints exactly `shares` Vault shares to receiver by joining amount of underlying tokens.
     * The assets and liabilities are derived from the current balance sheet for that number of shares.
     * @dev
     * - MUST emit the Join event
     * - MUST revert if all of shares cannot be minted (due to join limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with all of the asset tokens
     */
    function joinWithShares(uint256 shares, address receiver)
        external
        returns (uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Returns the maximum amount of `tokenAddress` that can be withdrawn from the vault given the owner balance
     * in the vault,
     * through a exitWithToken call
     * `tokenAddress` must represent one of the assetTokens or liabilityTokens within `tokens()`
     * @dev
     * - MUST return a limited value if owner is subject to some exit limit or timelock.
     * - MUST NOT revert.
     * - If `tokenAddress` is not one of the `tokens()` then this MUST return 0.
     */
    function maxExitWithToken(address tokenAddress, address owner) external view returns (uint256 maxTokens);

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their exit at the current block,
     * given current on-chain conditions.
     * The address and exact number of tokens of one of the `tokens()` is specified.
     * The remaining assets and liabilities are derived from the current balance sheet, along with the number of shares
     * that would represent.
     * @dev
     * - MUST return the `shares` as close to and NO LESS than the exact amount of Vault shares
     *    that would be burned in a exitWithToken call in the same transaction. (ie round up)
     * - MUST return the `assets` as close to and NO MORE than the exact amount of tokens
     *    transferred TO the sender for a exitWithToken call in the same transaction (ie round down).
     * - MUST return the `liabilities` as close to and NO LESS than the exact amount of tokens
     *    transferred FROM the receiver for a exitWithToken call in the same transaction (ie round up).
     * - MUST NOT account for exit limits like those returned from maxExitWithToken and should always act as though the
     *    exit would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of exit fees. Integrators should be aware of the existence of exit fees.
     * - MUST NOT revert.
     * - If `tokenAddress` is not one of the `tokens()` then shares, assets and libilities MUST have zero amounts.
     */
    function previewExitWithToken(address tokenAddress, uint256 tokenAmount)
        external
        view
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Burns shares from owner, sends exactly `tokenAddress` of underlying tokens to receiver.
     * The address and exact number of tokens of one of the `tokens()` is specified.
     * The remaining assets and liabilities are derived from the current balance sheet, along with the number of shares
     * that would represent.
     * @dev
     * - MUST emit the Exit event.
     * - MUST revert if all of assets cannot be withdrawn (due to exit limit being reached, slippage, the owner
     *    not having enough shares, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with all of the liability tokens.
     */
    function exitWithToken(address tokenAddress, uint256 tokenAmount, address receiver, address owner)
        external
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Returns the maximum amount of Vault shares that can be redeemed from the vault given the owner balance in
     * the vault,
     * through a exitWithShares call.
     * @dev
     * - MUST return a limited value if owner is subject to some exit limit or timelock.
     * - MUST return balanceOf(owner) if owner is not subject to any exit limit or timelock.
     * - MUST NOT revert.
     */
    function maxExitWithShares(address owner) external view returns (uint256 maxShares);

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their redemption at the current block,
     * given current on-chain conditions.
     * The assets and liabilities are derived from the current balance sheet for that number of shares.
     * @dev
     * - MUST return the `assets` as close to and NO MORE than the exact amount of tokens
     *    transferred TO the sender for a exitWithShares call in the same transaction (ie round down).
     * - MUST return the `liabilities` as close to and NO LESS than the exact amount of tokens
     *    transferred FROM the receiver for a exitWithShares call in the same transaction (ie round up).
     * - MUST NOT account for redemption limits like those returned from maxExitWithShares and should always act as
     * though the
     *    redemption would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of exit fees. Integrators should be aware of the existence of exit fees.
     * - MUST NOT revert.
     */
    function previewExitWithShares(uint256 shares)
        external
        view
        returns (uint256[] memory assets, uint256[] memory liabilities);

    /**
     * @notice Burns shares from owner.
     * The assets and liabilities are derived from the current balance sheet for that number of shares.
     * @dev
     * - MUST emit the Exit event.
     * - MUST revert if all of assets cannot be redeemed (due to exit limit being reached, slippage, the owner
     *    not having enough shares, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with all of the liability tokens.
     */
    function exitWithShares(uint256 shares, address receiver, address owner)
        external
        returns (uint256[] memory assets, uint256[] memory liabilities);
}
