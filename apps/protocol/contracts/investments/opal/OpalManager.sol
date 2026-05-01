pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/OpalManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibMap as SoladyLibMap } from "solady/utils/LibMap.sol";
import { EnumerableSetLib as SoladyEnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { LibCall } from "solady/utils/LibCall.sol";

import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOpalAdapterFactory } from "contracts/interfaces/investments/opal/IOpalAdapterFactory.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { OpalVault } from "contracts/investments/opal/OpalVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { OrigamiEnumerableMapLib } from "contracts/libraries/OrigamiEnumerableMapLib.sol";
import { OpalMaxJoinExitLib } from "contracts/investments/opal/OpalMaxJoinExitLib.sol";

/// @dev Metadata for an adapter
struct AdapterDetails {
    /// @dev A map for this adapter's asset token indexes to the combined manager view of assets index
    /// This map is resynchronized for each adapter when any `_combinedAssetTokens` is removed
    /// since the order of items in `_combinedAssetTokens` may change as a result
    SoladyLibMap.Uint8Map assetToCombinedIndexMap;

    /// @dev A map for this adapter's liability token indexes to the combined manager view of liabilities index
    /// This map is resynchronized for each adapter when any `_combinedLiabilityTokens` is removed
    /// since the order of items in `_combinedLiabilityTokens` may change as a result
    SoladyLibMap.Uint8Map liabilityToCombinedIndexMap;
}

/**
 * @title Origami Portfolio of Assets and Liabilities (OPAL) Manager
 */
contract OpalManager is IOpalManager, OrigamiElevatedAccess, OrigamiManagerPausable, OrigamiBundler {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using OrigamiMath for uint256;
    using SoladyLibMap for SoladyLibMap.Uint8Map;
    using SoladyEnumerableSetLib for SoladyEnumerableSetLib.AddressSet;
    using OrigamiEnumerableMapLib for OrigamiEnumerableMapLib.Bytes32ToAddressSetMap;
    using OrigamiEnumerableMapLib for OrigamiEnumerableMapLib.AddressToAdapterDetailsMap;

    /// @inheritdoc IOpalManager
    IOpalAdapterFactory public immutable override adapterFactory;

    /// @inheritdoc IOpalManager
    mapping(address to => bool allowed) public override approvedPlugins;

    /// @inheritdoc IOpalManager
    uint16 public override joinFeeBps;

    /// @inheritdoc IOpalManager
    uint16 public override exitFeeBps;

    /// @inheritdoc IOpalManager
    uint16 public constant override MAX_FEE_BPS = 330; // 3.3%

    /// @inheritdoc IOpalManager
    uint256 public constant override MAX_ADAPTERS = 10;

    /// @inheritdoc IOpalManager
    uint256 public constant override MAX_TOKENS = 10;

    /// @dev The OPAL vault
    OpalVault private immutable _vault;

    /// @dev The enumerable map of adapters and their details.
    /// Adapters may be created/removed over time in order to adapt to market updates,
    /// eg Pendle PT collateral expirires will require a rollover of markets
    /// NOTE the ordering of these may change, as removing an item will 'swap & pop'
    OrigamiEnumerableMapLib.AddressToAdapterDetailsMap private _adapterToDetailsMap;

    /// @dev An enumerable mapping of all unique groupId's found in all active adapters => the set of
    /// adapters which have that groupId.
    /// NOTE the ordering of these may change, as removing an item will 'swap & pop'
    OrigamiEnumerableMapLib.Bytes32ToAddressSetMap private _groupIdToAdapters;

    /// @dev The aggregated set of asset tokens across all active adapters
    /// NOTE the ordering of these may change, as removing an item will 'swap & pop'
    SoladyEnumerableSetLib.AddressSet private _combinedAssetTokens;

    /// @dev The aggregated set of liability tokens across all active adapters
    /// NOTE the ordering of these may change, as removing an item will 'swap & pop'
    SoladyEnumerableSetLib.AddressSet private _combinedLiabilityTokens;

    /// @dev A mapping of a token (contained in either _combinedAssetTokens or _combinedLiabilityTokens) to
    /// the set of active adapters which contain that same asset or liability token.
    mapping(address token => SoladyEnumerableSetLib.AddressSet adapters) private _adaptersWithToken;

    constructor(address initialOwner_, address vault_, address adapterFactory_) OrigamiElevatedAccess(initialOwner_) {
        _vault = OpalVault(vault_);
        adapterFactory = IOpalAdapterFactory(adapterFactory_);
    }

    /// @inheritdoc IOpalManager
    function setPluginApproved(address plugin, bool value) external override onlyElevatedAccess {
        approvedPlugins[plugin] = value;
        emit PluginApprovedSet(plugin, value);
    }

    /// @inheritdoc IOpalManager
    function setFees(uint16 newJoinFeeBps, uint16 newExitFeeBps) external override onlyElevatedAccess {
        if (newJoinFeeBps > MAX_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        if (newExitFeeBps > MAX_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();

        emit FeeBpsSet(newJoinFeeBps, newExitFeeBps);
        joinFeeBps = newJoinFeeBps;
        exitFeeBps = newExitFeeBps;
    }

    /**
     * @notice Recover tokens accidentally sent here
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        // This contract will not ordinarily hold tokens, so safe to recover.
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiBundler
    function multicall(Call[] calldata bundle)
        public
        payable
        override(IOrigamiBundler, OrigamiBundler)
        onlyElevatedAccess
    {
        // NB This is intentionally limited to only elevated access
        OrigamiBundler.multicall(bundle);
        emit Multicall();
    }

    /// @inheritdoc IOpalManager
    function addAdapter(
        address implementation,
        bytes32 description,
        bytes calldata immutableArgsData,
        bytes calldata initData
    ) external override onlyElevatedAccess returns (address) {
        IOpalAdapter adapter = IOpalAdapter(
            adapterFactory.create(implementation, address(this), description, immutableArgsData)
        );
        adapter.initialize(initData);

        // Add the adapter's tokens into the aggregated set, and map the token indexes
        // Note: the adapter is expected to have an immutable set of asset and liability token addresses
        // Only limited checking is performed on the validity of the new adapter here.
        (address[] memory adapterAssets, address[] memory adapterLiabilities) = adapter.tokens();
        if (adapterAssets.length == 0 && adapterLiabilities.length == 0) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        // No need to check if it was added, will always be a new address.
        (, AdapterDetails storage details) = _adapterToDetailsMap.add(address(adapter), MAX_ADAPTERS);

        // Add all unique groups from this adapter into the global set
        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter.groupIds();
        if (assetGroupIds.length != adapterAssets.length || liabilityGroupIds.length != adapterLiabilities.length) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        for (uint256 i; i < assetGroupIds.length; ++i) {
            _groupIdToAdapters.addItem(assetGroupIds[i], address(adapter));
        }
        for (uint256 i; i < liabilityGroupIds.length; ++i) {
            _groupIdToAdapters.addItem(liabilityGroupIds[i], address(adapter));
        }

        // Add the adapter's assets and liabilities into the combined sets and then verify
        // that no token is both an asset and liability.
        _addAdapterTokens(adapter, _combinedAssetTokens, adapterAssets, details.assetToCombinedIndexMap);
        _addAdapterTokens(adapter, _combinedLiabilityTokens, adapterLiabilities, details.liabilityToCombinedIndexMap);
        _verifyTokens();

        _vault.updateCurrentTokensHash();

        emit AdapterAdded(address(adapter));
        return address(adapter);
    }

    /// @inheritdoc IOpalManager
    function removeAdapter(address adapter) external override onlyElevatedAccess {
        IOpalAdapter _adapter = IOpalAdapter(adapter);

        // There's intentionally no check on assets remaining in the adapter (as it could be dust or
        // issues with the adapter), however there's an extra check to ensure an adapter isn't removed
        // by accident. The adapter must first be deprecated.
        if (!_adapter.isDeprecated()) revert AdapterStillActive();

        if (!_adapterToDetailsMap.remove(adapter)) revert OrigamiEnumerableMapLib.EnumerableMapKeyNotFound();

        // Cannot remove all adapters
        if (_adapterToDetailsMap.length() == 0) revert InvalidAdapter();

        // Remove this adapter from the global groups.
        // When this adapter is removed from the last value set for a groupId, the key is removed (swap & pop)
        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = _adapter.groupIds();
        for (uint256 i; i < assetGroupIds.length; ++i) {
            _groupIdToAdapters.removeFromValueSet(assetGroupIds[i], adapter);
        }
        for (uint256 i; i < liabilityGroupIds.length; ++i) {
            _groupIdToAdapters.removeFromValueSet(liabilityGroupIds[i], adapter);
        }

        // For each of the asset and liability tokens of this adapter, remove from the aggregated set
        // It is assumed (and trusted) that the adapter tokens are immutable.
        (address[] memory adapterAssets, address[] memory adapterLiabilities) = _adapter.tokens();
        _removeAdapterTokens(adapter, adapterAssets, _combinedAssetTokens);
        _removeAdapterTokens(adapter, adapterLiabilities, _combinedLiabilityTokens);

        // Also resynchronize the token index map for all remaining adapters as the order of combined tokens
        // may have changed
        _resyncAdapterTokenIndexes();

        _vault.updateCurrentTokensHash();

        emit AdapterRemoved(adapter);
    }

    /// @dev internal enum only to track intended action when calling _allocateAcrossAdapters
    enum AllocationAction {
        VIEW_ONLY,
        JOIN,
        EXIT
    }

    /// @inheritdoc IOpalManager
    function join(
        uint256[] calldata assets,
        uint256[] calldata liabilities,
        address receiver,
        BalanceSheetData calldata bsData
    ) external override onlyVault {
        // Note: The vault is expected (and trusted) to pass through valid balance sheet data
        // where the per adapter balances sum exactly to the aggregated data.
        // It is also trusted to have sent the exact amount of assets to this contract prior to calling
        _allocateAcrossAdapters(
            assets,
            liabilities,
            bsData.aggregatedBalanceSheet,
            abi.decode(bsData.perAdapterBS, (AssetsAndLiabilities[])),
            AllocationAction.JOIN,
            receiver
        );

        // Events aren't emitted here, as they're done in each adapter.
    }

    /// @inheritdoc IOpalManager
    function exit(
        uint256[] calldata assets,
        uint256[] calldata liabilities,
        address receiver,
        BalanceSheetData calldata bsData
    ) external override onlyVault {
        // Note: The vault is expected (and trusted) to pass through valid balance sheet data
        // where the per adapter balances sum exactly to the aggregated data.
        // It is also trusted to have sent the exact amount of liabilities to this contract prior to calling
        _allocateAcrossAdapters(
            assets,
            liabilities,
            bsData.aggregatedBalanceSheet,
            abi.decode(bsData.perAdapterBS, (AssetsAndLiabilities[])),
            AllocationAction.EXIT,
            receiver
        );

        // Events aren't emitted here, as they're done in each adapter.
    }

    /// @inheritdoc IOrigamiBundler
    function isApprovedPlugin(address plugin) public view override(IOrigamiBundler, OrigamiBundler) returns (bool) {
        // Allow all current adapters and any whitelisted plugins.
        return _adapterToDetailsMap.contains(plugin) || approvedPlugins[plugin];
    }

    /// @inheritdoc IOpalManager
    function vault() external view override returns (address) {
        return address(_vault);
    }

    /// @inheritdoc IOpalManager
    function areJoinsPaused() external view override returns (bool) {
        return _paused.investmentsPaused;
    }

    /// @inheritdoc IOpalManager
    function areExitsPaused() external view override returns (bool) {
        return _paused.exitsPaused;
    }

    /// @inheritdoc IOpalManager
    function assetTokens() external view override returns (address[] memory) {
        return _combinedAssetTokens.values();
    }

    /// @inheritdoc IOpalManager
    function liabilityTokens() external view override returns (address[] memory) {
        return _combinedLiabilityTokens.values();
    }

    /// @inheritdoc IOpalManager
    function balanceSheet()
        public
        view
        override
        returns (
            uint256[] memory combinedAssets,
            uint256[] memory combinedLiabilities,
            bytes memory encodedBalanceSheetData
        )
    {
        (AssetsAndLiabilities memory combinedBalanceSheet, AssetsAndLiabilities[] memory perAdapterBalanceSheet) =
            _balanceSheet();
        return (combinedBalanceSheet.assets, combinedBalanceSheet.liabilities, abi.encode(perAdapterBalanceSheet));
    }

    /// @inheritdoc IOpalManager
    function maxJoin() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        return OpalMaxJoinExitLib.calcMaxAllocationAcrossAllAdapters(
            _adapterMaxJoin, _adapterToDetailsMap, _groupIdToAdapters, _combinedAssetTokens, _combinedLiabilityTokens
        );
    }

    /// @inheritdoc IOpalManager
    function maxExit() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        return OpalMaxJoinExitLib.calcMaxAllocationAcrossAllAdapters(
            _adapterMaxExit, _adapterToDetailsMap, _groupIdToAdapters, _combinedAssetTokens, _combinedLiabilityTokens
        );
    }

    /// @inheritdoc IOpalManager
    function adapterDetails(address adapter)
        external
        view
        override
        returns (
            AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        )
    {
        (bool exists, AdapterDetails storage details) = _adapterToDetailsMap.tryGet(adapter);
        if (exists) {
            IOpalAdapter _adapter = IOpalAdapter(adapter);
            (address[] memory adapterAssets, address[] memory adapterLiabilities) = _adapter.tokens();

            assetToCombinedIndexMap = new AdapterToCombinedIndexMapItem[](adapterAssets.length);
            for (uint256 i; i < adapterAssets.length; ++i) {
                assetToCombinedIndexMap[i] = AdapterToCombinedIndexMapItem({
                    token: adapterAssets[i], combinedIndex: details.assetToCombinedIndexMap.get(i)
                });
            }

            liabilityToCombinedIndexMap = new AdapterToCombinedIndexMapItem[](adapterLiabilities.length);
            for (uint256 i; i < adapterLiabilities.length; ++i) {
                liabilityToCombinedIndexMap[i] = AdapterToCombinedIndexMapItem({
                    token: adapterLiabilities[i], combinedIndex: details.liabilityToCombinedIndexMap.get(i)
                });
            }
        }
    }

    /// @inheritdoc IOpalManager
    function adapters() external view override returns (address[] memory) {
        return _adapterToDetailsMap.keys();
    }

    /// @inheritdoc IOpalManager
    function adaptersWithToken(address token) external view override returns (address[] memory) {
        return _adaptersWithToken[token].values();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165, OrigamiBundler) returns (bool) {
        return OrigamiBundler.supportsInterface(interfaceId) || interfaceId == type(IOpalManager).interfaceId;
    }

    /// @inheritdoc IOpalManager
    function allocationsAcrossAdapters(uint256[] calldata assets, uint256[] calldata liabilities)
        external
        view
        override
        returns (AssetsAndLiabilities[] memory)
    {
        // Force to be a view with staticcall
        bytes memory returnData = LibCall.staticCallContract(
            address(this), abi.encodeWithSelector(this._allocationsAcrossAdaptersNonView.selector, assets, liabilities)
        );

        return abi.decode(returnData, (AssetsAndLiabilities[]));
    }

    /// @inheritdoc IOpalManager
    function matchToken(address tokenAddress)
        external
        view
        override
        returns (IOrigamiTokenizedBalanceSheetVault.AssetOrLiability kind, uint256 index)
    {
        index = _combinedAssetTokens.indexOf(tokenAddress);
        if (index != SoladyEnumerableSetLib.NOT_FOUND) {
            kind = IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET;
        } else {
            index = _combinedLiabilityTokens.indexOf(tokenAddress);
            if (index != SoladyEnumerableSetLib.NOT_FOUND) {
                kind = IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY;
            } else {
                // Set as INVALID
                kind = IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.INVALID;
                index = 0;
            }
        }
    }

    /// @dev A non-view version of `allocationsAcrossAdapters()`, however it doesn't in fact
    /// update any state. Use the allocationsAcrossAdapters() to use as a view instead (or use this version)
    /// with 'staticcall'
    function _allocationsAcrossAdaptersNonView(uint256[] calldata assets, uint256[] calldata liabilities)
        public /*intended as an internal view*/
        returns (AssetsAndLiabilities[] memory)
    {
        // NB There's a small cost here to encode then decode the perAdapterBS when calling balanceSheet()
        // but this is intended as an offchain view only.
        (AssetsAndLiabilities memory combinedBalanceSheet, AssetsAndLiabilities[] memory perAdapterAllocations) =
            _balanceSheet();

        _allocateAcrossAdapters(
            assets, liabilities, combinedBalanceSheet, perAdapterAllocations, AllocationAction.VIEW_ONLY, address(0)
        );
        return perAdapterAllocations;
    }

    /**
     * @dev Update the adapter allocations for each balance sheet token, based on the existing amounts across the
     * adapters
     * and a combined allocation amount for that token.
     * Arrays are updated in place for gas optimization to avoid new allocations.
     * @param combinedAllocations The total amount to allocate across all adapters.
     *        Indexed by the manager/aggregate level tokens.
     *        NOTE this array is updated in place (each item reduced by the amount allocated). So all items should equal
     * zero after calling.
     * @param combinedBalances The existing balance sheet combined amounts per token, summed across all adapters.
     *        Indexed by the manager/aggregate level tokens.
     *        NOTE this array is updated in place (each item reduced by the balances in each adapter). All items should
     * equal zero after calling.
     * @param adapterBalances The per adapter balance sheet amounts per token, for each adapter. Indexed by the adapter,
     * then that adapter's tokens.
     *        NOTE This array is updated in place, the result is that this represents the per adapter allocations for
     * each token.
     * @param adapterToCombinedTokenIndexMap Map the adapter index of each token address to the combined level index of
     * that same token address.
     */
    function _allocateToAdapter(
        uint256[] memory combinedAllocations,
        uint256[] memory combinedBalances,
        uint256[] memory adapterBalances,
        SoladyLibMap.Uint8Map storage adapterToCombinedTokenIndexMap
    ) internal view {
        uint256 _combinedTokenIndex;
        uint256 _adapterBalance;
        uint256 _combinedBalance;
        uint256 _combinedAllocation;
        uint256 _adapterAllocation;

        // Iterate over each of the adapter token balances, scaling that item in place to the proportional
        // balance of what's remaining to allocate.
        for (uint256 _adapterTokenIndex; _adapterTokenIndex < adapterBalances.length; ++_adapterTokenIndex) {
            _combinedTokenIndex = adapterToCombinedTokenIndexMap.get(_adapterTokenIndex);
            _adapterBalance = adapterBalances[_adapterTokenIndex];
            _combinedBalance = combinedBalances[_combinedTokenIndex];
            _combinedAllocation = combinedAllocations[_combinedTokenIndex];

            if (_combinedBalance == 0 || _adapterBalance == 0) {
                // If the pre-existing balance of this token in the adapter is zero
                // then dont allocate any funds
                _adapterAllocation = 0;
            } else if (_adapterBalance == _combinedBalance) {
                // If the balance of this token is the remaining balance to allocate
                // then use 100% of it (avoid mulDiv and rounding)
                _adapterAllocation = _combinedAllocation;
            } else {
                // Otherwise calculate the proportion of this token to allocate to the adapter
                // based off the starting balances
                _adapterAllocation =
                    _combinedAllocation.mulDiv(_adapterBalance, _combinedBalance, OrigamiMath.Rounding.ROUND_DOWN);
            }

            // Set the adapter item to the proportionally scaled balance
            adapterBalances[_adapterTokenIndex] = _adapterAllocation;

            // Subtract the scaled amount allocated from the total left.
            // This decreases the numerator by the amount just allocated
            combinedAllocations[_combinedTokenIndex] = _combinedAllocation - _adapterAllocation;

            // Subtract the adapter existing balance from the remaining left, so the denominator decreases
            // This decreases the denominator by the amount just allocated
            combinedBalances[_combinedTokenIndex] = _combinedBalance - _adapterBalance;
        }
    }

    // Note `memory` is used intentionally for these (even though it does a copy from calldata=>memory),
    // as these lists are updated in place
    function _allocateAcrossAdapters(
        uint256[] memory assets,
        uint256[] memory liabilities,
        AssetsAndLiabilities memory combinedBalances,
        AssetsAndLiabilities[] memory perAdapterAllocations,
        AllocationAction action,
        address receiver
    ) internal {
        uint256 numAdapters = _adapterToDetailsMap.length();
        if (numAdapters == 0) revert InvalidAdapter();
        if (perAdapterAllocations.length != numAdapters) revert CommonEventsAndErrors.InvalidLength();

        if (assets.length != _combinedAssetTokens.length() || assets.length != combinedBalances.assets.length) {
            revert CommonEventsAndErrors.InvalidLength();
        }
        if (
            liabilities.length != _combinedLiabilityTokens.length()
                || liabilities.length != combinedBalances.liabilities.length
        ) revert CommonEventsAndErrors.InvalidLength();

        address adapter;
        AssetsAndLiabilities memory adapterAllocations;
        AdapterDetails storage details;
        for (uint256 i; i < numAdapters; ++i) {
            adapterAllocations = perAdapterAllocations[i];
            (adapter, details) = _adapterToDetailsMap.keyValueAt(i);

            _allocateToAdapter(
                assets, combinedBalances.assets, adapterAllocations.assets, details.assetToCombinedIndexMap
            );

            _allocateToAdapter(
                liabilities,
                combinedBalances.liabilities,
                adapterAllocations.liabilities,
                details.liabilityToCombinedIndexMap
            );

            // NB This is what causes it to be a non-view, even if called with AllocationAction.VIEW_ONLY
            if (action == AllocationAction.JOIN) {
                IOpalAdapter(adapter).join(adapterAllocations.assets, adapterAllocations.liabilities, receiver);
            } else if (action == AllocationAction.EXIT) {
                IOpalAdapter(adapter).exit(adapterAllocations.assets, adapterAllocations.liabilities, receiver);
            }
        }
    }

    /// @dev For each adapter, resync the assetToCombinedIndexMap and liabilityToCombinedIndexMap
    /// to the latest _combinedAssetTokens and _combinedLiabilityTokens order of tokens.
    function _resyncAdapterTokenIndexes() private {
        uint256 numActiveAdapters = _adapterToDetailsMap.length();
        AdapterDetails storage details;
        address adapter;
        address[] memory adapterAssets;
        address[] memory adapterLiabilities;

        // This isn't efficient at all, but there are a capped amount adapters and tokens
        // and only when adding/removing new adapters (elevated access only)
        for (uint256 i; i < numActiveAdapters; ++i) {
            (adapter, details) = _adapterToDetailsMap.keyValueAt(i);
            (adapterAssets, adapterLiabilities) = IOpalAdapter(adapter).tokens();

            _updateAdapterToCombinedIndexMap(adapterAssets, details.assetToCombinedIndexMap, _combinedAssetTokens);
            _updateAdapterToCombinedIndexMap(
                adapterLiabilities, details.liabilityToCombinedIndexMap, _combinedLiabilityTokens
            );
        }
    }

    /// @dev Map each adapter token to the combined token index which has the same token address
    function _updateAdapterToCombinedIndexMap(
        address[] memory adapterTokens,
        SoladyLibMap.Uint8Map storage adapterToCombinedTokenIndexMap,
        SoladyEnumerableSetLib.AddressSet storage combinedTokens
    ) private {
        uint256 index;
        for (uint256 i; i < adapterTokens.length; ++i) {
            index = combinedTokens.indexOf(adapterTokens[i]);

            // Its trusted that adapter tokens() are immutable, so it's not possible
            // that the index wont be found. But for completeness revert if it's not the case
            // the adapter will have to be corrected.
            if (index == SoladyEnumerableSetLib.NOT_FOUND) revert CommonEventsAndErrors.InvalidParam();

            adapterToCombinedTokenIndexMap.set(
                i,
                // downcast is safe since there can't be more than MAX_TOKENS
                // forge-lint: disable-next-line(unsafe-typecast)
                uint8(index)
            );
        }
    }

    /// @dev For each of `adapterTokens`:
    ///    - Update the erc20 approval to 0 (so the adapter cant pull funds any longer)
    ///    - Remove the reference to the adapter from the _adaptersWithToken list
    ///    - If _adaptersWithToken is empty as a result then also remove that token from the combined token set
    function _removeAdapterTokens(
        address adapter,
        address[] memory adapterTokens,
        SoladyEnumerableSetLib.AddressSet storage combinedTokens
    ) private {
        address token;
        SoladyEnumerableSetLib.AddressSet storage inAdapters;
        for (uint256 i; i < adapterTokens.length; ++i) {
            token = adapterTokens[i];
            inAdapters = _adaptersWithToken[token];

            // No need to check if this succeeds or not.
            // If the adapter.tokens() hasn't changed (it is trusted to be immutable) then this can never
            // be false. And if for some unknown reason it has changed then it still needs to be removed.
            inAdapters.remove(adapter);

            // Remove ERC20 approval
            IERC20(token).forceApprove(adapter, 0);

            // If no remaining adapters have this token, it can be removed.
            if (inAdapters.length() == 0) {
                // No need to check if this succeeds or not (same reason as above)
                // NOTE: This will change the order of remaining items (swap & pop) and also
                // the TBS vault token hash
                combinedTokens.remove(token);
            }
        }
    }

    /// @dev Revert if any of the liability tokens is also an asset token
    function _verifyTokens() private view {
        // Typically the number of liabilities will be smaller than the number of assets
        // so iterate through the liabilities and check each one of those isn't an asset
        uint256 numLiabilities = _combinedLiabilityTokens.length();
        address token;
        for (uint256 i; i < numLiabilities; ++i) {
            token = _combinedLiabilityTokens.at(i);
            if (_combinedAssetTokens.contains(token)) {
                revert CommonEventsAndErrors.InvalidToken(token);
            }
        }
    }

    /// @dev Add each of the adapter asset or liability tokens from the adapter into the combined
    /// set of assets/liabilities.
    /// This also sets the mapping of each adapter token index to the combined token list index
    /// and grants approval for the adapter to pull tokens from this manager (for joining/exiting)
    function _addAdapterTokens(
        IOpalAdapter adapter,
        SoladyEnumerableSetLib.AddressSet storage combinedTokens,
        address[] memory adapterTokens,
        SoladyLibMap.Uint8Map storage adapterToCombinedTokenIndexMap
    ) private {
        address token;
        for (uint256 i; i < adapterTokens.length; ++i) {
            token = adapterTokens[i];

            // Add this adapter into the set which have this token as an asset/liability
            // The check here is to make sure there are no duplicate tokens in the same adapter
            if (!_adaptersWithToken[token].add(address(adapter))) {
                revert CommonEventsAndErrors.InvalidToken(token);
            }

            // Add the token into the combined token list
            // Note If this is a new token, this will change the vault token hash
            // No need to check if it exists or not.
            combinedTokens.add(token, MAX_TOKENS);

            // Grant the adapter max approval to pull this token
            // The adapter is trusted, since:
            //  - Only elevated access can create and register a new adapter
            //  - Tokens only exist transiently in this contract when calling the adapter anyway
            IERC20(token).forceApprove(address(adapter), type(uint256).max);
        }

        // Each token in the adapter gets mapped to the combined index with the same token address
        _updateAdapterToCombinedIndexMap(adapterTokens, adapterToCombinedTokenIndexMap, combinedTokens);
    }

    function _adapterMaxJoin(IOpalAdapter adapter)
        private
        view
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        return adapter.maxJoin();
    }

    function _adapterMaxExit(IOpalAdapter adapter)
        private
        view
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        return adapter.maxExit();
    }

    /// @dev Aggregate the balance sheet data across all the adapters - combined total, and for each adapter
    /// @return combinedBalanceSheet The combined total sum of balances (assets & liabilities) across all adapters.
    /// @return perAdapterBalanceSheet The balances (assets & liabilities) for each unique adapter (ie unaggregated)
    function _balanceSheet()
        private
        view
        returns (AssetsAndLiabilities memory combinedBalanceSheet, AssetsAndLiabilities[] memory perAdapterBalanceSheet)
    {
        combinedBalanceSheet.assets = new uint256[](_combinedAssetTokens.length());
        combinedBalanceSheet.liabilities = new uint256[](_combinedLiabilityTokens.length());

        uint256 numActiveAdapters = _adapterToDetailsMap.length();
        perAdapterBalanceSheet = new AssetsAndLiabilities[](numActiveAdapters);

        address adapter;
        uint256 j;
        AdapterDetails storage details;
        uint256 aggregatedIndex;
        for (uint256 i; i < numActiveAdapters; ++i) {
            (adapter, details) = _adapterToDetailsMap.keyValueAt(i);

            AssetsAndLiabilities memory adapterBS = perAdapterBalanceSheet[i];

            (adapterBS.assets, adapterBS.liabilities) = IOpalAdapter(adapter).balanceSheet();

            // Aggregate the combined totals
            for (j = 0; j < adapterBS.assets.length; ++j) {
                aggregatedIndex = details.assetToCombinedIndexMap.get(j);
                combinedBalanceSheet.assets[aggregatedIndex] += adapterBS.assets[j];
            }
            for (j = 0; j < adapterBS.liabilities.length; ++j) {
                aggregatedIndex = details.liabilityToCombinedIndexMap.get(j);
                combinedBalanceSheet.liabilities[aggregatedIndex] += adapterBS.liabilities[j];
            }
        }
    }

    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function _onlyVault() internal view {
        if (msg.sender != address(_vault)) revert CommonEventsAndErrors.InvalidAccess();
    }
}
