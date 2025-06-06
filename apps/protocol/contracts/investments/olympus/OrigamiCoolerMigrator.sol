pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/olympus/OrigamiCoolerMigrator.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import {
    ICooler,
    IOlympusCoolerFactoryV1_1,
    IOlympusCoolerFactoryV1_2,
    IOlympusClearinghouseV1_1,
    IOlympusClearinghouseV1_2
} from "contracts/interfaces/external/olympus/IOlympusCoolerV1.sol";
import { IMonoCooler } from "contracts/interfaces/external/olympus/IMonoCooler.sol";
import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";
import { IERC3156FlashLender } from "contracts/interfaces/external/makerdao/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "contracts/interfaces/external/makerdao/IERC3156FlashBorrower.sol";
import { IDaiUsds } from "contracts/interfaces/external/makerdao/IDaiUsds.sol";

import { IOrigamiCoolerMigrator } from "contracts/interfaces/investments/olympus/IOrigamiCoolerMigrator.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Cooler Migrator
 * @notice This contract helps migrate Cooler V1.1, V1.2, V1.3 and Mono Cooler positions into hOHM.
 * @dev Only handles migrating coolers with gOHM collateral, and DAI and USDS debt (so 18 decimals only)
 */
contract OrigamiCoolerMigrator is IOrigamiCoolerMigrator, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice hOHM vault
    IOrigamiTokenizedBalanceSheetVault public immutable override hOHM;

    /// @notice Flashloan Lender
    IERC3156FlashLender public immutable override flashloanLender;

    /// @notice DaiUsds conversion contract
    IDaiUsds public immutable override daiUsds;

    /// @notice Mono Cooler 
    IMonoCooler public immutable override monoCooler;

    /// @notice Dai ERC20 token
    IERC20 public immutable override dai;

    /// @notice OHM Governance contract
    IERC20 public immutable override gOHM;

    /// @notice USDS ERC20 token
    IERC20 public immutable override usds;

    /// @notice Set maximum iterations for getting cooler loans
    uint256 public override maxLoans = 50;

    /// @notice Olympus Clearinghouse v1.1
    address private immutable _clearinghouse_v1_1;

    /// @notice Olympus Clearinghouse v1.2
    address private immutable _clearinghouse_v1_2;

    /// @notice Olympus Clearinghouse v1.3
    address private immutable _clearinghouse_v1_3;

    struct _FlashloanData {
        /// @notice All the cooler loans to migrate
        AllCoolerLoansPreview allLoans;

        /// @notice Mono cooler specific migration delegation requests
        IDLGTEv1.DelegationRequest[] delegationRequests;

        /// @notice The total USDS debt required
        /// Flash loan amount is in DAI and converted to USDS
        uint256 totalUsdsDebt;

        /// @notice The cooler owner account
        /// Needs to have granted gOHM approval, and also USDS approval if extra is required
        address account;
    }

    constructor(
        address initialOwner_,
        address hOHM_,
        address gOHM_,
        address dai_,
        address usds_,
        address daiUsds_,
        address monoCooler_,
        address flashloanLender_,
        address[3] memory clearinghouses_ // v1.1, v1.2, v1.3 in order
    ) OrigamiElevatedAccess(initialOwner_) {
        hOHM = IOrigamiTokenizedBalanceSheetVault(hOHM_);
        gOHM = IERC20(gOHM_);
        dai = IERC20(dai_);
        usds = IERC20(usds_);
        daiUsds = IDaiUsds(daiUsds_);
        monoCooler = IMonoCooler(monoCooler_);
        flashloanLender = IERC3156FlashLender(flashloanLender_);

        _clearinghouse_v1_1 = clearinghouses_[0];
        _clearinghouse_v1_2 = clearinghouses_[1];
        _clearinghouse_v1_3 = clearinghouses_[2];
    }

    /// @inheritdoc IOrigamiCoolerMigrator
    function setMaxLoans(uint256 maxLoans_) external override onlyElevatedAccess {
        maxLoans = maxLoans_;
        emit MaxLoansSet(maxLoans_);
    }

    /// @inheritdoc IOrigamiCoolerMigrator
    function migrate(
        AllCoolerLoansMigration calldata allLoans,
        MonoCoolerMigration calldata monoCoolerParams,
        SlippageParams calldata slippageParams
    ) external override {
        AllCoolerLoansPreview memory allLoansPreview = _fillCoolerLoansPreviewForMigration(msg.sender, allLoans);
        MigrationPreview memory mPreview = previewMigration(allLoansPreview);

        uint256 totalDebt = mPreview.totalDaiDebt + mPreview.totalUsdsDebt;
        if (totalDebt == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _checkSlippage(mPreview, slippageParams, totalDebt);

        // If authorization signature is set, then do the auth now
        if (allLoans.migrateMonoCooler) {
            _setMonoCoolerAuthorization(monoCoolerParams, msg.sender);
        }

        bytes memory flashloanData = abi.encode(_FlashloanData({
            allLoans: allLoansPreview,
            delegationRequests: monoCoolerParams.delegationRequests,
            totalUsdsDebt: mPreview.totalUsdsDebt,
            account: msg.sender
        }));

        // flash loan is in dai only
        flashloanLender.flashLoan(
            this,
            address(dai),
            totalDebt,
            flashloanData
        );
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address initiator,
        address /*token*/,
        uint256 flashLoanAmount,
        uint256 /*lenderFee*/,
        bytes calldata params
    ) external override returns (bytes32) {
        // Lender fee in DssFlash is set to 0. Therefore we don't use the `lenderFee` param in function
        if (msg.sender != address(flashloanLender)) revert CommonEventsAndErrors.InvalidAccess();
        if (initiator != address(this)) revert CommonEventsAndErrors.InvalidAccess();

        // decode data
        _FlashloanData memory data = abi.decode(params, (_FlashloanData));

        // Convert DAI into any required USDS debt once.
        if (data.totalUsdsDebt > 0) {
            dai.safeIncreaseAllowance(address(daiUsds), data.totalUsdsDebt);
            daiUsds.daiToUsds(address(this), data.totalUsdsDebt);
        }

        // Repay cooler v1/v2/v3 and then pull that amount of gOHM collateral from user
        (
            uint256 totalCoolerCollateral,
            uint256 totalMonoCoolerCollateral
        ) = _repayCoolers(data.account, data.allLoans, data.allLoans.monoCooler, data.delegationRequests);
        gOHM.safeTransferFrom(data.account, address(this), totalCoolerCollateral);

        // Join into hOHM
        (uint256 hohmSharesReceived, uint256 usdsReceived) = _bringItHohm(
            totalCoolerCollateral + totalMonoCoolerCollateral,
            data.account
        );

        emit CoolerLoansMigrated(
            data.account,
            flashLoanAmount,
            totalCoolerCollateral + totalMonoCoolerCollateral,
            hohmSharesReceived,
            usdsReceived
        );

        // Either send the user surplus or pull extra required funds from the user
        // The gap to pull may be required if the USDS per hOHM share price is less 
        // than the user's current aggregate cooler LTV
        int256 usdsDelta = usdsReceived.encodeInt256() - flashLoanAmount.encodeInt256();
        if (usdsDelta > 0) {
            usds.safeTransfer(data.account, uint256(usdsDelta));
        } else {
            usds.safeTransferFrom(data.account, address(this), uint256(-usdsDelta));
        }

        // convert usds back to dai
        usds.safeIncreaseAllowance(address(daiUsds), flashLoanAmount);
        daiUsds.usdsToDai(address(this), flashLoanAmount);

        dai.safeIncreaseAllowance(address(flashloanLender), flashLoanAmount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @inheritdoc IOrigamiCoolerMigrator
    function getCoolerLoansFor(
        address account,
        address cooler_v1_1
    ) external override view returns (AllCoolerLoansPreview memory allLoans) {
        address clearinghouse;

        // cooler v.1.1 -- the factory doesn't have a `getCoolerFor()` method so it's
        // found off-chain first and passed in.
        if (cooler_v1_1 != address(0)) {
            clearinghouse = _clearinghouse_v1_1;
            IOlympusCoolerFactoryV1_1 factory = IOlympusClearinghouseV1_1(clearinghouse).factory();
            if (!factory.created(cooler_v1_1)) revert InvalidCooler(cooler_v1_1);
            allLoans.v1_1 = CoolerPreviewInfo(cooler_v1_1, _getAllLoansForCooler(cooler_v1_1, clearinghouse));
        }

        // cooler v.1.2
        {
            clearinghouse = _clearinghouse_v1_2;
            IOlympusCoolerFactoryV1_2 factory = IOlympusClearinghouseV1_2(clearinghouse).factory();
            address cooler = factory.getCoolerFor(account, address(gOHM), address(dai));
            if (cooler != address(0)) {
                allLoans.v1_2 = CoolerPreviewInfo(cooler, _getAllLoansForCooler(cooler, clearinghouse));
            }
        }

        // cooler v.1.3
        {
            clearinghouse = _clearinghouse_v1_3;
            IOlympusCoolerFactoryV1_2 factory = IOlympusClearinghouseV1_2(clearinghouse).factory();
            address cooler = factory.getCoolerFor(account, address(gOHM), address(usds));
            if (cooler != address(0)) {
                allLoans.v1_3 = CoolerPreviewInfo(cooler, _getAllLoansForCooler(cooler, clearinghouse));
            }
        }

        // MonoCooler
        allLoans.monoCooler = MonoCoolerLoanPreviewInfo({
            debt: monoCooler.accountDebt(account),
            collateral: monoCooler.accountCollateral(account)
        });
    }

    /// @inheritdoc IOrigamiCoolerMigrator
    function getClearinghouses() external override view returns (
        address v1_1,
        address v1_2,
        address v1_3
    ) {
        v1_1 = _clearinghouse_v1_1;
        v1_2 = _clearinghouse_v1_2;
        v1_3 = _clearinghouse_v1_3;
    }

    /// @inheritdoc IOrigamiCoolerMigrator
    function getCoolerV1_1Params() external override view returns (address, address, address) {
        return (
            address(IOlympusClearinghouseV1_1(_clearinghouse_v1_1).factory()),
            address(gOHM),
            address(dai)
        );
    }

    /// @inheritdoc IOrigamiCoolerMigrator
    function previewMigration(
        AllCoolerLoansPreview memory allLoans
    ) public override view returns (MigrationPreview memory preview) {
        _aggreateLoans(allLoans.v1_1.loans, preview, true);  // DAI
        _aggreateLoans(allLoans.v1_2.loans, preview, true);  // DAI
        _aggreateLoans(allLoans.v1_3.loans, preview, false); // USDS

        // MonoCooler - USDS
        {
            preview.totalCollateral += allLoans.monoCooler.collateral;
            preview.totalUsdsDebt += allLoans.monoCooler.debt;
        }

        (
            uint256 shares, 
            /*uint256[] memory assets*/,
            uint256[] memory liabilities
        ) = hOHM.previewJoinWithToken(address(gOHM), preview.totalCollateral);
        preview.hOhmShares = shares;
        preview.hOhmLiabilities = liabilities[0];
    }

    /// @dev Populate the preview information for a given cooler
    /// Verify the cooler, and that it matches the expected account and clearinghouse version
    function _verifyAndFillCoolerPreview(
        address account,
        CoolerLoanMigrationInfo calldata coolerMigrateInfo,
        CoolerPreviewInfo memory coolerPreviewInfo,
        address expectedClearinghouse
    ) private view {
        // Skip if specified as address(0)
        address cooler = coolerMigrateInfo.cooler;
        if (cooler == address(0)) return;

        // Must have been created via the expected factory, and the caller must be the owner
        IOlympusCoolerFactoryV1_1 factory = IOlympusClearinghouseV1_1(expectedClearinghouse).factory();
        if (!factory.created(cooler)) revert InvalidCooler(cooler);
        if (ICooler(cooler).owner() != account) { revert InvalidOwner(); }

        uint256 loanId;
        uint256 length = coolerMigrateInfo.loanIds.length;
        coolerPreviewInfo.cooler = cooler;
        coolerPreviewInfo.loans = new CoolerLoanPreviewInfo[](length);

        for (uint256 i; i < length; ++i) {
            loanId = coolerMigrateInfo.loanIds[i];
            try ICooler(cooler).getLoan(loanId) returns (ICooler.Loan memory loan) {
                // Check if this loan is valid
                if (
                    loan.lender != expectedClearinghouse ||   // Not the expected Olympus clearinghouse
                    loan.principal == 0 ||                      // Already fully repaid
                    block.timestamp > loan.expiry               // Expired
                ) revert InvalidLoanId(cooler, loanId);

                coolerPreviewInfo.loans[i] = CoolerLoanPreviewInfo({
                    loanId: loanId,
                    collateral: loan.collateral,
                    debt: loan.principal + loan.interestDue
                });
            } catch Panic(uint256 errorCode) {
                // Expect an out-of-bounds error only
                if (errorCode == 0x32) revert InvalidLoanId(cooler, loanId);
                revert CommonEventsAndErrors.UnknownExecuteError(abi.encode(errorCode));
            }
        }
    }

    /// @dev Populate the preview information (the current debt & collateral) for a given set of loans per cooler version
    /// Each cooler and loan will be verified to ensure it's valid for migration
    function _fillCoolerLoansPreviewForMigration(
        address account,
        AllCoolerLoansMigration calldata allLoansMigrate
    ) private view returns (AllCoolerLoansPreview memory allLoansPreview) {
        if (maxLoans == 0) revert CommonEventsAndErrors.IsPaused();

        _verifyAndFillCoolerPreview(account, allLoansMigrate.v1_1, allLoansPreview.v1_1, _clearinghouse_v1_1);
        _verifyAndFillCoolerPreview(account, allLoansMigrate.v1_2, allLoansPreview.v1_2, _clearinghouse_v1_2);
        _verifyAndFillCoolerPreview(account, allLoansMigrate.v1_3, allLoansPreview.v1_3, _clearinghouse_v1_3);

        if (allLoansMigrate.migrateMonoCooler) {
            allLoansPreview.monoCooler = MonoCoolerLoanPreviewInfo({
                collateral: monoCooler.accountCollateral(account),
                debt: monoCooler.accountDebt(account)
            });
        }
    }

    function _setMonoCoolerAuthorization(MonoCoolerMigration calldata monoCoolerParams, address account) private {
        IMonoCooler.Authorization calldata authorization = monoCoolerParams.authorization;

        // If account is address zero, it is assumed caller didn't intend setAuthorized to be called
        // Otherwise it must match the caller
        if (authorization.account == address(0)) return;
        if (authorization.account != account) revert InvalidOwner();
        if (authorization.authorized != address(this)) revert InvalidAuth();

        // Nothing to do if already authorized
        if (monoCooler.isSenderAuthorized(address(this), account)) return;

        monoCooler.setAuthorizationWithSig(authorization, monoCoolerParams.signature);
    }

    /// @dev Populate all loans for a given cooler, up to a (mutable) maximum size
    function _getAllLoansForCooler(
        address cooler,
        address expectedClearinghouse
    ) private view returns (CoolerLoanPreviewInfo[] memory loanInfo) {
        uint256 maxLoansCache = maxLoans;
        CoolerLoanPreviewInfo[] memory info = new CoolerLoanPreviewInfo[](maxLoansCache);
        uint256 loanIndex;

        // Cooler doesn't provide a way to (cleanly) iterate -- so need to use exception handling here
        // First get all loans and break when we get an out-of-bounds
        for (uint256 i; i < maxLoansCache; ++i) {
            try ICooler(cooler).getLoan(i) returns (ICooler.Loan memory loan) {
                // Skip if this loan isn't valid
                if (
                    loan.lender != expectedClearinghouse || // Not the expected Olympus clearinghouse
                    loan.principal == 0 ||                    // Already fully repaid
                    block.timestamp > loan.expiry             // Expired
                ) continue;

                info[loanIndex++] = CoolerLoanPreviewInfo({
                    loanId: i,
                    debt: (loan.principal + loan.interestDue),
                    collateral: loan.collateral
                });
            } catch Panic(uint256 errorCode) {
                // Expect an out-of-bounds error only
                if (errorCode == 0x32) break;
                revert CommonEventsAndErrors.UnknownExecuteError(abi.encode(errorCode));
            }
        }

        // Now post process such that the returned loanInfo is the correct size
        loanInfo = new CoolerLoanPreviewInfo[](loanIndex);
        for (uint256 i; i < loanIndex; ++i) {
            loanInfo[i] = info[i];
        }
    }

    function _aggreateLoans(
        CoolerLoanPreviewInfo[] memory loans,
        MigrationPreview memory preview,
        bool isDaiDebt
    ) private pure {
        for (uint256 i; i < loans.length; ++i) {
            if (isDaiDebt) {
                preview.totalDaiDebt += loans[i].debt;
            } else {
                preview.totalUsdsDebt += loans[i].debt;
            }
            preview.totalCollateral += loans[i].collateral;
        }
    }

    function _repayCoolers(
        address account,
        AllCoolerLoansPreview memory allLoans,
        MonoCoolerLoanPreviewInfo memory monoCoolerLoanInfo,
        IDLGTEv1.DelegationRequest[] memory delegationRequests
    ) private returns (
        uint256 totalCoolerCollateral,
        uint256 totalMonoCoolerCollateral
    ) {
        // Repay cooler v1/v2/v3 and then pull that amount of gOHM collateral from user
        totalCoolerCollateral = _repayCooler(allLoans.v1_1, dai);
        totalCoolerCollateral += _repayCooler(allLoans.v1_2, dai);
        totalCoolerCollateral += _repayCooler(allLoans.v1_3, usds);

        // Repay MonoCooler - gOHM collateral is sent to this contract.
        totalMonoCoolerCollateral = _repayMonoCooler(account, monoCoolerLoanInfo, delegationRequests);
    }

    function _repayCooler(CoolerPreviewInfo memory coolerInfo, IERC20 debtToken) private returns (uint256 totalCollateral) {
        address cooler = coolerInfo.cooler;
        if (cooler == address(0) || coolerInfo.loans.length == 0) return 0;

        // Max approve to save iterating twice, then rug approval at the end.
        debtToken.approve(cooler, type(uint).max);

        CoolerLoanPreviewInfo memory loanInfo;
        for (uint256 i; i < coolerInfo.loans.length; ++i) {
            loanInfo = coolerInfo.loans[i];
            ICooler(cooler).repayLoan(loanInfo.loanId, loanInfo.debt);
            totalCollateral += loanInfo.collateral;
        }

        debtToken.approve(cooler, 0);
    }

    function _repayMonoCooler(
        address account,
        MonoCoolerLoanPreviewInfo memory loanInfo,
        IDLGTEv1.DelegationRequest[] memory delegationRequests
    ) private returns (uint256 totalCollateral) {
        if (loanInfo.collateral == 0) return 0;

        if (loanInfo.debt != 0) {
            usds.safeIncreaseAllowance(address(monoCooler), loanInfo.debt);

            // Repay and check the output matches
            if (monoCooler.repay(loanInfo.debt.encodeUInt128(), account) != loanInfo.debt) {
                revert MismatchingDebt();
            }
        }

        // Withdraw and check the output matches
        if (loanInfo.collateral != monoCooler.withdrawCollateral(
            loanInfo.collateral.encodeUInt128(), 
            account, 
            address(this), 
            delegationRequests
        )) {
            revert MismatchingCollateral();
        }

        totalCollateral = loanInfo.collateral;
    }

    function _bringItHohm(
        uint256 totalCollateral,
        address account
    ) private returns (uint256 hohmShares, uint256 usdsReceived) {
        IERC20(gOHM).safeIncreaseAllowance(address(hOHM), totalCollateral);

        // join hOHM vault with token. send shares and liabilities to this contract first
        uint256[] memory liabilities;
        (hohmShares, /*assets*/, liabilities) = hOHM.joinWithToken(address(gOHM), totalCollateral, address(this));
        
        usdsReceived = liabilities[0];
        IERC20(hOHM).safeTransfer(account, hohmShares);
    }

    /// @dev Check slippage vs the latest preview
    function _checkSlippage(
        MigrationPreview memory mPreview,
        SlippageParams calldata slippageParams,
        uint256 totalDebt
    ) private pure {
        if (mPreview.hOhmShares < slippageParams.minHohmShares) {
            revert CommonEventsAndErrors.Slippage(slippageParams.minHohmShares, mPreview.hOhmShares);
        }

        if (mPreview.hOhmLiabilities > totalDebt) {
            // Expect at least `minUsdsReceived`
            uint256 delta = mPreview.hOhmLiabilities - totalDebt;
            if (delta < slippageParams.minUsdsSurplus) revert CommonEventsAndErrors.Slippage(slippageParams.minUsdsSurplus, delta);
        } else {
            // Expect at most `maxUsdsPulled`
            uint256 delta = totalDebt - mPreview.hOhmLiabilities;
            if (delta > slippageParams.maxUsdsShortfall) revert CommonEventsAndErrors.Slippage(slippageParams.maxUsdsShortfall, delta);
        }
    }

}
