pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/adapters/OpalAdapterEuler.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { EVCUtil } from "contracts/external/ethereum-vault-connector/utils/EVCUtil.sol";
import { AmountCap, AmountCapLib } from "contracts/external/euler-vault-kit/AmountCapLib.sol";
import "contracts/external/euler-vault-kit/Constants.sol" as EulerConstants;

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOpalAdapterEuler } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterEuler.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Euler
/// @notice An OPAL Adapter which is a borrow position in an Euler V2 market.
/// That will be a single position with exactly one collateral token and exactly one debt token.
contract OpalAdapterEuler is IOpalAdapterEuler, OpalAdapterBase, EVCUtil {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;
    using AmountCapLib for AmountCap;

    /// @inheritdoc IOpalAdapterEuler
    uint256 public override maxLoanUtilizationRatioOnJoin;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_LOAN_TOKEN = 0x34; // start: byte 52, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_EULER_LOAN_VAULT = 0x48; // start: byte 72, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_COLLATERAL_TOKEN = 0x5c; // start: byte 92, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_EULER_COLLATERAL_VAULT = 0x70; // start: byte 112, len: 20 bytes (address)

    /// @dev Euler's LTV scale is 1e4 (9000 == 90% LTV). Origmai uses 1e18 (0.9e18 == 90% LTV)
    uint256 private constant LTV_CONVERSION_SCALAR = 1e14;

    // Note EVCUtil inheritance provides utility to the `callThroughEVC` modifier to defer Euler health checks when
    // required.
    constructor(bytes32 _implTypeAndVersion, address _ethereumVaultConnector)
        OpalAdapterBase(_implTypeAndVersion)
        EVCUtil(_ethereumVaultConnector)
    { }

    /// @inheritdoc OpalAdapterBase
    function _adapterInit(bytes calldata data) internal override {
        address _loanToken = loanToken();
        address _collateralToken = collateralToken();
        if (_collateralToken == _loanToken) revert CommonEventsAndErrors.InvalidToken(_collateralToken);

        (address _initialOwner, uint256 _maxLoanUtilizationRatioOnJoin) = abi.decode(data, (address, uint256));
        _init(_initialOwner);

        if (_maxLoanUtilizationRatioOnJoin > OrigamiMath.WAD) revert CommonEventsAndErrors.InvalidParam();
        maxLoanUtilizationRatioOnJoin = _maxLoanUtilizationRatioOnJoin;

        // Verify that the collateral vault asset matches the collateralToken
        // and enable that collateral vault on the EVC
        IEVault _collateralVault = collateralVault();
        if (_collateralVault.asset() != _collateralToken) {
            revert CommonEventsAndErrors.InvalidAddress(_collateralToken);
        }
        evc.enableCollateral(address(this), address(_collateralVault));

        // Verify that the borrow vault asset matches the loanToken
        // and enable the controller for the borrow vault on the EVC
        IEVault _borrowVault = borrowVault();
        if (_borrowVault.asset() != _loanToken) revert CommonEventsAndErrors.InvalidAddress(_loanToken);
        evc.enableController(address(this), address(_borrowVault));

        // Euler has the concept of subaccounts, see:
        // https://docs.euler.finance/developers/evc/integration-guide/#how-sub-account-addresses-are-structured-and-derived
        // This contract only ever uses the "main" address (sub-account 0)
        // EVC config is set on the prefix - the first 19 bytes of this account's address
        bytes19 addressPrefix = evc.getAddressPrefix(address(this));

        // Lockdown mode restricts operations on the EVC, but not on the EVaults
        // As we don't plan to reconfigure this contract once deployed, we can lock it down from the start
        evc.setLockdownMode(addressPrefix, true);
        // We don't need Permit2 either, as allowances are handled here manually
        evc.setPermitDisabledMode(addressPrefix, true);

        // The Euler vaults are trusted for max approval
        IERC20(_loanToken).forceApprove(address(_borrowVault), type(uint256).max);
        IERC20(_collateralToken).forceApprove(address(_collateralVault), type(uint256).max);
    }

    /****** IMMUTABLE GETTERS ******/

    /// @inheritdoc IOpalAdapterEuler
    function loanToken() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_LOAN_TOKEN);
    }

    /// @inheritdoc IOpalAdapterEuler
    function borrowVault() public view override returns (IEVault) {
        return IEVault(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_EULER_LOAN_VAULT));
    }

    /// @inheritdoc IOpalAdapterEuler
    function collateralToken() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_COLLATERAL_TOKEN);
    }

    /// @inheritdoc IOpalAdapterEuler
    function collateralVault() public view override returns (IEVault) {
        return IEVault(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_EULER_COLLATERAL_VAULT));
    }

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        view
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        // Euler vaults are separate for collateral vs debt, and have separate caps.
        // The group isn't unique to the (collateralVault, borrowVault) pair since one of the
        // vaults may be used with another Euler vault in another adapter. eg:
        //  Adapter1: collateral: sUSDe; debt: USDC
        //  Adapter2: collateral: USDe; debt: USDC
        // In that case the cap on the USDC euler vault needs to be shared
        assetGroupIds = new bytes32[](1);
        assetGroupIds[0] = bytes32(uint256(uint160(address(collateralVault()))));

        liabilityGroupIds = new bytes32[](1);
        liabilityGroupIds[0] = bytes32(uint256(uint160(address(borrowVault()))));
    }

    /****** ADMIN ACTIONS ******/

    /// @inheritdoc IOpalAdapterEuler
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

        // Supply collateral
        // This may revert if above supply caps, paused, etc.
        IERC20(collateralToken()).safeTransferFrom(msg.sender, address(this), supplyAmount);
        collateralVault().deposit(supplyAmount, address(this));

        // Borrow the single debt token
        IEVault _borrowVault = borrowVault();
        if (borrowAmount > 0) {
            // This may revert if not sufficient liquidity, above borrow caps, paused, etc.
            // NB: No need to check the LTV is under the 'safe LTV', as Euler does that internally upon a borrow
            _borrowVault.borrow(borrowAmount, recipient);

            // Validate that the loanToken UR is under the policy threshold for joins
            _validateLoanTokenUtilizationRatio(_borrowVault);
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

        // Repay the debt
        if (repayAmount > 0) {
            IERC20(loanToken()).safeTransferFrom(msg.sender, address(this), repayAmount);

            // In the unlikely scenario that repayAmount is greater than the outstanding debt,
            // cap the amount actually repaid, so there may be a balance of tokens left here.
            // This can be skimmed later as part of the Bundler Actions.
            _repayUptoMax(repayAmount);
        }

        // Withdraw the collateral
        // In the unlikely scenario that withdrawAmount is greater than the supplied amount,
        // this will revert. This is expected because recipient should receive all the the tokens.
        // The OPAL vaults are seeded by the protocol first - if the vault is shutdown the protocol
        // will be responsible for exiting any dust from its seed position.
        _withdraw(collateralVault(), withdrawAmount, recipient);

        // NB: No need to validate the UR vs the policy set amount on an exit
        // NB: No need to check the LTV, as Euler does that internally on a collateral withdraw

        // The amounts here are the inputs, they are not adjusted to the 'actual' amounts
        // repaid/withdrawn
        emit Exit(assetAmounts, liabilityAmounts);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOpalAdapterEuler
    function supplyCollateral(uint256 amount, uint256 minAmount)
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

        // Euler doesn't revert for a zero amount
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        IEVault _collateralVault = collateralVault();
        uint256 shares = _collateralVault.deposit(amount, address(this));

        // Accounts for rounding errors and potential future deposit fees in Euler vaults
        return _collateralVault.previewRedeem(shares);
    }

    /// @inheritdoc IOpalAdapterEuler
    function withdrawCollateral(uint256 amount, address recipient)
        external
        override
        withApprovedBundler
        returns (uint256 withdrawn)
    {
        // Euler doesn't revert for a zero amount
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        return _withdraw(collateralVault(), amount, recipient);
    }

    /// @inheritdoc IOpalAdapterEuler
    function borrow(uint256 amount, address recipient)
        external
        override
        withApprovedBundler
        returns (uint256 borrowedAmount)
    {
        // Euler doesn't revert for a zero amount
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        return borrowVault().borrow(amount, recipient);
    }

    /// @inheritdoc IOpalAdapterEuler
    function repay(uint256 amount, uint256 minAmount) external override withApprovedBundler returns (uint256) {
        if (amount == type(uint256).max) {
            amount = IERC20(loanToken()).balanceOf(address(this));
        }

        // Skip if the amount is less than the threshold
        if (amount < minAmount) return 0;
        return _repayUptoMax(amount);
    }

    /// @inheritdoc IOpalAdapterEuler
    function withDeferredEulerChecks(bytes calldata callbackData) external override callThroughEVC withApprovedBundler {
        _reenterBundle(callbackData);
    }

    /****** BUNDLER PLUGIN CHECKS ******/

    /// @inheritdoc IOpalAdapterEuler
    function validateLtvInRange(uint256 minLtv, uint256 maxLtv) external view override {
        IEVault _collateralVault = collateralVault();
        IEVault _borrowVault = borrowVault();

        // Bound the maxLTV by the `maxSafeLtv`
        uint256 __maxSafeLtv = _maxSafeLtv(_collateralVault, _borrowVault);
        if (__maxSafeLtv < maxLtv) maxLtv = __maxSafeLtv;

        if (minLtv > maxLtv) revert CommonEventsAndErrors.InvalidParam();

        uint256 _ltv = _currentLtv(_collateralVault, _borrowVault);
        if (_ltv < minLtv || _ltv > maxLtv) revert LtvOutOfRange(_ltv, minLtv, maxLtv);
    }

    /// @inheritdoc IOpalAdapterEuler
    function validateLoanUtilizationRatioInRange(uint256 minUR, uint256 maxUR) external view override {
        if (minUR > maxUR) revert CommonEventsAndErrors.InvalidParam();
        uint256 _currentUR = _currentLoanTokenUtilizationRatio(borrowVault());
        if (_currentUR < minUR || _currentUR > maxUR) revert UtilizationRatioOutOfRange(_currentUR, minUR, maxUR);
    }

    /****** VIEWS ******/

    /// @inheritdoc IOpalAdapterEuler
    function encodeImmutableArgs(address _collateralVault, address _borrowVault)
        external
        view
        override
        returns (bytes memory result)
    {
        address _collateralToken = IEVault(_collateralVault).asset();
        address _loanToken = IEVault(_borrowVault).asset();
        if (_collateralToken == _loanToken) revert CommonEventsAndErrors.InvalidToken(_collateralToken);

        result = abi.encodePacked(_loanToken, _borrowVault, _collateralToken, _collateralVault);
    }

    /// @inheritdoc IOpalAdapterEuler
    function encodeInitArgs(address _initialOwner, uint256 _maxLoanUtilizationRatioOnJoin)
        external
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(_initialOwner, _maxLoanUtilizationRatioOnJoin);
    }

    /// @inheritdoc IOpalAdapter
    function tokens() external view override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        assetTokens = new address[](1);
        assetTokens[0] = collateralToken();
        liabilityTokens = new address[](1);
        liabilityTokens[0] = loanToken();
    }

    /// @inheritdoc IOpalAdapter
    function balanceSheet()
        public
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        assetAmounts = new uint256[](1);
        assetAmounts[0] = _suppliedBalance(collateralVault());
        liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = borrowVault().debtOf(address(this));
    }

    /// @inheritdoc IOpalAdapterEuler
    function joinMetrics()
        external
        view
        override
        returns (AssetSupplyMetrics memory supplyMetrics, LiabilityBorrowMetrics memory borrowMetrics)
    {
        supplyMetrics = _assetSupplyMetrics();
        borrowMetrics = _liabilityBorrowMetrics();
    }

    /// @inheritdoc IOpalAdapter
    function maxJoin()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        // - Euler supply and borrow caps ARE taken into account.
        // - If an Euler hook target isn't enabled but the Euler 'operation' IS disabled, that IS taken into account
        // - If an Euler hook target is enabled, that IS NOT taken into consideration as it depends on the exact
        // calldata of that operation at runtime.
        // - The Euler vault is (generally) a beacon proxy. If the implementation is upgraded to be a 'ReadOnlyProxy'
        //   which effectively pauses all vaults globally, that IS NOT taken into consideration.
        // If this needs to be improved for UX/integration purposes, this contract can be updated (at the tradeoff
        // with runtime gas and robustness)

        // Rather than deriving the max assets from `_assetSupplyMetrics()`, the vault implements
        // ERC4626::maxDeposit() which can be used for better accuracy. The address parameter isn't used.
        assetAmounts = new uint256[](1);
        assetAmounts[0] = collateralVault().maxDeposit(address(this));

        liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = _availableToBorrow(_liabilityBorrowMetrics());
    }

    /// @inheritdoc IOpalAdapterEuler
    function exitMetrics()
        public
        view
        override
        returns (AssetWithdrawMetrics memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics)
    {
        withdrawMetrics = _assetWithdrawMetrics();
        repayMetrics = _liabilityRepayMetrics();
    }

    /// @inheritdoc IOpalAdapter
    function maxExit()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        // The same Euler implementaiton considerations apply as in maxJoin()
        (AssetWithdrawMetrics memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics) = exitMetrics();

        assetAmounts = new uint256[](1);
        assetAmounts[0] = withdrawMetrics.withdrawingDisabled ? 0 : withdrawMetrics.availableSupply;

        liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = repayMetrics.repayingDisabled ? 0 : repayMetrics.totalDebt;
    }

    /// @inheritdoc IOpalAdapterEuler
    function eulerEVC() external view override returns (address) {
        return address(evc);
    }

    /// @inheritdoc IOpalAdapterEuler
    function positionDetails() external view override returns (EulerPositionDetails memory details) {
        IEVault _collateralVault = collateralVault();
        IEVault _borrowVault = borrowVault();

        // `supplied` includes the interest earned on the supplied balance (expressed in supplyToken decimals)
        details.supplied = _suppliedBalance(_collateralVault);

        // `borrowed` includes the interest (expressed in borrowToken decimals)
        details.borrowed = _borrowVault.debtOf(address(this));

        _populateLtvDetails(details, _collateralVault, _borrowVault);
        details.maxSafeLtv = _maxSafeLtv(_collateralVault, _borrowVault);
        details.healthFactor = _healthFactor(details.currentLtv, details.liquidationLtv);
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public view override(OpalAdapterBase, IOpalAdapter) returns (uint256 ltv) {
        return _currentLtv(collateralVault(), borrowVault());
    }

    /// @inheritdoc IOpalAdapter
    function maxSafeLtv() external view override returns (uint256) {
        return _maxSafeLtv(collateralVault(), borrowVault());
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public view override(IOpalAdapter, OpalAdapterBase) returns (uint256) {
        return _liquidationLtv(collateralVault(), borrowVault());
    }

    /// @inheritdoc IOpalAdapterEuler
    function currentLoanTokenUtilizationRatio() external view override returns (uint256 utilizationRatio) {
        return _currentLoanTokenUtilizationRatio(borrowVault());
    }

    /// @inheritdoc IOpalAdapterEuler
    function areAnyVaultOperationsDisabled(IEVault vault, uint32 operationsBitMask)
        public
        view
        override
        returns (bool)
    {
        (address hookTarget, uint32 hookedOps) = vault.hookConfig();

        // Check if *any* of the flags in operationsBitMask are set
        // and that the hookTarget is address(0)
        // Extends the Euler FlagsLib
        bool anySet = (hookedOps & operationsBitMask) != 0;
        return anySet && hookTarget == address(0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OpalAdapterBase)
        returns (bool)
    {
        return OpalAdapterBase.supportsInterface(interfaceId) || interfaceId == type(IOpalAdapterEuler).interfaceId;
    }

    /****** PRIVATE ******/

    /// @dev Populate the adapter's current LTV details using the latest liquidity metrics in Euler
    /// This updates `positionDetails` in place
    function _populateLtvDetails(EulerPositionDetails memory details, IEVault _collateralVault, IEVault _borrowVault)
        private
        view
    {
        details.liquidationLtv = _liquidationLtv(_collateralVault, _borrowVault);

        // From Euler's IEVault.accountLiquidity():
        //   `riskAdjustedCollateralValue`: Total risk adjusted value of all collaterals in unit of account
        //   `liabilityValue`: Value of debt in unit of account (no adjustments)
        // Risk adjustment always decreases the collateral value by the liquidation margin
        // Example: for a deposit worth 10k USD, and a liquidationLTV of 95%, the riskAdjustedCollateralValue
        // would be 9.5k
        // See: https://github.com/euler-xyz/euler-vault-kit/blob/master/docs/whitepaper.md#risk-adjustment
        (details.collateralValueInUnitOfAcct, details.liabilityValueInUnitOfAcct) = _borrowVault.accountLiquidity({
            account: address(this),
            liquidation: true // liquidity values for liquidation purposes
        });

        // Undo the risk adjustment to get the actual collateral value
        //   riskAdjustedCollateral = collateral * liquidationLTV
        //   collateral = riskAdjustedCollateral / liquidationLTV
        // round down to underestimate collateral (more conservative).
        // Note liabilities are not risk-adjusted, so no extra calc required
        details.collateralValueInUnitOfAcct = details.liquidationLtv == 0
            ? 0
            : details.collateralValueInUnitOfAcct
                .mulDiv(OrigamiMath.WAD, details.liquidationLtv, OrigamiMath.Rounding.ROUND_DOWN);

        // Derive the current LTV, rounding up to be conservative.
        details.currentLtv = _calculateLtv(details.liabilityValueInUnitOfAcct, details.collateralValueInUnitOfAcct);
    }

    /// @dev The liquidation LTV of the loanToken to collateralToken. Represented in WAD
    function _liquidationLtv(IEVault _collateralVault, IEVault _borrowVault) private view returns (uint256) {
        return _borrowVault.LTVLiquidation(address(_collateralVault)) * LTV_CONVERSION_SCALAR;
    }

    /// @dev The current `loanToken` utilization ratio on Euler
    function _currentLoanTokenUtilizationRatio(IEVault _borrowVault) private view returns (uint256) {
        uint256 alreadyBorrowed = _borrowVault.totalBorrows();
        uint256 totalDebtSupply = _borrowVault.totalAssets();
        return totalDebtSupply > 0
            ? alreadyBorrowed.mulDiv(OrigamiMath.WAD, totalDebtSupply, OrigamiMath.Rounding.ROUND_UP)
            : 0;
    }

    /// @dev The amount of `collateralToken` this adapter can withdraw, irrespective
    /// if the Euler vault is paused for redemptions or not.
    function _suppliedBalance(IEVault _collateralVault) private view returns (uint256) {
        return _collateralVault.previewRedeem(_collateralVault.balanceOf(address(this)));
    }

    /// @dev Repay the outstanding debt that this adapter holds.
    /// If `repayAmount` is greater than the outstanding debt, it will be capped to the outstanding balance.
    function _repayUptoMax(uint256 repayAmount) internal returns (uint256 debtRepaidAmount) {
        IEVault _borrowVault = borrowVault();

        if (repayAmount < type(uint256).max) {
            // If repayAmount > outstanding debt, use `max` to repay it all
            uint256 outstandingDebt = _borrowVault.debtOf(address(this));
            if (repayAmount > outstandingDebt) repayAmount = type(uint256).max;
        }

        debtRepaidAmount = _borrowVault.repay(repayAmount, address(this));
    }

    /// @dev IEVault does not support type(uint256).max for withdrawals,
    ///      so for max withdrawals we use redeem, with type(uint256).max
    /// @dev if withdrawAmount > supplied balance, IEVault will revert
    function _withdraw(IEVault _collateralVault, uint256 withdrawAmount, address recipient)
        private
        returns (uint256 amountWithdrawn)
    {
        if (withdrawAmount == type(uint256).max) {
            amountWithdrawn = _collateralVault.redeem(type(uint256).max, recipient, address(this));
        } else {
            // The output of withdraw is the shares burned, not the assets withdrawn
            // euler will revert if amountWithdraw != withdrawAmount (except for type(uint256).max, which is handled
            // separately above)
            _collateralVault.withdraw(withdrawAmount, recipient, address(this));
            amountWithdrawn = withdrawAmount;
        }
    }

    /// @dev Ensure the UR of the debt token in Euler is under the policy set amount
    function _validateLoanTokenUtilizationRatio(IEVault _borrowVault) private view {
        uint256 _currentUR = _currentLoanTokenUtilizationRatio(_borrowVault);
        if (_currentUR > maxLoanUtilizationRatioOnJoin) {
            revert UtilizationRatioOutOfRange(_currentUR, 0, maxLoanUtilizationRatioOnJoin);
        }
    }

    /// @dev The current Loan-To-Value (LTV) of this adapter.
    function _currentLtv(IEVault _collateralVault, IEVault _borrowVault) private view returns (uint256 ltv) {
        EulerPositionDetails memory details;
        _populateLtvDetails(details, _collateralVault, _borrowVault);
        return details.currentLtv;
    }

    /// @dev The maximum Loan-To-Value (LTV) that this adapter can safetly borrow up to.
    function _maxSafeLtv(IEVault _collateralVault, IEVault _borrowVault) private view returns (uint256) {
        // The EulerV2 system has a borrow LTV that is less or equal than the liquidation LTV, (safety margin)
        // This call returns Borrowing LTV for a given collateral, in 1e4 scale
        return _borrowVault.LTVBorrow(address(_collateralVault)) * LTV_CONVERSION_SCALAR;
    }

    /// @dev Calculate the available amount remaining which can be borrowed given the stats
    function _availableToBorrow(LiabilityBorrowMetrics memory metrics) private pure returns (uint256) {
        if (metrics.borrowingDisabled) return 0;

        // Use the min of the euler cap and the origami policy set cap
        uint256 borrowCap = metrics.eulerBorrowCap;
        if (metrics.joinBorrowCap < metrics.eulerBorrowCap) {
            borrowCap = metrics.joinBorrowCap;
        }

        // Get the available limit under the cap
        uint256 availableUnderCap = borrowCap > metrics.alreadyBorrowed ? borrowCap - metrics.alreadyBorrowed : 0;

        // Return the min(available under cap, remaining balance of tokens available to borrow)
        return (availableUnderCap < metrics.availableSupply) ? availableUnderCap : metrics.availableSupply;
    }

    /// @dev Fill in the asset supply metrics
    function _assetSupplyMetrics() private view returns (AssetSupplyMetrics memory metrics) {
        IEVault _collateralVault = collateralVault();
        metrics.supplyingDisabled = areAnyVaultOperationsDisabled(_collateralVault, EulerConstants.OP_DEPOSIT);

        (uint16 _supplyCap,) = _collateralVault.caps();
        metrics.eulerSupplyCap = AmountCap.wrap(_supplyCap).resolve();
        metrics.alreadySupplied = _collateralVault.totalAssets();
    }

    /// @dev Fill in the asset withdraw metrics
    function _assetWithdrawMetrics() private view returns (AssetWithdrawMetrics memory metrics) {
        IEVault _collateralVault = collateralVault();
        metrics.withdrawingDisabled = areAnyVaultOperationsDisabled(
            _collateralVault,
            // Both withdraw() and redeem() are used for withdrawals
            EulerConstants.OP_WITHDRAW | EulerConstants.OP_REDEEM
        );

        // Limited to the balance of the collateral token 'cash' available for withdrawal in the collateralVault
        // ERC4626::maxWithdraw() isn't used since that takes this contract's balance into consideration.
        // whereas this interface returns the global position irrespective of the current position in this adapter.
        metrics.availableSupply = _collateralVault.cash();
    }

    /// @dev Fill in the debt borrow metrics
    function _liabilityBorrowMetrics() private view returns (LiabilityBorrowMetrics memory metrics) {
        IEVault _borrowVault = borrowVault();
        metrics.borrowingDisabled = areAnyVaultOperationsDisabled(_borrowVault, EulerConstants.OP_BORROW);

        // Within Euler AmountCap::resolve() 'no cap' is represented as type(uint256).max already.
        (, uint16 _borrowCap) = _borrowVault.caps();
        metrics.eulerBorrowCap = AmountCap.wrap(_borrowCap).resolve();

        // cash() is the vault total holdings of `asset` (borrowToken)
        metrics.availableSupply = _borrowVault.cash();
        metrics.alreadyBorrowed = _borrowVault.totalBorrows();

        // Use the policy set max UR to derive the borrow cap for joins
        // If the max UR = 1e18, then set the cap to type(uint256).max
        uint256 _maxLoanUtilizationRatioOnJoin = maxLoanUtilizationRatioOnJoin;
        metrics.joinBorrowCap = _maxLoanUtilizationRatioOnJoin < OrigamiMath.WAD
            ? _maxLoanUtilizationRatioOnJoin.mulDiv(
                metrics.availableSupply + metrics.alreadyBorrowed, OrigamiMath.WAD, OrigamiMath.Rounding.ROUND_DOWN
            )
            : type(uint256).max;
    }

    /// @dev Fill in the debt repay metrics
    function _liabilityRepayMetrics() private view returns (LiabilityRepayMetrics memory metrics) {
        IEVault _borrowVault = borrowVault();
        metrics.repayingDisabled = areAnyVaultOperationsDisabled(_borrowVault, EulerConstants.OP_REPAY);

        // The total debt by all users in this vault including accrued
        metrics.totalDebt = _borrowVault.totalBorrows();
    }

    /// @dev Override the withApprovedBundler modifier in order to use the EVCUtil sender
    /// This is required when using in conjunction with callThroughEVC in order to get the real
    /// sender rather than the EVC as the msg.sender
    /// forge-lint:disable-next-item(unwrapped-modifier-logic)
    modifier withApprovedBundler() override {
        bool resetBundler = _withApprovedBundler(_msgSender());
        _;
        _resetBundler(resetBundler);
    }
}
