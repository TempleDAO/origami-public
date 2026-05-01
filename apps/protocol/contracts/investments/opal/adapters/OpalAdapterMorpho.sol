pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/adapters/OpalAdapterMorpho.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { MorphoBalancesLib } from "@morpho-org/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { MarketParamsLib } from "@morpho-org/morpho-blue/src/libraries/MarketParamsLib.sol";
import { MorphoLib } from "@morpho-org/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import { IOracle as IMorphoOracle } from "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";
import {
    ORACLE_PRICE_SCALE as MORPHO_ORACLE_PRICE_SCALE
} from "@morpho-org/morpho-blue/src/libraries/ConstantsLib.sol";
import {
    IMorphoSupplyCollateralCallback,
    IMorphoRepayCallback
} from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOpalAdapterMorpho } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterMorpho.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Morpho
/// @notice An OPAL Adapter which is a borrow position in a single Morpho market, so one asset token and one liability
/// token
contract OpalAdapterMorpho is IOpalAdapterMorpho, OpalAdapterBase {
    using SafeERC20 for IERC20;
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MorphoMarketParams;
    using SafeCast for uint256;
    using OrigamiMath for uint256;

    /// @inheritdoc IOpalAdapter
    uint256 public override maxSafeLtv;

    /// @inheritdoc IOpalAdapterMorpho
    uint256 public override maxLoanUtilizationRatioOnJoin;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_MORPHO = 0x34; // byte 52, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_COLLATERAL_TOKEN = 0x48; // byte 72, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_LOAN_TOKEN = 0x5c; // byte 92, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_MORPHO_ORACLE = 0x70; // byte 112, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_MORPHO_IRM = 0x84; // byte 132, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_MORPHO_LTV = 0x98; // byte 152, len: 32 bytes (uint256)
    uint256 private constant _ARGS_OFFSET_MORPHO_MARKET_ID = 0xb8; // byte 184, len: 32 bytes (bytes32)

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    /// @inheritdoc OpalAdapterBase
    function _adapterInit(bytes calldata data) internal override {
        address _loanToken = loanToken();
        address _collateralToken = collateralToken();
        if (_collateralToken == _loanToken) revert CommonEventsAndErrors.InvalidToken(_collateralToken);

        // Ensure the market id and market params params are matching
        MorphoMarketParams memory _marketParams = getMarketParams();
        MorphoMarketId _marketId = morphoMarketId();
        if (MorphoMarketId.unwrap(_marketParams.id()) != MorphoMarketId.unwrap(_marketId)) {
            revert CommonEventsAndErrors.InvalidParam();
        }

        (address _initialOwner, uint256 _maxSafeLtv, uint256 _maxLoanUtilizationRatioOnJoin) =
            abi.decode(data, (address, uint256, uint256));
        _init(_initialOwner);

        if (_maxLoanUtilizationRatioOnJoin > OrigamiMath.WAD) revert CommonEventsAndErrors.InvalidParam();
        maxLoanUtilizationRatioOnJoin = _maxLoanUtilizationRatioOnJoin;

        // Extra checks
        if (_maxSafeLtv >= morphoLltv()) revert CommonEventsAndErrors.InvalidParam();
        maxSafeLtv = _maxSafeLtv;

        // Verify that the market is valid
        IMorpho _morpho = morpho();
        if (_morpho.lastUpdate(_marketId) == 0) revert CommonEventsAndErrors.InvalidParam();

        // Approve the supply and borrow to the Morpho singleton upfront
        IERC20(_collateralToken).safeApprove(address(_morpho), type(uint256).max);
        IERC20(_loanToken).safeApprove(address(_morpho), type(uint256).max);
    }

    /****** IMMUTABLE GETTERS ******/

    /// @inheritdoc IOpalAdapterMorpho
    function morpho() public view override returns (IMorpho) {
        return IMorpho(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_MORPHO));
    }

    /// @inheritdoc IOpalAdapterMorpho
    function collateralToken() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_COLLATERAL_TOKEN);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function loanToken() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_LOAN_TOKEN);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function morphoOracle() public view override returns (IMorphoOracle) {
        return IMorphoOracle(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_MORPHO_ORACLE));
    }

    /// @inheritdoc IOpalAdapterMorpho
    function morphoIrm() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_MORPHO_IRM);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function morphoLltv() public view override returns (uint256) {
        return ClonesImmutableReader._getArgUint256(_ARGS_OFFSET_MORPHO_LTV);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function morphoMarketId() public view override returns (MorphoMarketId) {
        return MorphoMarketId.wrap(ClonesImmutableReader._getArgBytes32(_ARGS_OFFSET_MORPHO_MARKET_ID));
    }

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        view
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        // The combination of the Morpho singleton address + the Morpho market ID
        bytes32 grpId = EfficientHashLib.hash(
            bytes32(uint256(uint160(address(morpho())))), MorphoMarketId.unwrap(morphoMarketId())
        );

        assetGroupIds = new bytes32[](1);
        assetGroupIds[0] = grpId;

        liabilityGroupIds = new bytes32[](1);
        liabilityGroupIds[0] = grpId;
    }

    /****** ADMIN ******/

    /// @inheritdoc IOpalAdapterMorpho
    function setMaxSafeLtv(uint256 _maxSafeLtv) external override onlyElevatedAccess {
        if (_maxSafeLtv >= morphoLltv()) revert CommonEventsAndErrors.InvalidParam();
        maxSafeLtv = _maxSafeLtv;
        emit MaxSafeLtvSet(_maxSafeLtv);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function setMaxLoanUtilizationRatioOnJoin(uint256 maxRatio) external override onlyElevatedAccess {
        if (maxRatio > OrigamiMath.WAD) revert CommonEventsAndErrors.InvalidParam();
        maxLoanUtilizationRatioOnJoin = maxRatio;
        emit MaxLoanUtilizationRatioOnJoinSet(maxRatio);
    }

    /****** JOIN/EXIT ******/

    /// @inheritdoc IOpalAdapter
    function join(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address recipient)
        external
        override
        withApprovedBundler
    {
        if (assetAmounts.length != 1 || liabilityAmounts.length != 1) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        // The sender (OPAL manager) must set approval to pull the tokens
        // The Opal manager is trusted to line up the assets and liabilities lists -- no need to do any extra sense
        // checks.
        (uint256 supplyAmount, uint256 borrowAmount) = (assetAmounts[0], liabilityAmounts[0]);

        if (supplyAmount == 0) {
            // Nothing to do if nothing supplied or borrowed
            if (borrowAmount == 0) return;

            // In the case of bad debt, the adapters will first need to be rebalanced/reconfigured.
            revert NoCollateral();
        }

        IMorpho _morpho = morpho();
        MorphoMarketParams memory _marketParams = getMarketParams();
        IERC20(collateralToken()).safeTransferFrom(msg.sender, address(this), supplyAmount);
        _morpho.supplyCollateral(_marketParams, supplyAmount, address(this), "");

        if (borrowAmount > 0) {
            // This may revert if there isn't sufficient liquidity
            _morpho.borrow(_marketParams, borrowAmount, 0, address(this), recipient);

            // Validate that the LTV is under the 'Safe LTV'
            _validateSafeLtv(_morpho, _marketParams, morphoMarketId());

            // Validate that the loanToken UR is under the policy threshold for joins
            _validateLoanTokenUtilizationRatio(_morpho, _marketParams);
        }

        // The amounts here are the inputs, they are not adjusted to the 'actual' amounts
        // supplied/borrowed
        emit Join(assetAmounts, liabilityAmounts);
    }

    /// @inheritdoc IOpalAdapter
    function exit(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address recipient)
        external
        override
        withApprovedBundler
    {
        if (assetAmounts.length != 1 || liabilityAmounts.length != 1) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        // The bundler is trusted to line up the assets and liabilities amounts -- no need to do any extra sense checks.
        (uint256 withdrawAmount, uint256 repayAmount) = (assetAmounts[0], liabilityAmounts[0]);

        if (withdrawAmount == 0) {
            // Nothing to do if nothing repaid or withdrawn
            if (repayAmount == 0) return;

            // In the case of bad debt, the adapters will first need to be rebalanced/reconfigured.
            revert NoCollateral();
        }

        IMorpho _morpho = morpho();
        MorphoMarketParams memory _marketParams = getMarketParams();
        MorphoMarketId _marketId = morphoMarketId();
        if (repayAmount > 0) {
            IERC20(loanToken()).safeTransferFrom(msg.sender, address(this), repayAmount);

            // In the unlikely scenario that repayAmount is greater than the outstanding debt,
            // cap the amount actually repaid, so there may be a balance of tokens left here.
            // This can be skimmed later as part of the Bundler Actions.
            _repayUpToMax(repayAmount, _morpho, _marketParams, _marketId, "");
        }

        // In the unlikely scenario that withdrawAmount is greater than the supplied amount,
        // this will revert. This is expected because recipient should receive all the the tokens.
        // The OPAL vaults are seeded by the protocol first - if the vault is shutdown the protocol
        // will be responsible for exiting any dust from its seed position.
        _morpho.withdrawCollateral(_marketParams, withdrawAmount, address(this), recipient);

        // Validate that the LTV is under the 'Safe LTV'
        _validateSafeLtv(_morpho, _marketParams, _marketId);

        // NB: The UR is not enforced to be less than the policy set `maxLoanUtilizationRatioOnJoin` on an exit

        // The amounts here are the inputs, they are not adjusted to the 'actual' amounts
        // repaid/withdrawn
        emit Exit(assetAmounts, liabilityAmounts);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOpalAdapterMorpho
    function supplyCollateral(uint256 amount, uint256 minAmount, bytes calldata callbackData)
        external
        override
        withApprovedBundler
        returns (uint256 supplied)
    {
        if (amount == type(uint256).max) {
            amount = IERC20(collateralToken()).balanceOf(address(this));
        }

        // Skip if the amount is less than the threshold
        if (amount < minAmount) return 0;

        morpho().supplyCollateral(getMarketParams(), amount, address(this), callbackData);
        return amount;
    }

    /// @inheritdoc IMorphoSupplyCollateralCallback
    function onMorphoSupplyCollateral(
        uint256,
        /*assets*/
        bytes calldata callbackData
    )
        external
        override
    {
        _morphoCallback(callbackData);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function withdrawCollateral(uint256 amount, address recipient)
        external
        override
        withApprovedBundler
        returns (uint256 withdrawn)
    {
        IMorpho _morpho = morpho();
        withdrawn = amount == type(uint256).max ? _collateralBalance(_morpho, morphoMarketId()) : amount;
        _morpho.withdrawCollateral(getMarketParams(), withdrawn, address(this), recipient);

        // Note: The LTV isn't checked to be under 'maxSafeLtv' as it's assumed the bundle will contain
        // a final post-condition check on the balance sheet at the conclusion of all other steps.
    }

    /// @inheritdoc IOpalAdapterMorpho
    function borrow(uint256 assets, uint256 shares, address recipient)
        external
        override
        withApprovedBundler
        returns (uint256 borrowedAssets, uint256 borrowedShares)
    {
        // Note: The LTV (or slippage for number of assets actually borrowed given shares) isn't checked
        // here as it's assumed the bundle will contain a final post-condition check on the balance
        // sheet at the conclusion of all other steps.
        return morpho().borrow(getMarketParams(), assets, shares, address(this), recipient);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function repay(uint256 assets, uint256 minAssets, uint256 shares, bytes calldata callbackData)
        external
        override
        withApprovedBundler
        returns (uint256 repaidAssets, uint256 repaidShares)
    {
        if (shares == 0) {
            // Using assets.
            // If using `max` cap to the current loanToken balance in the contract
            // Capped to the current outstanding debt.
            if (assets == type(uint256).max) {
                assets = IERC20(loanToken()).balanceOf(address(this));
            }

            // Skip if the amount is less than the threshold
            if (assets < minAssets) return (0, 0);

            return _repayUpToMax(assets, morpho(), getMarketParams(), morphoMarketId(), callbackData);
        } else {
            // Using shares.
            // If using `max`, cap to the current shares balance
            // `minAssets` is not used when shares is specified
            IMorpho _morpho = morpho();
            if (shares == type(uint256).max) {
                shares = _morpho.borrowShares(morphoMarketId(), address(this));

                // If no shares found, then skip
                if (shares == 0) return (0, 0);
            }

            return _morpho.repay(getMarketParams(), assets, shares, address(this), callbackData);
        }
    }

    /// @inheritdoc IMorphoRepayCallback
    function onMorphoRepay(
        uint256,
        /*assets*/
        bytes calldata callbackData
    )
        external
        override
    {
        _morphoCallback(callbackData);
    }

    /****** BUNDLER PLUGIN CHECKS ******/

    /// @inheritdoc IOpalAdapterMorpho
    function validateLtvInRange(uint256 minLtv, uint256 maxLtv) external view {
        // Bound the maxLTV by the `maxSafeLtv`
        uint256 _maxSafeLtv = maxSafeLtv;
        if (_maxSafeLtv < maxLtv) maxLtv = _maxSafeLtv;

        if (minLtv > maxLtv) revert CommonEventsAndErrors.InvalidParam();

        uint256 _ltv = currentLtv();
        if (_ltv < minLtv || _ltv > maxLtv) revert LtvOutOfRange(_ltv, minLtv, maxLtv);
    }

    /// @inheritdoc IOpalAdapterMorpho
    function validateLoanUtilizationRatioInRange(uint256 minUR, uint256 maxUR) external view {
        if (minUR > maxUR) revert CommonEventsAndErrors.InvalidParam();
        uint256 _currentUR = currentLoanTokenUtilizationRatio();
        if (_currentUR < minUR || _currentUR > maxUR) revert UtilizationRatioOutOfRange(_currentUR, minUR, maxUR);
    }

    /****** VIEWS ******/

    /// @inheritdoc IOpalAdapterMorpho
    function encodeImmutableArgs(address _morpho, MorphoMarketParams memory _morphoMarketParams)
        external
        pure
        override
        returns (bytes memory)
    {
        if (_morphoMarketParams.collateralToken == _morphoMarketParams.loanToken) {
            revert CommonEventsAndErrors.InvalidToken(_morphoMarketParams.collateralToken);
        }

        return abi.encodePacked(
            // bundler is at position 0x00
            // description is at position 0x14
            _morpho,
            _morphoMarketParams.collateralToken,
            _morphoMarketParams.loanToken,
            _morphoMarketParams.oracle,
            _morphoMarketParams.irm,
            _morphoMarketParams.lltv,
            _morphoMarketParams.id()
        );
    }

    /// @inheritdoc IOpalAdapterMorpho
    function encodeInitArgs(address _initialOwner, uint256 _maxSafeLtv, uint256 _maxLoanUtilizationRatioOnJoin)
        external
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(_initialOwner, _maxSafeLtv, _maxLoanUtilizationRatioOnJoin);
    }

    /// @inheritdoc IOpalAdapter
    function tokens() external view override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        assetTokens = new address[](1);
        assetTokens[0] = collateralToken();
        liabilityTokens = new address[](1);
        liabilityTokens[0] = loanToken();
    }

    /// @inheritdoc IOpalAdapter
    function balanceSheet() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        IMorpho _morpho = morpho();
        MorphoMarketParams memory _marketParams = getMarketParams();
        assets = new uint256[](1);
        assets[0] = _collateralBalance(_morpho, morphoMarketId());

        liabilities = new uint256[](1);
        liabilities[0] = _debtBalance(_morpho, _marketParams);
    }

    function joinMetrics() public view override returns (LiabilityBorrowMetrics memory borrowMetrics) {
        // This includes accrued debt.
        (
            borrowMetrics.totalSupply,/* totalSupplyShares */,
            borrowMetrics.alreadyBorrowed,
            /* totalBorrowShares */
        ) = morpho().expectedMarketBalances(getMarketParams());

        // Use the policy set max UR to derive the borrow cap for joins
        // If the max UR = 1e18, then set the cap to type(uint256).max
        uint256 _maxLoanUtilizationRatioOnJoin = maxLoanUtilizationRatioOnJoin;
        borrowMetrics.joinBorrowCap = _maxLoanUtilizationRatioOnJoin < OrigamiMath.WAD
            ? _maxLoanUtilizationRatioOnJoin.mulDiv(
                borrowMetrics.totalSupply, OrigamiMath.WAD, OrigamiMath.Rounding.ROUND_DOWN
            )
            : type(uint256).max;
    }

    /// @inheritdoc IOpalAdapter
    function maxJoin() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        // Morpho has no cap on what collateral can be supplied.
        assets = new uint256[](1);
        assets[0] = type(uint256).max;

        liabilities = new uint256[](1);
        liabilities[0] = _availableToBorrow(joinMetrics());
    }

    function exitMetrics()
        public
        view
        override
        returns (AssetWithdrawMetrics memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics)
    {
        IMorpho _morpho = morpho();

        // Limited to just the balance of the collateral token within morpho
        withdrawMetrics.availableSupply = IERC20(collateralToken()).balanceOf(address(_morpho));

        // The total debt by all users for this market including accrued
        (,, repayMetrics.totalDebt,) = _morpho.expectedMarketBalances(getMarketParams());
    }

    /// @inheritdoc IOpalAdapter
    function maxExit() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        (AssetWithdrawMetrics memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics) = exitMetrics();

        assets = new uint256[](1);
        assets[0] = withdrawMetrics.availableSupply;

        liabilities = new uint256[](1);
        liabilities[0] = repayMetrics.totalDebt;
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public view override(OpalAdapterBase, IOpalAdapter) returns (uint256) {
        return _currentLtv(morpho(), getMarketParams(), morphoMarketId());
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public view override(OpalAdapterBase, IOpalAdapter) returns (uint256) {
        return morphoLltv();
    }

    /// @inheritdoc IOpalAdapterMorpho
    function getMarketParams() public view override returns (MorphoMarketParams memory) {
        return MorphoMarketParams({
            loanToken: loanToken(),
            collateralToken: collateralToken(),
            oracle: address(morphoOracle()),
            irm: morphoIrm(),
            lltv: morphoLltv()
        });
    }

    /// @inheritdoc IOpalAdapterMorpho
    function currentLoanTokenUtilizationRatio() public view override returns (uint256 utilizationRatio) {
        return _currentLoanTokenUtilizationRatio(morpho(), getMarketParams());
    }

    /// @inheritdoc IOpalAdapterMorpho
    function positionDetails() external view override returns (MorphoPositionDetails memory details) {
        _populateLtvDetails(details, morpho(), getMarketParams(), morphoMarketId());
        details.liquidationLtv = morphoLltv();
        details.maxSafeLtv = maxSafeLtv;
        details.healthFactor = _healthFactor(details.currentLtv, details.liquidationLtv);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OpalAdapterBase)
        returns (bool)
    {
        return OpalAdapterBase.supportsInterface(interfaceId) || interfaceId == type(IOpalAdapterMorpho).interfaceId;
    }

    /****** PRIVATE ******/

    function _availableToBorrow(LiabilityBorrowMetrics memory metrics) private pure returns (uint256) {
        // Use the min of policy set borrow cap and the total supply.
        uint256 borrowCap = metrics.joinBorrowCap < metrics.totalSupply ? metrics.joinBorrowCap : metrics.totalSupply;

        return borrowCap > metrics.alreadyBorrowed ? borrowCap - metrics.alreadyBorrowed : 0;
    }

    /// @dev Repay the max of `repayAmount` and the current debt balance.
    function _repayUpToMax(
        uint256 repayAmount,
        IMorpho _morpho,
        MorphoMarketParams memory _marketParams,
        MorphoMarketId _marketId,
        bytes memory callbackData
    ) private returns (uint256 repaidAssets, uint256 repaidShares) {
        uint256 _currentDebtBalance = _debtBalance(_morpho, _marketParams);

        if (_currentDebtBalance != 0) {
            // If the repayment amount gte the current balance, then repay 100% of the debt.
            if (repayAmount < _currentDebtBalance) {
                // Repay via the amount (not shares)
                return _morpho.repay(_marketParams, repayAmount, 0, address(this), callbackData);
            } else {
                // Calculate the current morpho shares owed, and repay via the shares (not amount)
                // Do this when equal to the debt balance to avoid Morpho rounding underflow
                uint256 _repayShares = _morpho.position(_marketId, address(this)).borrowShares;
                return _morpho.repay(_marketParams, 0, _repayShares, address(this), callbackData);
            }
        }
    }

    /// @dev Validate that the LTV is under the 'Safe LTV'
    function _validateSafeLtv(IMorpho _morpho, MorphoMarketParams memory _marketParams, MorphoMarketId _marketId)
        private
        view
    {
        uint256 _ltv = _currentLtv(_morpho, _marketParams, _marketId);
        if (_ltv > maxSafeLtv) revert LtvOutOfRange(_ltv, 0, maxSafeLtv);
    }

    /// @dev Ensure the UR of the debt token in Aave is under the policy set amount
    function _validateLoanTokenUtilizationRatio(IMorpho _morpho, MorphoMarketParams memory _marketParams) private view {
        uint256 _currentUR = _currentLoanTokenUtilizationRatio(_morpho, _marketParams);
        if (_currentUR > maxLoanUtilizationRatioOnJoin) {
            revert UtilizationRatioOutOfRange(_currentUR, 0, maxLoanUtilizationRatioOnJoin);
        }
    }

    /// @dev The current `loanToken` utilization ratio on Morpho
    function _currentLoanTokenUtilizationRatio(IMorpho _morpho, MorphoMarketParams memory _marketParams)
        private
        view
        returns (uint256)
    {
        (
            uint256 totalSupplyAssets,
            /* totalSupplyShares */,
            uint256 totalBorrowAssets,
            /* totalBorrowShares */
        ) = _morpho.expectedMarketBalances(_marketParams);

        return totalSupplyAssets > 0
            ? totalBorrowAssets.mulDiv(OrigamiMath.WAD, totalSupplyAssets, OrigamiMath.Rounding.ROUND_UP)
            : 0;
    }

    /// @dev The current Loan-To-Value (LTV) of this adapter.
    function _currentLtv(IMorpho _morpho, MorphoMarketParams memory _marketParams, MorphoMarketId _marketId)
        private
        view
        returns (uint256 ltv)
    {
        MorphoPositionDetails memory details;
        _populateLtvDetails(details, _morpho, _marketParams, _marketId);
        return details.currentLtv;
    }

    /// @dev Populate the adapter's current LTV details using the latest liquidity metrics in Morpho
    /// This updates `details` in place
    function _populateLtvDetails(
        MorphoPositionDetails memory details,
        IMorpho _morpho,
        MorphoMarketParams memory _marketParams,
        MorphoMarketId _marketId
    ) private view {
        details.liabilityValue = _debtBalance(_morpho, _marketParams);
        details.collateralSupplied = _collateralBalance(_morpho, _marketId);
        details.collateralValueInLiabilityTerms = details.collateralSupplied
            .mulDiv(
                // Morpho oracle price is represented with:
                //   `36 + borrowToken decimals - supplyToken decimals` decimals of precision.
                morphoOracle().price(),
                MORPHO_ORACLE_PRICE_SCALE,
                OrigamiMath.Rounding.ROUND_DOWN
            );

        details.currentLtv = _calculateLtv(details.liabilityValue, details.collateralValueInLiabilityTerms);
    }

    /// @dev The current debt balance of tokens borrowed
    function _debtBalance(IMorpho _morpho, MorphoMarketParams memory _marketParams) private view returns (uint256) {
        return _morpho.expectedBorrowAssets(_marketParams, address(this));
    }

    /// @dev The current balance of tokens supplied
    function _collateralBalance(IMorpho _morpho, MorphoMarketId _marketId) private view returns (uint256) {
        return _morpho.collateral(_marketId, address(this));
    }

    /// @dev Triggers `_multicall` logic during a callback.
    function _morphoCallback(bytes calldata callbackData) private {
        if (msg.sender != address(morpho())) revert CommonEventsAndErrors.InvalidAccess();
        _reenterBundle(callbackData);
    }
}
