pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/adapters/OpalAdapterAaveV3.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {
    ReserveConfiguration as AaveReserveConfiguration
} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {
    IAaveV3RewardsController
} from "contracts/interfaces/external/aave/aave-v3-periphery/IAaveV3RewardsController.sol";
import { WadRayMath as AaveWadRayMath } from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOpalAdapterAaveV3 } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterAaveV3.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Aave V3
/// @notice An OPAL Adapter which is a borrow position in an Aave V3 market.
/// That will be a single position with one or more collateral tokens and one debt token.
contract OpalAdapterAaveV3 is IOpalAdapterAaveV3, OpalAdapterBase {
    using SafeERC20 for IERC20;
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;
    using OrigamiMath for uint256;

    /// @inheritdoc IOpalAdapterAaveV3
    uint16 public override referralCode = 0;

    /// @inheritdoc IOpalAdapterAaveV3
    IAavePool public override aavePool;

    /// @inheritdoc IOpalAdapterAaveV3
    uint256 public override maxLoanUtilizationRatioOnJoin;

    /// @dev Only use the Aave variable interest, not fixed
    uint256 private constant INTEREST_RATE_MODE = uint256(AaveDataTypes.InterestRateMode.VARIABLE);

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_POOL_ADDRESS_PROVIDER = 0x34; // start: byte 52, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_LOAN_TOKEN = 0x48; // start: byte 72, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_AAVE_D_TOKEN = 0x5c; // start: byte 92, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_NUM_COLLATERAL_TOKENS = 0x70; // start: byte 112, len: 1 byte (uint8)
    uint256 private constant _ARGS_OFFSET_COLLATERAL_TOKENS = 0x71; // start: byte 113, len: num * 40 bytes (address,
    // address)

    /// @dev max number of collateral tokens allowed in this adapter
    uint8 private constant MAX_COLLATERAL_TOKENS = 5;

    /// @dev Aave reports LTV in 1e4 (9000 == 90% LTV). Origami uses 1e18 (0.9e18 == 90% LTV)
    uint256 private constant LTV_CONVERSION_SCALAR = 1e14;

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    /// @inheritdoc OpalAdapterBase
    function _adapterInit(bytes calldata data) internal override {
        (address _initialOwner, uint8 _defaultEMode, uint256 _maxLoanUtilizationRatioOnJoin) =
            abi.decode(data, (address, uint8, uint256));
        _init(_initialOwner);

        if (_maxLoanUtilizationRatioOnJoin > OrigamiMath.WAD) revert CommonEventsAndErrors.InvalidParam();
        maxLoanUtilizationRatioOnJoin = _maxLoanUtilizationRatioOnJoin;

        // Verify that the reported aToken and dToken matches
        // and approve the loan token to the pool upfront
        IAavePool _aavePool = IAavePool(aavePoolAddressProvider().getPool());

        address _loanToken = loanToken();
        if (aaveDToken() != _aavePool.getReserveData(_loanToken).variableDebtTokenAddress) {
            revert CommonEventsAndErrors.InvalidParam();
        }
        IERC20(_loanToken).forceApprove(address(_aavePool), type(uint256).max);

        address[] memory _collateralTokens = collateralTokens();
        if (_collateralTokens.length == 0 || _collateralTokens.length > MAX_COLLATERAL_TOKENS) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        address[] memory _aTokens = aaveATokens();
        address _collateralToken;
        for (uint256 i; i < _collateralTokens.length; ++i) {
            _collateralToken = _collateralTokens[i];
            if (_collateralToken == _loanToken) revert CommonEventsAndErrors.InvalidToken(_collateralToken);
            if (_aTokens[i] != _aavePool.getReserveData(_collateralToken).aTokenAddress) {
                revert CommonEventsAndErrors.InvalidParam();
            }
            IERC20(_collateralToken).forceApprove(address(_aavePool), type(uint256).max);
        }

        // Initate e-mode on the Aave/Spark pool if required
        if (_defaultEMode != 0) {
            _aavePool.setUserEMode(_defaultEMode);
        }

        aavePool = _aavePool;
    }

    /****** IMMUTABLE GETTERS ******/

    /// @inheritdoc IOpalAdapterAaveV3
    function aavePoolAddressProvider() public view override returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_POOL_ADDRESS_PROVIDER));
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function loanToken() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_LOAN_TOKEN);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function aaveDToken() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_AAVE_D_TOKEN);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function numCollateralTokens() public view override returns (uint8) {
        return ClonesImmutableReader._getArgUint8(_ARGS_OFFSET_NUM_COLLATERAL_TOKENS);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function collateralTokens() public view override returns (address[] memory result) {
        uint8 _numAssets = numCollateralTokens();
        result = new address[](_numAssets);
        for (uint256 i; i < _numAssets; ++i) {
            // The collateral token address and the aave aToken address are encoded
            // as tuples. 20+20 bytes (0x28)
            result[i] = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_COLLATERAL_TOKENS + i * 0x28);
        }
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function aaveATokens() public view override returns (address[] memory result) {
        uint8 _numAssets = numCollateralTokens();
        result = new address[](_numAssets);
        for (uint256 i; i < _numAssets; ++i) {
            // The collateral token address and the aave aToken address are encoded
            // as tuples. 20+20 bytes (0x28)
            result[i] = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_COLLATERAL_TOKENS + 0x14 + i * 0x28);
        }
    }

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        view
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        // Supply/Borrow caps are set per Aave instance, determined by the pool address provider.
        // So the same groupId is used for all assets within this pool address provider
        bytes32 grpId = bytes32(uint256(uint160(address(aavePoolAddressProvider()))));

        uint256 _numAssets = numCollateralTokens();
        assetGroupIds = new bytes32[](_numAssets);
        for (uint256 i; i < _numAssets; ++i) {
            assetGroupIds[i] = grpId;
        }

        liabilityGroupIds = new bytes32[](1);
        liabilityGroupIds[0] = grpId;
    }

    /****** ADMIN ACTIONS ******/

    /// @inheritdoc IOpalAdapterAaveV3
    function updateAavePool() external override onlyElevatedAccess {
        address oldPool = address(aavePool);
        IAavePool newPool = IAavePool(aavePoolAddressProvider().getPool());
        if (address(newPool) == oldPool) revert CommonEventsAndErrors.InvalidAddress(address(newPool));

        // Ensure the reserve data still matches (no need for full completeness - just check the a/d tokens)
        IERC20 _token = IERC20(loanToken());
        if (aaveDToken() != newPool.getReserveData(address(_token)).variableDebtTokenAddress) {
            revert CommonEventsAndErrors.InvalidParam();
        }

        _token.forceApprove(oldPool, 0);
        _token.forceApprove(address(newPool), type(uint256).max);

        address[] memory _collateralTokens = collateralTokens();
        address[] memory _aTokens = aaveATokens();
        for (uint256 i; i < _collateralTokens.length; ++i) {
            _token = IERC20(_collateralTokens[i]);
            if (_aTokens[i] != newPool.getReserveData(address(_token)).aTokenAddress) {
                revert CommonEventsAndErrors.InvalidParam();
            }
            _token.forceApprove(oldPool, 0);
            _token.forceApprove(address(newPool), type(uint256).max);
        }

        emit AavePoolUpdated(address(newPool));
        aavePool = newPool;
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function setReferralCode(uint16 code) external override onlyElevatedAccess {
        referralCode = code;
        emit ReferralCodeSet(code);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function setUserUseReserveAsCollateral(address token, bool useAsCollateral) external override onlyElevatedAccess {
        aavePool.setUserUseReserveAsCollateral(token, useAsCollateral);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function setEModeCategory(uint8 categoryId) external override onlyElevatedAccess {
        aavePool.setUserEMode(categoryId);
        validateLtvInRange(0, type(uint256).max);
    }

    /// @inheritdoc IOpalAdapterAaveV3
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
        address[] memory _collateralTokens = collateralTokens();
        if (assetAmounts.length != _collateralTokens.length || liabilityAmounts.length != 1) {
            revert CommonEventsAndErrors.InvalidLength();
        }
        IAavePool pool = aavePool;

        // Supply each of the collaterals in turn
        address token;
        uint256 supplyAmount;
        uint256 totalSupplyAmount;
        for (uint256 i; i < assetAmounts.length; ++i) {
            token = _collateralTokens[i];
            supplyAmount = assetAmounts[i];
            if (supplyAmount > 0) {
                IERC20(token).safeTransferFrom(msg.sender, address(this), supplyAmount);
                // This may revert if above supply caps, paused, etc.
                pool.supply(token, supplyAmount, address(this), referralCode);
            }

            // Only being used to check its non-zero, dont care about token decimals.
            totalSupplyAmount += supplyAmount;
        }

        uint256 borrowAmount = liabilityAmounts[0];
        if (totalSupplyAmount == 0) {
            // Nothing to do if nothing supplied or borrowed
            if (borrowAmount == 0) return;

            // Dont allow joins which borrow but dont add any new supply.
            // In the case of bad debt, the adapters will first need to be rebalanced/reconfigured.
            revert NoCollateral();
        }

        // Borrow the single debt token
        if (borrowAmount > 0) {
            // This may revert if not sufficient liquidity, above borrow caps, paused, etc.
            // NB: No need to check the LTV is under the 'safe LTV', as Aave does that internally upon a borrow
            _borrow(pool, borrowAmount, recipient);

            // Validate that the loanToken UR is under the policy threshold for joins
            _validateLoanTokenUtilizationRatio(pool);
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
        address[] memory _collateralTokens = collateralTokens();
        if (assetAmounts.length != _collateralTokens.length || liabilityAmounts.length != 1) {
            revert CommonEventsAndErrors.InvalidLength();
        }
        IAavePool pool = aavePool;

        // Repay the debt
        uint256 repayAmount = liabilityAmounts[0];
        if (repayAmount > 0) {
            address _loanToken = loanToken();
            IERC20(_loanToken).safeTransferFrom(msg.sender, address(this), repayAmount);

            // In the unlikely scenario that repayAmount is greater than the outstanding debt, Aave
            // will cap the amount actually repaid, so there may be a balance of tokens left here.
            // This can be skimmed later as part of the Bundler Actions.
            pool.repay(_loanToken, repayAmount, INTEREST_RATE_MODE, address(this));
        }

        // Withdraw the collateral
        address token;
        uint256 withdrawAmount;
        bool atLeastOneWithdraw;
        for (uint256 i; i < assetAmounts.length; ++i) {
            token = _collateralTokens[i];
            withdrawAmount = assetAmounts[i];
            if (withdrawAmount > 0) {
                // In the unlikely scenario that withdrawAmount is greater than the supplied amount,
                // Aave will revert. This is expected because recipient should receive all the the tokens.
                // The OPAL vaults are seeded by the protocol first - if the vault is shutdown the protocol
                // will be responsible for exiting any dust from its seed position.
                // It may also revert if not sufficient liquidity or the market is paused, etc -- also expected.
                pool.withdraw(token, withdrawAmount, recipient);

                atLeastOneWithdraw = true;
            }
        }

        if (!atLeastOneWithdraw) {
            // Nothing to do if nothing repaid or withdrawn
            if (repayAmount == 0) return;

            // In the case of bad debt, the adapters will first need to be rebalanced/reconfigured.
            revert NoCollateral();
        }

        // NB: The UR is not enforced to be less than the policy set `maxLoanUtilizationRatioOnJoin` on an exit
        // NB: No need to check the LTV, as Aave does that internally on a collateral withdraw

        // The amounts here are the inputs, they are not adjusted to the 'actual' amounts
        // repaid/withdrawn
        emit Exit(assetAmounts, liabilityAmounts);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOpalAdapterAaveV3
    function supplyCollateral(address token, uint256 amount, uint256 minAmount)
        external
        override
        withApprovedBundler
        returns (uint256 supplied)
    {
        // Not necessarily a listed collateral in the balance sheet, since
        // anyone can supply collateral on this contracts behalf anyway.
        if (amount == type(uint256).max) {
            amount = IERC20(token).balanceOf(address(this));
        }

        // Skip if the amount is less than the threshold
        if (amount < minAmount) return 0;

        aavePool.supply(token, amount, address(this), referralCode);
        return amount;
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function withdrawCollateral(address token, uint256 amount, address recipient)
        external
        override
        withApprovedBundler
        returns (uint256 withdrawn)
    {
        return aavePool.withdraw(token, amount, recipient);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function borrow(uint256 amount, address recipient) external override withApprovedBundler {
        _borrow(aavePool, amount, recipient);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function repay(uint256 amount, uint256 minAmount) external override withApprovedBundler returns (uint256 repaid) {
        address _loanToken = loanToken();
        if (amount == type(uint256).max) {
            amount = IERC20(_loanToken).balanceOf(address(this));
        }

        // Skip if the amount is less than the threshold
        if (amount < minAmount) return 0;

        // Aave will cap the repayment amount to the current debt
        return aavePool.repay(_loanToken, amount, INTEREST_RATE_MODE, address(this));
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function claimAllRewards(address rewardsController, address[] calldata rewardTokens, address to)
        external
        override
        withApprovedBundler
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        // Event emitted within rewards controller.
        return IAaveV3RewardsController(rewardsController).claimAllRewards(rewardTokens, to);
    }

    /****** BUNDLER PLUGIN CHECKS ******/

    /// @inheritdoc IOpalAdapterAaveV3
    function validateLtvInRange(uint256 minLtv, uint256 maxLtv) public view override {
        // Bound the maxLTV by the `maxSafeLtv`
        AavePositionDetails memory details = positionDetails();
        if (details.maxSafeLtv < maxLtv) maxLtv = details.maxSafeLtv;
        if (minLtv > maxLtv) revert CommonEventsAndErrors.InvalidParam();

        if (details.currentLtv < minLtv || details.currentLtv > maxLtv) {
            revert LtvOutOfRange(details.currentLtv, minLtv, maxLtv);
        }
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function validateLoanUtilizationRatioInRange(uint256 minUR, uint256 maxUR) external view override {
        if (minUR > maxUR) revert CommonEventsAndErrors.InvalidParam();
        uint256 _currentUR = _currentLoanTokenUtilizationRatio(aavePool);
        if (_currentUR < minUR || _currentUR > maxUR) revert UtilizationRatioOutOfRange(_currentUR, minUR, maxUR);
    }

    /****** VIEWS ******/

    /// @inheritdoc IOpalAdapterAaveV3
    function encodeImmutableArgs(
        address _aavePoolAddressProvider,
        address[] calldata _collateralTokens,
        address _loanToken
    ) external view returns (bytes memory result) {
        if (_collateralTokens.length == 0 || _collateralTokens.length > MAX_COLLATERAL_TOKENS) revert CommonEventsAndErrors.InvalidLength();

        IAavePool pool = IAavePool(IPoolAddressesProvider(_aavePoolAddressProvider).getPool());

        result = abi.encodePacked(
            _aavePoolAddressProvider,
            _loanToken,
            pool.getReserveData(_loanToken).variableDebtTokenAddress,
            uint8(_collateralTokens.length)
        );

        address collateralToken;
        for (uint256 i; i < _collateralTokens.length; ++i) {
            collateralToken = _collateralTokens[i];
            if (collateralToken == _loanToken) revert CommonEventsAndErrors.InvalidToken(_loanToken);
            result = bytes.concat(
                result, abi.encodePacked(collateralToken, pool.getReserveData(collateralToken).aTokenAddress)
            );
        }
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function encodeInitArgs(address _initialOwner, uint8 _defaultEMode, uint256 _maxLoanUtilizationRatioOnJoin)
        external
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(_initialOwner, _defaultEMode, _maxLoanUtilizationRatioOnJoin);
    }

    /// @inheritdoc IOpalAdapter
    function tokens() external view override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        assetTokens = collateralTokens();
        liabilityTokens = new address[](1);
        liabilityTokens[0] = loanToken();
    }

    /// @inheritdoc IOpalAdapter
    function balanceSheet()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        address[] memory _aTokens = aaveATokens();
        assetAmounts = new uint256[](_aTokens.length);
        for (uint256 i; i < _aTokens.length; ++i) {
            assetAmounts[i] = IERC20(_aTokens[i]).balanceOf(address(this));
        }

        liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = IERC20(aaveDToken()).balanceOf(address(this));
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function joinMetrics()
        public
        view
        override
        returns (AssetSupplyMetrics[] memory supplyMetrics, LiabilityBorrowMetrics memory borrowMetrics)
    {
        // Aave can set caps on both the supply side and the borrow side
        IAavePool _pool = aavePool;
        address[] memory _collateralTokens = collateralTokens();
        address[] memory _aTokens = aaveATokens();
        uint256 _length = _collateralTokens.length;
        supplyMetrics = new AssetSupplyMetrics[](_length);
        uint256 isolationModeDebtCeiling;
        uint256 isolationModeTotalDebt;

        // Aave determines if we're in isolation mode based on how many unique collateral tokens
        // have been supplied (based on balance). This just approximates for the pragmatic case where
        // it's how many unique collateral tokens are used in the adapter, with the assumption the adapter
        // will provide all of them.
        bool isSingleCollateral = _length == 1;
        for (uint256 i; i < _length; ++i) {
            (supplyMetrics[i], isolationModeDebtCeiling, isolationModeTotalDebt) =
                _assetSupplyMetrics(_pool, _collateralTokens[i], _aTokens[i], isSingleCollateral);
        }

        borrowMetrics = _liabilityBorrowMetrics(_pool, isolationModeDebtCeiling, isolationModeTotalDebt);
    }

    /// @inheritdoc IOpalAdapter
    function maxJoin()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        (AssetSupplyMetrics[] memory supplyMetrics, LiabilityBorrowMetrics memory borrowMetrics) = joinMetrics();

        uint256 _length = supplyMetrics.length;
        assetAmounts = new uint256[](_length);
        for (uint256 i; i < _length; ++i) {
            assetAmounts[i] = _availableToSupply(supplyMetrics[i]);
        }

        liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = _availableToBorrow(borrowMetrics);
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function exitMetrics()
        public
        view
        override
        returns (AssetWithdrawMetrics[] memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics)
    {
        // Aave can set caps on both the supply side and the borrow side
        IAavePool _pool = aavePool;
        address[] memory _collateralTokens = collateralTokens();
        address[] memory _aTokens = aaveATokens();
        uint256 _length = _collateralTokens.length;
        withdrawMetrics = new AssetWithdrawMetrics[](_length);
        for (uint256 i; i < _length; ++i) {
            withdrawMetrics[i] = _assetWithdrawMetrics(_pool, _collateralTokens[i], _aTokens[i]);
        }

        repayMetrics = _liabilityRepayMetrics(_pool);
    }

    /// @inheritdoc IOpalAdapter
    function maxExit()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        (AssetWithdrawMetrics[] memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics) = exitMetrics();

        uint256 _length = withdrawMetrics.length;
        assetAmounts = new uint256[](_length);
        for (uint256 i; i < _length; ++i) {
            // The global amount of a token which can be withdrawn given the aave flags and aToken balance
            assetAmounts[i] = withdrawMetrics[i].withdrawingDisabled ? 0 : withdrawMetrics[i].availableSupply;
        }

        /// The global amount of the `loanToken` which can be repaid given the aave flags and dToken supply
        liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = repayMetrics.repayingDisabled ? 0 : repayMetrics.alreadyBorrowed;
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function positionDetails() public view override returns (AavePositionDetails memory details) {
        (
            details.totalCollateralBase,
            details.totalDebtBase,
            details.availableBorrowsBase,
            details.liquidationLtv,
            details.maxSafeLtv,
            details.healthFactor
        ) = aavePool.getUserAccountData(address(this));

        // Aave represents as 1e4, upscale to WAD
        details.liquidationLtv *= LTV_CONVERSION_SCALAR;
        details.maxSafeLtv *= LTV_CONVERSION_SCALAR;

        details.currentLtv = _calculateLtv(details.totalDebtBase, details.totalCollateralBase);
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public view override(OpalAdapterBase, IOpalAdapter) returns (uint256 ltv) {
        return positionDetails().currentLtv;
    }

    /// @inheritdoc IOpalAdapter
    function maxSafeLtv() external view override returns (uint256) {
        return positionDetails().maxSafeLtv;
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public view override(OpalAdapterBase, IOpalAdapter) returns (uint256) {
        return positionDetails().liquidationLtv;
    }

    /// @inheritdoc IOpalAdapterAaveV3
    function currentLoanTokenUtilizationRatio() external view override returns (uint256 utilizationRatio) {
        return _currentLoanTokenUtilizationRatio(aavePool);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OpalAdapterBase)
        returns (bool)
    {
        return OpalAdapterBase.supportsInterface(interfaceId) || interfaceId == type(IOpalAdapterAaveV3).interfaceId;
    }

    /****** PRIVATE ******/

    /// @dev borrow the `loanToken` and transfer to recipient
    function _borrow(IAavePool pool, uint256 borrowAmount, address recipient) private {
        address _loanToken = loanToken();
        pool.borrow(_loanToken, borrowAmount, INTEREST_RATE_MODE, referralCode, address(this));
        IERC20(_loanToken).safeTransfer(recipient, borrowAmount);
    }

    /// @dev Fill in the asset supply metrics given Aave config and stats
    function _assetSupplyMetrics(IAavePool pool, address collateralToken, address aToken, bool singleCollateral)
        private
        view
        returns (AssetSupplyMetrics memory metrics, uint256 isolationModeDebtCeiling, uint256 isolationModeTotalDebt)
    {
        AaveDataTypes.ReserveDataLegacy memory reserveData = pool.getReserveData(collateralToken);
        AaveDataTypes.ReserveConfigurationMap memory config = reserveData.configuration;

        (bool isActive, bool isFrozen,/*bool borrowingEnabled*/, bool isPaused) = config.getFlags();
        metrics.supplyingDisabled = !isActive || isFrozen || isPaused;

        // An aave supply cap == 0 means 'no cap', we represent this as type(uint256).max
        metrics.aaveSupplyCap = config.getSupplyCap();
        if (metrics.aaveSupplyCap == 0) {
            metrics.aaveSupplyCap = type(uint256).max;
        } else {
            metrics.aaveSupplyCap = metrics.aaveSupplyCap * (10 ** config.getDecimals());
        }

        // Cannot just use aToken.totalSupply() as this doesn't include the unminted
        // `accruedToTreasury` yet. The implementation here matches aave supply validation.
        metrics.alreadySupplied = AaveWadRayMath.rayMul(
            pool.getReserveNormalizedIncome(collateralToken),
            (IAaveAToken(aToken).scaledTotalSupply() + reserveData.accruedToTreasury)
        );

        // 'in isolation mode' within Aave is defined by having a single collateral which has
        // a non-zero debt ceiling
        if (singleCollateral) {
            isolationModeDebtCeiling = config.getDebtCeiling();
            isolationModeTotalDebt = reserveData.isolationModeTotalDebt;
        }
    }

    /// @dev Fill in the asset withdraw metrics given Aave config and stats
    function _assetWithdrawMetrics(IAavePool pool, address underlyingToken, address aToken)
        private
        view
        returns (AssetWithdrawMetrics memory metrics)
    {
        AaveDataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlyingToken);

        (bool isActive,,, bool isPaused) = config.getFlags();
        metrics.withdrawingDisabled = !isActive || isPaused;

        metrics.availableSupply = IERC20(underlyingToken).balanceOf(aToken);
    }

    /// @dev Calculate the available collateral that can be supplied given the metrics
    function _availableToSupply(AssetSupplyMetrics memory metrics) private pure returns (uint256) {
        if (metrics.supplyingDisabled) return 0;
        if (metrics.aaveSupplyCap == type(uint256).max) return type(uint256).max;
        unchecked {
            return metrics.aaveSupplyCap > metrics.alreadySupplied ? metrics.aaveSupplyCap - metrics.alreadySupplied : 0;
        }
    }

    /// @dev The current `loanToken` utilization ratio on Aave
    function _currentLoanTokenUtilizationRatio(IAavePool pool) private view returns (uint256) {
        address _loanToken = loanToken();
        (uint256 availableSupply, uint256 alreadyBorrowed) = _debtSupply(_loanToken, pool.getReserveData(_loanToken));

        uint256 totalDebtSupply = availableSupply + alreadyBorrowed;
        return totalDebtSupply > 0
            ? alreadyBorrowed.mulDiv(OrigamiMath.WAD, totalDebtSupply, OrigamiMath.Rounding.ROUND_UP)
            : 0;
    }

    /// @dev What's already been borrowed and the remaining available supply
    function _debtSupply(address _loanToken, AaveDataTypes.ReserveDataLegacy memory reserveData)
        private
        view
        returns (uint256 availableSupply, uint256 alreadyBorrowed)
    {
        // Available underlying which can be borrowed, held by the aToken
        availableSupply = IERC20(_loanToken).balanceOf(reserveData.aTokenAddress);

        // The amount already borrowed - this includes any accrued debt up to now.
        alreadyBorrowed = IERC20(reserveData.variableDebtTokenAddress).totalSupply();
    }

    /// @dev Fill in the debt borrow metrics given Aave config and stats
    function _liabilityBorrowMetrics(IAavePool pool, uint256 isolationModeDebtCeiling, uint256 isolationModeTotalDebt)
        private
        view
        returns (LiabilityBorrowMetrics memory metrics)
    {
        address _loanToken = loanToken();
        AaveDataTypes.ReserveDataLegacy memory reserveData = pool.getReserveData(_loanToken);
        AaveDataTypes.ReserveConfigurationMap memory config = reserveData.configuration;

        (bool isActive, bool isFrozen, bool borrowingEnabled, bool isPaused) = config.getFlags();
        metrics.borrowingDisabled = !isActive || isFrozen || !borrowingEnabled || isPaused;

        // An aave borrow cap == 0 means 'no cap', we represent this as type(uint256).max
        uint256 debtDecimals = config.getDecimals();
        metrics.aaveBorrowCap = config.getBorrowCap();
        if (metrics.aaveBorrowCap == 0) {
            metrics.aaveBorrowCap = type(uint256).max;
        } else {
            metrics.aaveBorrowCap = metrics.aaveBorrowCap * (10 ** debtDecimals);
        }

        // Get the current available liquidity and already borrowed (including accrued)
        (metrics.availableSupply, metrics.alreadyBorrowed) = _debtSupply(_loanToken, reserveData);

        // Use the policy set max UR to derive the borrow cap for joins
        // If the max UR = 1e18, then set the cap to type(uint256).max
        uint256 _maxLoanUtilizationRatioOnJoin = maxLoanUtilizationRatioOnJoin;
        metrics.joinBorrowCap = _maxLoanUtilizationRatioOnJoin < OrigamiMath.WAD
            ? _maxLoanUtilizationRatioOnJoin.mulDiv(
                metrics.availableSupply + metrics.alreadyBorrowed, OrigamiMath.WAD, OrigamiMath.Rounding.ROUND_DOWN
            )
            : type(uint256).max;

        // If the debt ceiling is non-zero it is in 'isolation mode'
        if (isolationModeDebtCeiling != 0) {
            // If the debt isn't borrowable in isolation, then set borrowing as disabled.
            if (!config.getBorrowableInIsolation()) metrics.borrowingDisabled = true;

            // The isolation mode debt is represented with 2 decimal places
            uint256 factor = 10 ** (debtDecimals - AaveReserveConfiguration.DEBT_CEILING_DECIMALS);
            metrics.isolationModeDebtCeiling = isolationModeDebtCeiling * factor;
            metrics.isolationModeTotalDebt = isolationModeTotalDebt * factor;
        }
    }

    /// @dev Calculate the available amount remining which can be borrowed given the stats
    function _availableToBorrow(LiabilityBorrowMetrics memory metrics) private pure returns (uint256 available) {
        if (metrics.borrowingDisabled) return 0;

        // Use the min of the aave cap and the origami policy set cap
        uint256 borrowCap =
            metrics.joinBorrowCap < metrics.aaveBorrowCap ? metrics.joinBorrowCap : metrics.aaveBorrowCap;

        // Get the available limit under the cap
        available = borrowCap > metrics.alreadyBorrowed ? borrowCap - metrics.alreadyBorrowed : 0;

        // Also cap to the remaining balance of tokens available to borrow
        if (metrics.availableSupply < available) {
            available = metrics.availableSupply;
        }

        // Finally if its in isolation mode (debt ceiling > 0) then also cap to the available isolation mode debt
        if (metrics.isolationModeDebtCeiling > 0) {
            uint256 isoModeAvailable = metrics.isolationModeDebtCeiling > metrics.isolationModeTotalDebt
                ? metrics.isolationModeDebtCeiling - metrics.isolationModeTotalDebt
                : 0;

            // Take the min
            if (isoModeAvailable < available) {
                available = isoModeAvailable;
            }
        }
    }

    /// @dev The global amount of the `loanToken` which can be repaid given the aave flags and dToken supply
    function _liabilityRepayMetrics(IAavePool pool) private view returns (LiabilityRepayMetrics memory metrics) {
        AaveDataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(loanToken());

        (bool isActive,,, bool isPaused) = config.getFlags();
        metrics.repayingDisabled = !isActive || isPaused;

        // The global amount of total debt
        metrics.alreadyBorrowed = IERC20(aaveDToken()).totalSupply();
    }

    /// @dev Ensure the UR of the debt token in Aave is under the policy set amount
    function _validateLoanTokenUtilizationRatio(IAavePool pool) private view {
        uint256 _currentUR = _currentLoanTokenUtilizationRatio(pool);
        if (_currentUR > maxLoanUtilizationRatioOnJoin) {
            revert UtilizationRatioOutOfRange(_currentUR, 0, maxLoanUtilizationRatioOnJoin);
        }
    }
}
