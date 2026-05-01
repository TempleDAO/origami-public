pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/OrigamiTBSLib.sol)

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import {
    IOrigamiTokenizedBalanceSheetVault as ITBSV
} from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

/// @dev Internal state cache of the balance sheet and input parameters.
/// This should be populated upfront before any actions are performed on the vault,
/// and intended to immutable after that -- it should not be updated through the lifecycle of the transaction.
/// Motivation: Saves duplicated state and STATICCALL's, as well as circumventing stack-too-deep issues
struct TBSState {
    /// @dev The current list of asset tokens in the TBS
    address[] assetAddresses;

    /// @dev The current list of liability tokens in the TBS
    address[] liabilityAddresses;

    /// @dev The current balances of the assetTokens() in the balance sheet
    uint256[] assetBalances;

    /// @dev The current balances of the liabilityTokens() in the balance sheet
    uint256[] liabilityBalances;

    /// @dev The totalSupply of the vault
    uint256 totalSupply;

    /// @dev If the input token address is an asset/liability or neither
    ITBSV.AssetOrLiability inputTokenKind;

    /// @dev The index of the input token address. Always zero if invalid
    uint256 inputTokenIndex;

    /// @dev The amount of the input token. Set to zero if the token balance of
    /// the input token address in the balance sheet is zero
    uint256 inputTokenAmount;

    /// @dev Any encoded state required by the implementation to allocate the total assets and liabilities.
    /// For example if the total needs to be split across multiple positions.
    /// May be left empty
    bytes balanceSheetData;
}

/// @dev A library to operate on cached Tokenized Balance Sheet state
library OrigamiTBSLib {
    using OrigamiMath for uint256;

    function _matchAmount(
        ITBSV.AssetOrLiability inputTokenKind,
        uint256 inputTokenIndex,
        uint256[] memory assetAmounts,
        uint256[] memory liabilityAmounts
    ) private pure returns (uint256 amount) {
        if (inputTokenKind == ITBSV.AssetOrLiability.ASSET) {
            return assetAmounts[inputTokenIndex];
        } else if (inputTokenKind == ITBSV.AssetOrLiability.LIABILITY) {
            return liabilityAmounts[inputTokenIndex];
        }

        // If INVALID return 0
    }

    function inputTokenBalance(TBSState memory $) internal pure returns (uint256 balance) {
        return _matchAmount($.inputTokenKind, $.inputTokenIndex, $.assetBalances, $.liabilityBalances);
    }

    /// @dev The available shares which can be minted as of now, under the maxTotalSupply
    /// If maxTotalSupply() is type(uint256).max, then this will also be type(uint256).max
    function availableSharesCapacity(uint256 totalSupply_, uint256 maxTotalSupply_)
        internal
        pure
        returns (uint256 shares)
    {
        if (maxTotalSupply_ == type(uint256).max) return maxTotalSupply_;

        if (totalSupply_ > maxTotalSupply_) {
            shares = 0;
        } else {
            unchecked {
                shares = maxTotalSupply_ - totalSupply_;
            }
        }
    }

    /// @dev Return whether the tokenAddress is part of the balance sheet assets or liabilities, and the index
    /// of that address in the respective assetTokens() or liabilityTokens() list
    /// - kind === ASSET if an asset
    /// - kind === LIABILITY if a liability
    /// - kind === INVALID if not an asset or liability (index will be zero in this case)
    function matchToken(address tokenAddress, address[] memory assetAddresses, address[] memory liabilityAddresses)
        internal
        pure
        returns (ITBSV.AssetOrLiability kind, uint256 index)
    {
        uint256 i;
        for (; i < assetAddresses.length; ++i) {
            if (assetAddresses[i] == tokenAddress) {
                return (ITBSV.AssetOrLiability.ASSET, i);
            }
        }

        for (i = 0; i < liabilityAddresses.length; ++i) {
            if (liabilityAddresses[i] == tokenAddress) {
                return (ITBSV.AssetOrLiability.LIABILITY, i);
            }
        }

        // Leave uninitialized as ITBSV.AssetOrLiability.INVALID
    }

    /// @dev Convert an amount of one of the asset/liability tokens (specified in the `$` state) into
    /// the full set of shares/assets/liabilities.
    /// Based off the balance of that token in the vault and total supply of shares
    function convertInputTokenAmountToSharesAndTokens(
        TBSState memory $,
        OrigamiMath.Rounding sharesRounding,
        OrigamiMath.Rounding assetsRounding,
        OrigamiMath.Rounding liabilitiesRounding
    ) internal pure returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities) {
        shares = tokenToShares($.inputTokenAmount, inputTokenBalance($), $.totalSupply, sharesRounding);

        (assets, liabilities) = proportionalTokenAmountsFromShares({
            shares: shares, $: $, assetsRounding: assetsRounding, liabilitiesRounding: liabilitiesRounding
        });
    }

    /// @dev For each of the asset and liability tokens, calculate the proportional token
    /// amount given an amount of shares and the current total supply
    function proportionalTokenAmountsFromShares(
        TBSState memory $,
        uint256 shares,
        OrigamiMath.Rounding assetsRounding,
        OrigamiMath.Rounding liabilitiesRounding
    ) internal pure returns (uint256[] memory assets, uint256[] memory liabilities) {
        assets = _proportionalTokenAmountsFromShares($, shares, ITBSV.AssetOrLiability.ASSET, assetsRounding);
        liabilities =
            _proportionalTokenAmountsFromShares($, shares, ITBSV.AssetOrLiability.LIABILITY, liabilitiesRounding);
    }

    function sharesToToken(uint256 shares, uint256 tokenBalance, uint256 totalSupply, OrigamiMath.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return totalSupply == 0 ? 0 : shares.mulDiv(tokenBalance, totalSupply, rounding);
    }

    function tokenToShares(
        uint256 tokenAmount,
        uint256 tokenBalance,
        uint256 totalSupply,
        OrigamiMath.Rounding rounding
    ) internal pure returns (uint256) {
        return tokenBalance == 0 ? 0 : tokenAmount.mulDiv(totalSupply, tokenBalance, rounding);
    }

    /// @dev For each token in either asset or liability tokens (specified by `forKind`),
    /// calculate the proportional token amount given an amount of shares and the current total supply
    ///   otherTokenAmount = shares * otherTokenBalance / totalSupply
    function _proportionalTokenAmountsFromShares(
        TBSState memory $,
        uint256 shares,
        ITBSV.AssetOrLiability forKind,
        OrigamiMath.Rounding rounding
    ) private pure returns (uint256[] memory amounts) {
        uint256 length = forKind == ITBSV.AssetOrLiability.ASSET ? $.assetBalances.length : $.liabilityBalances.length;
        amounts = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            if ($.totalSupply == 0) {
                // denominator is zero
                amounts[i] = 0;
            } else if (i == $.inputTokenIndex && $.inputTokenKind == forKind) {
                // If this if for the specified input token kind and index, use that amount exactly
                // rather than a rounded calculation which could cause some differences
                amounts[i] = $.inputTokenAmount;
            } else {
                // Calculate the amount as `shares * balance[i] / totalSupply`
                amounts[i] = sharesToToken(shares, _tokenBalance($, forKind, i), $.totalSupply, rounding);
            }
        }
    }

    /// @dev Get the cached token balance for a given kind and index of token in assets or liabilities
    function _tokenBalance(TBSState memory $, ITBSV.AssetOrLiability forKind, uint256 forIndex)
        private
        pure
        returns (uint256 bal)
    {
        if (forKind == ITBSV.AssetOrLiability.ASSET && forIndex < $.assetBalances.length) {
            bal = $.assetBalances[forIndex];
        } else if (forKind == ITBSV.AssetOrLiability.LIABILITY && forIndex < $.liabilityBalances.length) {
            bal = $.liabilityBalances[forIndex];
        }

        // Otherwise returns 0
    }
}
