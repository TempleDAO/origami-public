pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/IOpalManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IOpalAdapterFactory } from "contracts/interfaces/investments/opal/IOpalAdapterFactory.sol";
import { IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

/**
 * @title Origami Portfolio of Assets and Liabilities (OPAL) Manager
 */
interface IOpalManager is IERC165, IOrigamiBundler {
    event FeeBpsSet(uint16 joinFeeBps, uint16 exitFeeBps);
    event AdapterAdded(address indexed adapter);
    event AdapterRemoved(address indexed adapter);
    event PluginApprovedSet(address indexed plugin, bool value);
    event Multicall();

    error AdapterStillActive();
    error InvalidAdapter();

    /// @notice Set which plugins (other than adapters) are allowed to be called
    /// as part of bundled multicalls
    function setPluginApproved(address plugin, bool value) external;

    function approvedPlugins(address plugin) external view returns (bool);

    /// @notice Set the join/exit fee, capped by the `MAX_FEE_BPS`
    function setFees(uint16 newJoinFeeBps, uint16 newExitFeeBps) external;

    /**
     * @notice Create a new adapter for a given implementation via the adapterFactory and add it
     * into the aggregated balance sheet.
     * @dev The asset/liability tokens from this new adapter will be added into the aggregated set
     * however it is likely the amounts in the balance sheet of that new adapter will be zero to begin with.
     * @param implementation An adapter implemenation to clone (must be pre-registered in the adapterFactory)
     * @param description A small string (as bytes32) description for this clone.
     *        format is left to the caller to decide, but for consistency could (but not
     *        enforced) be structured like:
     *        "[ASSET1.symbol, ASSET2.symbol] / [DEBT1.symbol, DEBT2.symbol]"
     * @param immutableArgsData abi encoded representation of immutable args. This must be
     *        encoded in a way the implemenation can decode at runtime.
     * @param immutableArgsData abi encoded representation of initialization args for that implemenation.
     *        This must be encoded in a way the implemenation can decode. adapter.initialize() is
     *        called immediately after creating the new clone of the implementation
     */
    function addAdapter(
        address implementation,
        bytes32 description,
        bytes calldata immutableArgsData,
        bytes calldata initData
    ) external returns (address);

    /**
     * @notice Remove an adapter from the aggregated set.
     * @dev There's no explicit check that the balance sheeet of this outgoing adapter is empty
     * as there may be dust amounts or issues with that particular adapter.
     */
    function removeAdapter(address adapter) external;

    /// @dev Container of asset and liability balances
    struct AssetsAndLiabilities {
        uint256[] assets;
        uint256[] liabilities;
    }

    /// @dev Container of the aggregated and per adapter balance sheet balances
    struct BalanceSheetData {
        /// @dev The aggregated balance sheet data - totalled across all adapters. The index of each matches the
        /// `tokens()`
        AssetsAndLiabilities aggregatedBalanceSheet;

        /// @dev The per adapter balance sheet. Abi encoded `AssetsAndLiabilities[]`, where the index of each matches
        /// that
        /// underlying adapter's `tokens()`
        /// The sum of these across the adapters equals the respective index for the same token of
        /// `combinedAssetBalances`
        /// and `combinedLiabilityBalances`
        bytes perAdapterBS;
    }

    /**
     * @notice Add equity by allocating the assets and borrowing the liabilities from the underlying adapters.
     * @param assets The total amount of assets to hold or deposit across all adapters, in its native decimals places
     * @param liabilities the total amount of debt across all adapters to send to the receiver, in its native decimals
     * places
     * @param receiver The address to receive the `liabilities`
     * @param bsData The encoded `BalanceSheetData` struct which contains the per adapter balance sheet
     * to work out the proportions
     */
    function join(
        uint256[] calldata assets,
        uint256[] calldata liabilities,
        address receiver,
        BalanceSheetData calldata bsData
    ) external;

    /**
     * @notice Remove equity by repaying `liabilities` and removing `assets` collateral from the underlying adapters.
     * Receiver receives the assets
     * @param assets The total amount of assets across all adapters to send to the receiver, in its native decimals
     * places
     * @param liabilities The total amount of debt to repay across all adapters, in its native decimals places
     * @param receiver The address to receive the `collateralAmount` of `collateralToken`
     * @param bsData The encoded `BalanceSheetData` struct which contains the per adapter balance sheet
     * to work out the proportions
     */
    function exit(
        uint256[] calldata assets,
        uint256[] calldata liabilities,
        address receiver,
        BalanceSheetData calldata bsData
    ) external;

    /**
     * @notice Describe how a set of assets and liabilities will be applied across the set of adapters
     */
    function allocationsAcrossAdapters(uint256[] calldata assets, uint256[] calldata liabilities)
        external
        view
        returns (AssetsAndLiabilities[] memory);

    /// @notice The Origami vault this is managing
    function vault() external view returns (address);

    /// @notice The combined set of asset tokens across all adapters
    /// @dev Note the size and order of this may change as adapters can be added and removed over time
    function assetTokens() external view returns (address[] memory);

    /// @notice The combined set of liability tokens across all adapters
    /// @dev Note the size and order of this may change as adapters can be added and removed over time
    function liabilityTokens() external view returns (address[] memory);

    /// @notice The combined balances of asset and liability tokens across all adapters
    /// @param totalAssets The combined asset amounts across all adapters. The index correlates to assetTokens()
    /// @param totalLiabilities The combined liability amounts across all adapters. The index correlates to
    /// assetTokens() @param encodedBalanceSheetData The encoded `BalanceSheetData` struct which contains the per
    /// adapter balance sheet
    /// to cache and then work out the proportions when allocating to adapters
    function balanceSheet()
        external
        view
        returns (uint256[] memory totalAssets, uint256[] memory totalLiabilities, bytes memory encodedBalanceSheetData);

    /// @notice Returns the total amount of the ASSETS and LIABILITIES this vault can join with as of this block
    /// @dev
    /// - `assets` MUST return a list which is the same size and order as `assetTokens()`
    /// - `liabilities` MUST return a list which is the same size and order as `liabilityTokens()`
    /// - SHOULD return zero if paused or entirely capped
    /// - SHOULD return type(uint256).max if unlimited
    /// - MUST NOT revert.
    function maxJoin() external view returns (uint256[] memory assets, uint256[] memory liabilities);

    /// @notice Returns the total amount of the ASSETS and LIABILITIES this vault can exit with as of this block
    /// @dev
    /// - `assets` MUST return a list which is the same size and order as `assetTokens()`
    /// - `liabilities` MUST return a list which is the same size and order as `liabilityTokens()`
    /// - SHOULD return zero if paused or entirely capped
    /// - SHOULD return type(uint256).max if unlimited
    /// - MUST NOT revert.
    function maxExit() external view returns (uint256[] memory assets, uint256[] memory liabilities);

    /// @dev Container to represent a given token and the index in the manager level (combined) assetTokens() or
    /// liabilityTokens()
    struct AdapterToCombinedIndexMapItem {
        /// @dev erc20 token address for one of the adapter assetTokens() or liabilityTokens()
        /// Must also be in the manager level combined assetTokens() or liabilityTokens()
        address token;

        /// @dev Index in the assetTokens() or liabilityTokens()
        uint256 combinedIndex;
    }

    /// @notice Mapping each of the adapter's token index to the combined manager level token index
    function adapterDetails(address adapter)
        external
        view
        returns (
            AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        );

    /// @notice The list of currently active adapters
    function adapters() external view returns (address[] memory);

    /// @notice A list of adapters which contain `token` in either its assetTokens() or liabilityTokens()
    function adaptersWithToken(address token) external view returns (address[] memory adapters);

    /// @notice Whether joinWithShares and joinWithAssets are currently paused
    function areJoinsPaused() external view returns (bool);

    /// @notice Whether exitToShares and exitToAssets are currently paused
    function areExitsPaused() external view returns (bool);

    /// @notice The current joinWithShares or joinWithTokens fee in basis points.
    function joinFeeBps() external view returns (uint16 feeBps);

    /// @notice The current exitToShares or exitToTokens fee in basis points.
    function exitFeeBps() external view returns (uint16 feeBps);

    /// @notice The factory used to create new adapters.
    function adapterFactory() external view returns (IOpalAdapterFactory factory);

    /// @notice The maximum exit fee in basis points: 3.3%
    function MAX_FEE_BPS() external view returns (uint16);

    /// @notice The maximum number of active adapters allowed
    function MAX_ADAPTERS() external view returns (uint256);

    /// @notice The maximum number of active tokens allowed in either the combined assetTokens() OR managerTokens()
    function MAX_TOKENS() external view returns (uint256);

    /// @notice Return whether the tokenAddress is part of the balance sheet assets or liabilities, and the index
    /// of that address in the respective assetTokens() or liabilityTokens() list
    /// - kind === ASSET if an asset
    /// - kind === LIABILITY if a liability
    /// - kind === INVALID if not an asset or liability (index will be zero in this case)
    function matchToken(address tokenAddress)
        external
        view
        returns (IOrigamiTokenizedBalanceSheetVault.AssetOrLiability kind, uint256 index);
}
