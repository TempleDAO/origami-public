pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/OpalVault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ITokenizedBalanceSheetVault
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { IOpalVault } from "contracts/interfaces/investments/opal/IOpalVault.sol";
import { OrigamiTokenizedBalanceSheetVault } from "contracts/common/OrigamiTokenizedBalanceSheetVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTBSLib as TBSLib, TBSState } from "contracts/libraries/OrigamiTBSLib.sol";

/**
 * @title Origami Portfolio of Assets and Liabilities (OPAL) - Tokenized Balance Sheet (TBS) Vault
 * @notice The logic to aggregate the adapter balance sheets and allocate out to the adapters is delegated to a manager.
 */
contract OpalVault is OrigamiTokenizedBalanceSheetVault, IOpalVault {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;
    using TBSLib for TBSState;

    /// @dev The internal manager
    IOpalManager private _manager;

    /// @inheritdoc IOpalVault
    address public override feeCollector;

    /// @inheritdoc IOpalVault
    uint48 public override annualPerformanceFeeBps;

    /// @inheritdoc IOpalVault
    uint48 public override lastPerformanceFeeTime;

    /// @inheritdoc IOpalVault
    uint16 public constant override MAX_PERFORMANCE_FEE_BPS = 1000; // 10%

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        uint48 _annualPerformanceFeeBps,
        address _feeCollector,
        address tokenPrices_
    ) OrigamiTokenizedBalanceSheetVault(initialOwner_, name_, symbol_, tokenPrices_) {
        if (_annualPerformanceFeeBps > MAX_PERFORMANCE_FEE_BPS) {
            revert CommonEventsAndErrors.InvalidParam();
        }
        annualPerformanceFeeBps = _annualPerformanceFeeBps;
        lastPerformanceFeeTime = uint48(block.timestamp);
        feeCollector = _feeCollector;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function setManager(address newManager) external override onlyElevatedAccess {
        if (newManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));

        if (newManager != address(_manager)) {
            _manager = IOpalManager(newManager);
            emit ManagerSet(newManager);
        }

        // Update the tokens hash in case it's changed
        updateCurrentTokensHash();
    }

    /// @inheritdoc IOpalVault
    function setAnnualPerformanceFee(uint48 _annualPerformanceFeeBps) external override onlyElevatedAccess {
        if (_annualPerformanceFeeBps > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();

        // Harvest on the old rate prior to updating the fee
        _collectPerformanceFees();

        emit PerformanceFeeSet(_annualPerformanceFeeBps);
        annualPerformanceFeeBps = _annualPerformanceFeeBps;
    }

    /// @inheritdoc IOpalVault
    function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(_feeCollector);
        feeCollector = _feeCollector;
    }

    /// @inheritdoc IOpalVault
    function collectPerformanceFees() external override onlyElevatedAccess returns (uint256 amount) {
        return _collectPerformanceFees();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areJoinsPaused()
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (bool)
    {
        return _manager.areJoinsPaused();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areExitsPaused()
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (bool)
    {
        return _manager.areExitsPaused();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function manager() external view override returns (address) {
        return address(_manager);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function joinFeeBps()
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256)
    {
        return _manager.joinFeeBps();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function exitFeeBps()
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256)
    {
        return _manager.exitFeeBps();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function assetTokens()
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (address[] memory assets)
    {
        assets = _manager.assetTokens();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function liabilityTokens()
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (address[] memory liabilities)
    {
        liabilities = _manager.liabilityTokens();
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    /// @dev It is not always guaranteed that the amount returned here will succeed when joinWithToken() is called,
    /// for example underlying adapter reverts if the protocol is paused (which may not be able to be captured
    /// adequately here). It may also be slightly more conservative than what may actually be possible. This is a best
    /// efforts.
    function maxJoinWithToken(
        address tokenAddress,
        address /*receiver*/
    )
        public
        view
        virtual
        override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256 maxToken)
    {
        // NOTE joinWithToken() will only use the base OrigamiTokenizedBalanceSheetVault::_maxJoinWithToken()
        // implementation as a precondition check rather than this version which also checks each underlying adapter.
        // This calc is gas intensive, and the join will revert anyway in the case that the underlying adapter cannot
        // join with the requested tokens.

        // Calculate the minimum amount of shares which can be used to join the vault
        TBSState memory $ = _stateForInputToken(tokenAddress, 0);
        uint256 maxShares = _leastOfMaxJoinWithShares($);

        // Match _previewJoinWithShares to calc the amount of shares prior to fees being taken
        if (maxShares < type(uint256).max) {
            maxShares = maxShares.inverseSubtractBps(joinFeeBps(), OrigamiMath.Rounding.ROUND_UP);
        }

        // Finally convert that max amount of shares into the requested token
        return _maxSharesToInputToken($, maxShares);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    /// @dev It is not always guaranteed that the amount returned here will succeed when joinWithShares() is called,
    /// for example underlying adapter reverts if the protocol is paused (which may not be able to be captured
    /// adequately here). It may also be slightly more conservative than what may actually be possible. This is a best
    /// efforts.
    function maxJoinWithShares(
        address /*receiver*/
    )
        public
        view
        virtual
        override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256 maxShares)
    {
        return _leastOfMaxJoinWithShares(_state());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    /// @dev It is not always guaranteed that the amount returned here will succeed when exitWithToken() is called,
    /// for example underlying adapter reverts if the protocol is paused (which may not be able to be captured
    /// adequately here). It may also be slightly more conservative than what may actually be possible. This is a best
    /// efforts.
    function maxExitWithToken(address tokenAddress, address sharesOwner)
        public
        view
        virtual
        override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256 maxToken)
    {
        // NOTE exitWithToken() will only use the base OrigamiTokenizedBalanceSheetVault::_maxExitWithToken()
        // implementation as a precondition check rather than this version which also checks each underlying adapter.
        // This calc is gas intensive, and the exit will revert anyway in the case that the underlying adapter cannot
        // exit with the requested tokens.

        // Calculate the minimum amount of shares which can be used to exit the vault
        TBSState memory $ = _stateForInputToken(tokenAddress, 0);
        uint256 maxShares = _leastOfMaxExitWithShares($, sharesOwner);

        // Match _previewExitWithShares to calc the amount of shares after fees are taken
        if (maxShares < type(uint256).max) {
            maxShares = maxShares.subtractBps(exitFeeBps(), OrigamiMath.Rounding.ROUND_DOWN);
        }

        // Finally convert that max amount of shares into the requested token
        return _maxSharesToInputToken($, maxShares);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    /// @dev It is not always guaranteed that the amount returned here will succeed when exitWithShares() is called,
    /// for example underlying adapter reverts if the protocol is paused (which may not be able to be captured
    /// adequately here). It may also be slightly more conservative than what may actually be possible. This is a best
    /// efforts.
    function maxExitWithShares(address sharesOwner)
        public
        view
        virtual
        override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256 maxShares)
    {
        return _leastOfMaxExitWithShares(_state(), sharesOwner);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function matchToken(address tokenAddress)
        public
        view
        virtual
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (AssetOrLiability kind, uint256 index)
    {
        return _manager.matchToken(tokenAddress);
    }

    /// @inheritdoc OrigamiTokenizedBalanceSheetVault
    function _balanceSheet()
        internal
        view
        override
        returns (uint256[] memory totalAssets, uint256[] memory totalLiabilities, bytes memory balanceSheetData)
    {
        return _manager.balanceSheet();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(IERC165, OrigamiTokenizedBalanceSheetVault)
        returns (bool)
    {
        return OrigamiTokenizedBalanceSheetVault.supportsInterface(interfaceId)
            || interfaceId == type(IOpalVault).interfaceId;
    }

    /// @inheritdoc IOpalVault
    function accruedPerformanceFee() public view override returns (uint256) {
        // totalSupply * feeBps * timeDelta / 365 days / 10_000
        // Round down (protocol takes less of a fee)
        uint256 _timeDelta = block.timestamp - lastPerformanceFeeTime;
        return OrigamiMath.mulDiv(
            totalSupply(),
            annualPerformanceFeeBps * _timeDelta,
            OrigamiMath.BASIS_POINTS_DIVISOR * 365 days,
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }

    /// @dev collect the accrued performance fees by minting new shares.
    function _collectPerformanceFees() internal returns (uint256 amount) {
        amount = accruedPerformanceFee();
        if (amount != 0) {
            address _feeCollector = feeCollector;
            emit PerformanceFeesCollected(_feeCollector, amount);

            // Do not need to check vs maxTotalSupply here as it is
            // only for new user investments
            _mint(_feeCollector, amount);
        }

        lastPerformanceFeeTime = uint48(block.timestamp);
    }

    /// @dev A hook for joins - it must pull assets from caller and send liabilities to receiver,
    /// along with any other interactions required.
    function _joinPreMintHook(
        TBSState memory $,
        address caller,
        address receiver,
        uint256,
        /*shares*/
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal override {
        // Transfer assets from the caller to the manager then join
        for (uint256 i; i < assets.length; ++i) {
            IERC20($.assetAddresses[i]).safeTransferFrom(caller, address(_manager), assets[i]);
        }

        // The aggregated and underlying 'per adapter' balance sheet data is passed through as calldata
        // to save potentially expensive calls duplicating the effort in the manager.
        // It also ensures consistency
        IOpalManager.BalanceSheetData memory bsData = IOpalManager.BalanceSheetData({
            aggregatedBalanceSheet: IOpalManager.AssetsAndLiabilities($.assetBalances, $.liabilityBalances),
            perAdapterBS: $.balanceSheetData
        });

        _manager.join(assets, liabilities, receiver, bsData);
    }

    /// @dev A hook for exits - it must send assets to receiver and pull liabilities from caller,
    /// along with any other interactions required.
    function _exitPreBurnHook(
        TBSState memory $,
        address caller,
        address,
        /*sharesOwner*/
        address receiver,
        uint256,
        /*shares*/
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal override {
        // Transfer liabilities from the caller to the manager then exit
        for (uint256 i; i < liabilities.length; ++i) {
            IERC20($.liabilityAddresses[i]).safeTransferFrom(caller, address(_manager), liabilities[i]);
        }

        // The aggregated and underlying 'per adapter' balance sheet data is passed through as calldata
        // to save potentially expensive calls duplicating the effort in the manager.
        // It also ensures consistency
        IOpalManager.BalanceSheetData memory bsData = IOpalManager.BalanceSheetData({
            aggregatedBalanceSheet: IOpalManager.AssetsAndLiabilities($.assetBalances, $.liabilityBalances),
            perAdapterBS: $.balanceSheetData
        });

        _manager.exit(assets, liabilities, receiver, bsData);
    }

    /// @dev Calculate the maximum shares possible by converting each of the max join/exit amounts of underlying tokens
    /// into shares and returning the minimum.
    function _maxSharesFromTokens(
        uint256[] memory tokenBalances,
        uint256[] memory managerMaxTokens,
        uint256 _totalSupply,
        uint256 prevMaxShares
    ) private pure returns (uint256 maxShares) {
        uint256 _shares;
        maxShares = prevMaxShares;
        uint256 totalTokenBalance;
        uint256 maxTokens;
        for (uint256 i; i < managerMaxTokens.length; ++i) {
            // If the token balance of this asset is zero then it wont contribute to what
            // can be joined into the vault, so can be skipped
            totalTokenBalance = tokenBalances[i];
            if (totalTokenBalance == 0) continue;

            // Also skip if it is uncapped
            maxTokens = managerMaxTokens[i];
            if (maxTokens == type(uint256).max) continue;

            // Convert the amount to shares, rounding down to ensure joins/exits will work for all valid tokens or
            // shares given the max constraints
            _shares = TBSLib.tokenToShares(maxTokens, totalTokenBalance, _totalSupply, OrigamiMath.Rounding.ROUND_DOWN);

            // Update the minimum value if necessary
            if (_shares < maxShares) maxShares = _shares;
        }
    }

    /// @dev The least amount of shares that joinWithShares can be called, given the two constraints:
    ///   1/ The maxTotalSupply based free shares capacity
    ///   2/ The underyling manager maxJoin amounts for each token in the balance sheet
    function _leastOfMaxJoinWithShares(TBSState memory $) private view returns (uint256 maxShares) {
        // Given the maximum underlying asset/liability amounts which can be joined into the underlying adapters in the
        // manager calculate the maximum shares for each token and take the overall minimum.
        {
            (uint256[] memory maxAssets, uint256[] memory maxLiabilities) = _manager.maxJoin();

            // Starts at type(uint256).max then takes the minimum shares allowed for each token
            // Round down to ensure joinWithShares() will succeed for both assets and liabilities
            maxShares = _maxSharesFromTokens($.assetBalances, maxAssets, $.totalSupply, type(uint256).max);
            maxShares = _maxSharesFromTokens($.liabilityBalances, maxLiabilities, $.totalSupply, maxShares);

            // Calculate the shares before the exit fee is taken on the shares.
            // Inverse of the fees being taken in _previewJoinWithShares();
            if (maxShares < type(uint256).max) {
                maxShares = maxShares.subtractBps(joinFeeBps(), OrigamiMath.Rounding.ROUND_DOWN);
            }
        }

        // Use the min of what the total supply capacity based max is (calculated in the base implementation),
        // and the maximum allowed by the manager assets above.
        // NOTE joinWithShares() will only use this base implementation as a precondition check rather than checking
        // each underlying adapter as above. This is because this calc is gas intensive, and will revert anyway in the
        // case that the underlying adapter cannot join
        // with the requested tokens.
        uint256 maxSharesGivenTotalSupplyCap = _maxJoinWithShares($.totalSupply);
        if (maxSharesGivenTotalSupplyCap < maxShares) maxShares = maxSharesGivenTotalSupplyCap;
    }

    /// @dev The least amount of shares that exitWithShares can be called, given the two constraints:
    ///   1/ The balance of shares `sharesOwner` holds
    ///   2/ The underyling manager maxExit amounts for each token in the balance sheet
    function _leastOfMaxExitWithShares(TBSState memory $, address sharesOwner)
        private
        view
        returns (uint256 maxShares)
    {
        // Given the maximum underlying asset/liability amounts which can be exited from the underlying adapters in the
        // manager calculate the maximum shares for each token and take the overall minimum.
        {
            (uint256[] memory maxAssets, uint256[] memory maxLiabilities) = _manager.maxExit();

            // Starts at type(uint256).max then takes the minimum shares allowed for each token
            // Round down to ensure exitWithShares() will succeed for both assets and liabilities
            maxShares = _maxSharesFromTokens($.assetBalances, maxAssets, $.totalSupply, type(uint256).max);
            maxShares = _maxSharesFromTokens($.liabilityBalances, maxLiabilities, $.totalSupply, maxShares);

            // Calculate the shares before the exit fee is taken on the shares.
            // Inverse of the fees being taken in _previewExitWithShares();
            if (maxShares < type(uint256).max) {
                maxShares = maxShares.inverseSubtractBps(exitFeeBps(), OrigamiMath.Rounding.ROUND_UP);
            }
        }

        // Use the min of what the total supply capacity based max is (calculated in the base implementation),
        // and the maximum allowed by the manager assets above.
        // NOTE exitWithShares() will only use this base implementation as a precondition check rather than checking
        // each underlying adapter as above. This is because this calc is gas intensive, and will revert anyway in the
        // case that the underlying adapter cannot exit
        // with the requested tokens.
        uint256 maxSharesGivenTotalSupplyCap = _maxExitWithShares(sharesOwner);
        if (maxSharesGivenTotalSupplyCap < maxShares) maxShares = maxSharesGivenTotalSupplyCap;
    }

    /// @dev Convert the maxShares into the max amount of tokens possible
    function _maxSharesToInputToken(TBSState memory $, uint256 maxShares) private pure returns (uint256) {
        // Find the current balance of the `tokenAddress` given the balance sheet.
        uint256 tokenBalance = $.inputTokenBalance();
        if (tokenBalance == 0) return 0;

        if (maxShares == type(uint256).max) return maxShares;

        // This always needs to round down to ensure joinWithToken / exitWithToken is always less than the
        // underlying adapter caps
        return TBSLib.sharesToToken(maxShares, tokenBalance, $.totalSupply, OrigamiMath.Rounding.ROUND_DOWN);
    }
}
