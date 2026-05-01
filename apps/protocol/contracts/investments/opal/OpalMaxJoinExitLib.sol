pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/OpalMaxJoinExitLib.sol)

import { LibMap as SoladyLibMap } from "solady/utils/LibMap.sol";
import { EnumerableSetLib as SoladyEnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";

import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiEnumerableMapLib } from "contracts/libraries/OrigamiEnumerableMapLib.sol";
import { AdapterDetails } from "contracts/investments/opal/OpalManager.sol";

/// @notice A library for the OpalManager to calculate the maxJoin or maxExit
/// given the underlying adapters.
/// It takes into consideration the current adapters of the vault and each of their maxJoin | maxExit amounts
/// for each of their tokens.
/// Since tokens within an adapter can share caps in the underlying borrow/lend market, this also takes into
/// consideration the adapter reported groupId for each token.
library OpalMaxJoinExitLib {
    using OrigamiMath for uint256;
    using SoladyLibMap for SoladyLibMap.Uint8Map;
    using SoladyEnumerableSetLib for SoladyEnumerableSetLib.AddressSet;
    using OrigamiEnumerableMapLib for OrigamiEnumerableMapLib.Bytes32ToAddressSetMap;
    using OrigamiEnumerableMapLib for OrigamiEnumerableMapLib.AddressToAdapterDetailsMap;

    /**
     * @dev Calculate the maximum allocation amount across all adapters for each asset or liability token, using the
     * `adapterFn`
     * @param adapterFn The adapter `maxJoin` | `maxExit` function to generate the underlying adapter level maximum join
     * or exit amount.
     *
     * Given a total amount `totalToAllocate_T` to allocate for a given asset or liability token `T`, it is allocated
     * across adapters proportional
     * to each adapters existing token balance `adapterBalance_T` vs the sum of token balances across all adapters
     * `totalBalance_T`
     *
     * So for each adapter:
     *   adapterAllocation_T = totalToAllocate_T * [adapterBalance_T/totalBalance_T]
     *
     * If there is a supply/borrow capacity limit on the `adapterAllocation_T` (governed by that underlying money market
     * the adapter uses - eg Aave),
     * each adapter can solve for the maximum `totalToAllocate_T` for that adapter:
     *
     *   totalToAllocate_T = adapterAllocation_T * [totalBalance_T/adapterBalance_T]
     *
     * However since `adapterAllocation_T` might share an underlying capacity supply/borrow cap for that token `T`
     * across multiple adapters
     * (eg Adapter1 and Adapter2 are both using the same collateral token in the same Aave instance which have the same
     * supply cap)
     * then `adapterAllocation_T` must to be scaled down by the proportion of that adapter's existing token balance vs
     * the sum of token balances across
     * adapters in the same group `groupBalance_T`
     *
     *   totalToAllocate_T = adapterAllocation_T * [adapterBalance_T/groupBalance_T] * [totalBalance_T/adapterBalance_T]
     *
     * This can simplify to:
     *   totalToAllocate_T = adapterAllocation_T * totalBalance_T / groupBalance_T
     *
     * For a given token across all adapters, the minimum is then used as the vault wide maximum amount allowed for
     * token T
     */
    function calcMaxAllocationAcrossAllAdapters(
        function(IOpalAdapter) internal view returns (uint256[] memory, uint256[] memory) adapterFn,
        OrigamiEnumerableMapLib.AddressToAdapterDetailsMap storage _adapterToDetailsMap,
        OrigamiEnumerableMapLib.Bytes32ToAddressSetMap storage _groupIdToAdapters,
        SoladyEnumerableSetLib.AddressSet storage _combinedAssetTokens,
        SoladyEnumerableSetLib.AddressSet storage _combinedLiabilityTokens
    ) internal view returns (uint256[] memory assetsMaxAllocations, uint256[] memory liabilitiesMaxAllocations) {
        _ActiveAdaptersCache memory $ = _fillAdapterCache(
            adapterFn, _adapterToDetailsMap, _groupIdToAdapters, _combinedAssetTokens, _combinedLiabilityTokens
        );

        // Initialize each amount to type(uint256).max to start, as the min will be taken while iterating through each
        // adapter
        assetsMaxAllocations = new uint256[]($.combinedBalanceSheet.assets.length);
        for (uint256 i; i < assetsMaxAllocations.length; ++i) {
            assetsMaxAllocations[i] = type(uint256).max;
        }
        liabilitiesMaxAllocations = new uint256[]($.combinedBalanceSheet.liabilities.length);
        for (uint256 i; i < liabilitiesMaxAllocations.length; ++i) {
            liabilitiesMaxAllocations[i] = type(uint256).max;
        }

        uint256 numActiveAdapters = $.perAdapterCache.length;

        // Force each adapter to reduce the maxJoin or maxExit amount they can join with by the number
        // of adapters-1
        // This resolves potential over-allocation to a specific adapter as it sequentially allocates
        // later within join() or exit()
        uint256 deltaForSafeMax = numActiveAdapters > 0 ? numActiveAdapters - 1 : 0;

        uint256 aggregatedTokenIndex; // The index of the current adapter token in the aggregated manager set
        uint256 globalGroupIdx; // The index of the current adapter's token groupId found in the global set
        uint256 numAdapterTokens;
        for (uint256 i; i < numActiveAdapters; ++i) {
            _SingleAdapterCache memory cacheItem = $.perAdapterCache[i];

            // Iterate over each a max amount in the adapter
            numAdapterTokens = cacheItem.adapterMaxJoinsOrExits.assets.length;
            for (uint256 j; j < numAdapterTokens; ++j) {
                aggregatedTokenIndex = cacheItem.assetAggregatedIndexes[j];
                globalGroupIdx = cacheItem.assetGroupIndexes[j];
                _applyProportionalMax({
                    maxAllocations: assetsMaxAllocations,
                    aggregatedTokenIndex: aggregatedTokenIndex,
                    combinedBalanceForToken: $.combinedBalanceSheet.assets[aggregatedTokenIndex],
                    groupBalanceForToken: $.perGroupBalanceSheet[globalGroupIdx].assets[aggregatedTokenIndex],
                    adapterMaxForToken: _safeMax(cacheItem.adapterMaxJoinsOrExits.assets[j], deltaForSafeMax)
                });
            }

            numAdapterTokens = cacheItem.adapterMaxJoinsOrExits.liabilities.length;
            for (uint256 j; j < numAdapterTokens; ++j) {
                aggregatedTokenIndex = cacheItem.liabilityAggregatedIndexes[j];
                globalGroupIdx = cacheItem.liabilityGroupIndexes[j];
                _applyProportionalMax({
                    maxAllocations: liabilitiesMaxAllocations,
                    aggregatedTokenIndex: aggregatedTokenIndex,
                    combinedBalanceForToken: $.combinedBalanceSheet.liabilities[aggregatedTokenIndex],
                    groupBalanceForToken: $.perGroupBalanceSheet[globalGroupIdx].liabilities[aggregatedTokenIndex],
                    adapterMaxForToken: _safeMax(cacheItem.adapterMaxJoinsOrExits.liabilities[j], deltaForSafeMax)
                });
            }
        }
    }

    /// @dev State for an adapter as of this block.
    struct _SingleAdapterCache {
        IOpalAdapter adapter;

        /// @dev The latest balance sheet data for the adapter
        IOpalManager.AssetsAndLiabilities balanceSheet;

        /// @dev The latest maxJoin | maxExit (filled accordingly for the use case)
        IOpalManager.AssetsAndLiabilities adapterMaxJoinsOrExits;

        /// @dev The adapter defines a groupId for each asset and liability token
        /// This list maps the position of that groupId into the global index within `_groupIdToAdapters`
        uint256[] assetGroupIndexes; // indexed by the adapter asset token index
        uint256[] liabilityGroupIndexes; // indexed by the adapter liability token index

        /// @dev This list maps the position of the adapter asset/liability token in the global
        /// `_combinedAssetTokens` | `_combinedLiabilityTokens`
        uint256[] assetAggregatedIndexes; // indexed by the adapter asset token index
        uint256[] liabilityAggregatedIndexes; // indexed by the adapter liability token index
    }

    struct _ActiveAdaptersCache {
        /// @dev The aggregated balance sheet data for all active adapters
        IOpalManager.AssetsAndLiabilities combinedBalanceSheet;

        /// @dev The balance sheet data for each unique group id. Indexed by the `_groupIdToAdapters` index
        IOpalManager.AssetsAndLiabilities[] perGroupBalanceSheet;

        /// @dev Cached information for a specific adapter
        _SingleAdapterCache[] perAdapterCache;
    }

    /// @dev Fill the cache for all current adapters
    function _fillAdapterCache(
        function(IOpalAdapter) internal view returns (uint256[] memory, uint256[] memory) adapterMaxFn,
        OrigamiEnumerableMapLib.AddressToAdapterDetailsMap storage _adapterToDetailsMap,
        OrigamiEnumerableMapLib.Bytes32ToAddressSetMap storage _groupIdToAdapters,
        SoladyEnumerableSetLib.AddressSet storage _combinedAssetTokens,
        SoladyEnumerableSetLib.AddressSet storage _combinedLiabilityTokens
    ) private view returns (_ActiveAdaptersCache memory $) {
        uint256 numActiveAdapters = _adapterToDetailsMap.length();
        $.perAdapterCache = new _SingleAdapterCache[](numActiveAdapters);

        uint256 numTokens;
        bytes32[] memory assetGroupIds;
        bytes32[] memory liabilityGroupIds;
        for (uint256 i; i < numActiveAdapters; ++i) {
            _SingleAdapterCache memory cacheItem = $.perAdapterCache[i];
            (address _adapter, AdapterDetails storage details) = _adapterToDetailsMap.keyValueAt(i);
            cacheItem.adapter = IOpalAdapter(_adapter);

            (cacheItem.balanceSheet.assets, cacheItem.balanceSheet.liabilities) = cacheItem.adapter.balanceSheet();

            (assetGroupIds, liabilityGroupIds) = cacheItem.adapter.groupIds();

            // The sizes of the arrays from the adapter are trusted to match in size - groupIds, tokens, balanceSheet,
            // etc.
            numTokens = cacheItem.balanceSheet.assets.length;
            cacheItem.assetGroupIndexes = new uint256[](numTokens);
            cacheItem.assetAggregatedIndexes = new uint256[](numTokens);
            for (uint256 j; j < numTokens; ++j) {
                cacheItem.assetGroupIndexes[j] = _groupIdToAdapters.indexOfE(assetGroupIds[j]);
                cacheItem.assetAggregatedIndexes[j] = details.assetToCombinedIndexMap.get(j);
            }

            numTokens = cacheItem.balanceSheet.liabilities.length;
            cacheItem.liabilityGroupIndexes = new uint256[](numTokens);
            cacheItem.liabilityAggregatedIndexes = new uint256[](numTokens);
            for (uint256 j; j < numTokens; ++j) {
                cacheItem.liabilityGroupIndexes[j] = _groupIdToAdapters.indexOfE(liabilityGroupIds[j]);
                cacheItem.liabilityAggregatedIndexes[j] = details.liabilityToCombinedIndexMap.get(j);
            }

            // Get the maxJoin | maxExit for this adapter
            (cacheItem.adapterMaxJoinsOrExits.assets, cacheItem.adapterMaxJoinsOrExits.liabilities) =
                adapterMaxFn(cacheItem.adapter);
        }

        ($.combinedBalanceSheet, $.perGroupBalanceSheet) =
            _balanceSheetPerGroup($, _combinedAssetTokens, _combinedLiabilityTokens, _groupIdToAdapters);
    }

    /// @dev Update the smallest proportional maxJoin/MaxExit, given an adapter and token in that adapter.
    /// Proportional to the `groupBalance/combinedBalance` ratio for the current adapter token group
    /// @param maxAllocations The smallest proportional maxJoin/maxExit seen so far.
    ///                       Updated in place, indexed by the `aggregatedTokenIndex`
    /// @param aggregatedTokenIndex The index of the current token in being applied
    /// @param combinedBalanceForToken The total combined balance for the current token across all adapter groups
    /// @param groupBalanceForToken The combined balance for the current token in a particular group
    /// @param adapterMaxForToken The current adapter maxJoin | maxExit for the current token
    function _applyProportionalMax(
        uint256[] memory maxAllocations,
        uint256 aggregatedTokenIndex,
        uint256 combinedBalanceForToken,
        uint256 groupBalanceForToken,
        uint256 adapterMaxForToken
    ) private pure {
        if (combinedBalanceForToken == 0) {
            // If there's no existing balance for this token across all adapters
            // then there should be no allocation
            maxAllocations[aggregatedTokenIndex] = 0;
            return;
        } else if (groupBalanceForToken == 0) {
            // If there's no aggregate balance for this groupId, then
            // it means there's no balance for this adapter either so it wouldn't receive an allocation
            // So it shouldn't contribute to the final min amount
            return;
        } else if (adapterMaxForToken == type(uint256).max) {
            // If this adapter can join with max then can also continue
            // since the maxAllocations was initialized to type(uint256).max
            return;
        }

        // The max for this adapter is rounded down to get a conservative amount allowed
        uint256 adapterProportionalMaxForToken =
            adapterMaxForToken.mulDiv(combinedBalanceForToken, groupBalanceForToken, OrigamiMath.Rounding.ROUND_DOWN);

        // Update if there's a new lower maximum
        if (adapterProportionalMaxForToken < maxAllocations[aggregatedTokenIndex]) {
            maxAllocations[aggregatedTokenIndex] = adapterProportionalMaxForToken;
        }
    }

    /// @dev If there is a max number of tokens from the adapter (< max), reduce by `deltaForSafeMax`
    /// to conservatively avoid over-allocation in join() and exit()
    function _safeMax(uint256 rawMax, uint256 delta) private pure returns (uint256 safeMax) {
        if (rawMax == type(uint256).max) return type(uint256).max;
        return (rawMax > delta) ? rawMax - delta : 0;
    }

    /// @dev Aggregate the balance sheet data across all the adapters - combined total, and for each unique group id
    /// associated with an adapter. Used where there is shared state such as supply/borrow caps for each underlying
    /// adapter. @return combinedBalanceSheet The combined total sum of balances (assets & liabilities) across all
    /// adapters.
    /// @return perGroupBalanceSheet The sum of balances (assets & liabilities) for each unique group id associated
    ///                                 with an adapter.
    function _balanceSheetPerGroup(
        _ActiveAdaptersCache memory $,
        SoladyEnumerableSetLib.AddressSet storage _combinedAssetTokens,
        SoladyEnumerableSetLib.AddressSet storage _combinedLiabilityTokens,
        OrigamiEnumerableMapLib.Bytes32ToAddressSetMap storage _groupIdToAdapters
    )
        private
        view
        returns (
            IOpalManager.AssetsAndLiabilities memory combinedBalanceSheet,
            IOpalManager.AssetsAndLiabilities[] memory perGroupBalanceSheet
        )
    {
        combinedBalanceSheet.assets = new uint256[](_combinedAssetTokens.length());
        combinedBalanceSheet.liabilities = new uint256[](_combinedLiabilityTokens.length());
        perGroupBalanceSheet = new IOpalManager.AssetsAndLiabilities[](_groupIdToAdapters.length());

        // Initialize each aggregate group balance sheet item to be the same size as the combined set
        for (uint256 i; i < perGroupBalanceSheet.length; ++i) {
            perGroupBalanceSheet[i] = IOpalManager.AssetsAndLiabilities({
                assets: new uint256[](combinedBalanceSheet.assets.length),
                liabilities: new uint256[](combinedBalanceSheet.liabilities.length)
            });
        }

        uint256 aggregatedIndex;
        uint256 amount;
        uint256 numActiveAdapters = $.perAdapterCache.length;
        for (uint256 i; i < numActiveAdapters; ++i) {
            _SingleAdapterCache memory cacheItem = $.perAdapterCache[i];

            // Aggregate the combined totals
            for (uint256 j; j < cacheItem.balanceSheet.assets.length; ++j) {
                amount = cacheItem.balanceSheet.assets[j];
                aggregatedIndex = cacheItem.assetAggregatedIndexes[j];
                combinedBalanceSheet.assets[aggregatedIndex] += amount;
                perGroupBalanceSheet[cacheItem.assetGroupIndexes[j]].assets[aggregatedIndex] += amount;
            }

            for (uint256 j; j < cacheItem.balanceSheet.liabilities.length; ++j) {
                amount = cacheItem.balanceSheet.liabilities[j];
                aggregatedIndex = cacheItem.liabilityAggregatedIndexes[j];
                combinedBalanceSheet.liabilities[aggregatedIndex] += amount;
                perGroupBalanceSheet[cacheItem.liabilityGroupIndexes[j]].liabilities[aggregatedIndex] += amount;
            }
        }
    }
}
