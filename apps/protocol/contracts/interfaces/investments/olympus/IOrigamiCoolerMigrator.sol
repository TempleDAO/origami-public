pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/olympus/IOrigamiCoolerMigrator.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";
import { IMonoCooler } from "contracts/interfaces/external/olympus/IMonoCooler.sol";
import { IDaiUsds } from "contracts/interfaces/external/makerdao/IDaiUsds.sol";
import { IERC3156FlashLender } from "contracts/interfaces/external/makerdao/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "contracts/interfaces/external/makerdao/IERC3156FlashBorrower.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

/**
 * @title Cooler Migrator
 * @notice This contract helps migrate Cooler V1.1, V1.2, V1.3 and Mono Cooler positions into hOHM.
 * @dev Only handles migrating coolers with gOHM collateral, and DAI and USDS debt (so 18 decimals only)
 */
interface IOrigamiCoolerMigrator is IERC3156FlashBorrower {
    /// @notice The known OlympusDAO clearinghouses. 
    /// @dev Only migrations for cooler's where this is the lender are allowed
    struct AllClearinghouses {
        address v1_1;
        address v1_2;
        address v1_3;
    }

    //============================================================================================//
    //                                 MIGRATION PREVIEW STRUCTS                                  //
    //============================================================================================//

    /// @notice The representation of all cooler loans for an account
    struct AllCoolerLoansPreview {
        CoolerPreviewInfo v1_1;
        CoolerPreviewInfo v1_2;
        CoolerPreviewInfo v1_3;
        MonoCoolerLoanPreviewInfo monoCooler;
    }

    /// @notice Loans information for a given account's Cooler or MonoCooler
    struct CoolerPreviewInfo {
        /// @notice The address of an account's cooler
        /// @dev If the account doesn't have a cooler for this clearing house version, then 
        // cooler=address(0) and the loans would be empty.
        address cooler;
        
        /// @notice The individual loans within a cooler
        /// @dev May be empty, meaning the account does not have any loans for this cooler version.
        CoolerLoanPreviewInfo[] loans;
    }

    /// @notice One of the loan's details for a particular Cooler or MonoCooler
    struct CoolerLoanPreviewInfo {
        /// @notice Loan ID
        uint256 loanId;

        /// @notice Total collateral amount of cooler loans
        uint256 collateral;

        /// @notice Total debt amount of cooler loans
        uint256 debt;
    }

    /// @notice MonoCooler collateral and debt preview amounts
    struct MonoCoolerLoanPreviewInfo {
        /// @notice Total collateral amount of cooler loans
        uint256 collateral;

        /// @notice Total debt amount of cooler loans
        uint256 debt;
    }

    /// @notice The summary of what will happen in the migration
    struct MigrationPreview {
        /// @notice Total gOHM collateral amount being migrated.
        uint256 totalCollateral;

        /// @notice Total DAI debt amount being migrated.
        uint256 totalDaiDebt;

        /// @notice Total USDS debt amount being migrated.
        uint256 totalUsdsDebt;

        /// @notice The number of shares the account is expected to receive on migration
        uint256 hOhmShares;

        /// @notice Total liability received from joining hOHM. This amount should be at least equal
        /// to flashloan amount/total debt
        /// @dev If liability received is less than total debt, sender must give allowance of remainder to this 
        /// contract to pull tokens to 'fill the gap'
        uint256 hOhmLiabilities;
    }

    //============================================================================================//
    //                                    MIGRATION STRUCTS                                       //
    //============================================================================================//
    
    struct AllCoolerLoansMigration {
        CoolerLoanMigrationInfo v1_1;
        CoolerLoanMigrationInfo v1_2;
        CoolerLoanMigrationInfo v1_3;
        bool migrateMonoCooler;
    }

    /// @notice Loans information for a given account's Cooler or MonoCooler
    struct CoolerLoanMigrationInfo {
        /// @notice The address of an account's cooler
        /// @dev If address(0) then this cooler version won't be migrated
        address cooler;
        
        /// @notice The cooler loan id's to migrate
        /// @dev If empty, then this cooler version won't be migrated
        uint256[] loanIds;
    }

    struct MonoCoolerMigration {
        /// @notice Mono cooler account authorization
        /// @dev If `authorization.account` is empty, then the owner needs to have called 
        /// monoCooler.setAuthorization() prior to migration
        IMonoCooler.Authorization authorization;

        /// @notice Mono cooler account signature
        IMonoCooler.Signature signature;

        /// @notice Optional delegation requests when withdrawing account's collateral from MonoCooler
        IDLGTEv1.DelegationRequest[] delegationRequests;
    }

    struct SlippageParams {
        /// @notice The minimum number of hOHM shares expected to be received from the migration
        uint256 minHohmShares;

        /// @notice The minimum number of USDS surplus expected to be received from the migration
        /// @dev May be set to zero if a shortfall is expected instead
        uint256 minUsdsSurplus;

        /// @notice The maximum number of USDS expected to be pulled from the migration in the case
        /// of a shortfall from joining hOHM vs the migrated cooler debt
        /// @dev May be set to zero if a USDS surplus is expected instead
        uint256 maxUsdsShortfall;
    }

    //============================================================================================//
    //                                      EVENTS & ERRORS                                       //
    //============================================================================================//
    
    event CoolerLoansMigrated(
        address indexed account,
        uint256 totalDebtRepaid,
        uint256 totalCollateralWithdrawn,
        uint256 hohmSharesReceived,
        uint256 usdsReceived
    );
    event MaxLoansSet(uint256 maxLoans);

    error InvalidCooler(address cooler);
    error InvalidLoanId(address cooler, uint256 loanId);
    error MismatchingDebt();
    error MismatchingCollateral();
    error InvalidOwner();
    error InvalidAuth();

    //============================================================================================//
    //                                         MUTATATIVE                                         //
    //============================================================================================//
    
    /**
     * @notice Set maximum loans used when iterating through cooler loans
     * @param maxLoans Maximum loans used when iterating through cooler loans
     * @dev 0 maxLoans are allowed as a way to pause the migrator.
     */
    function setMaxLoans(uint256 maxLoans) external;

    /**
     * @notice Migrate cooler v1.1, v1.2, v1.3 and MonoCooler
     * @param allLoans All cooler loans to migrate
     * @param monoCoolerParams MonoCooler migration parameters
     * @param slippageParams Check expected shares and USDS surplus/shortfall
     */
    function migrate(
        AllCoolerLoansMigration calldata allLoans,
        MonoCoolerMigration calldata monoCoolerParams,
        SlippageParams calldata slippageParams
    ) external;

    //============================================================================================//
    //                                            VIEWS                                           //
    //============================================================================================//
    
    /// @notice hOHM vault
    function hOHM() external view returns (IOrigamiTokenizedBalanceSheetVault);

    /// @notice Flashloan Lender
    function flashloanLender() external view returns (IERC3156FlashLender);

    /// @notice DaiUsds conversion contract
    function daiUsds() external view returns (IDaiUsds);

    /// @notice Mono Cooler 
    function monoCooler() external view returns (IMonoCooler);

    /// @notice Dai ERC20 token
    function dai() external view returns (IERC20);

    /// @notice OHM Governance contract
    function gOHM() external view returns (IERC20);

    /// @notice USDS ERC20 token
    function usds() external view returns (IERC20);

    /// @notice Set maximum iterations for getting cooler loans
    function maxLoans() external view returns (uint256);

    /**
     * @notice Get cooler loans for a cooler
     * @param account Account address
     * @param cooler_v1_1 The address of the Cooler v1.1
     * @dev cooler_v1_1 can't be queried from this contract because v1 factory `generateCooler`
     * uses `msg.sender` in generating the cooler address. So must v1.1 cooler address must
     * be passed in. Set to address(0) if no v1.1 cooler
     * @return allLoans All cooler loans for this account across all versions
     */
    function getCoolerLoansFor(
        address account,
        address cooler_v1_1
    ) external view returns (AllCoolerLoansPreview memory allLoans);

    /**
     * @notice Get whitelisted clearing houses
     */
    function getClearinghouses() external view returns (
        address v1_1,
        address v1_2,
        address v1_3
    );

    /**
     * @notice A helper to return the cooler v1.1 factory address, and the params
     * to call on that factory (via callstatic)
     *  `function generateCooler(ERC20 collateral_, ERC20 debt_) external returns (address cooler);`
     * @dev Needs to be called via a connected wallet such that the msg.sender is the user
     * requesting to get their cooler v1.1 address.
     */
    function getCoolerV1_1Params() external view returns (
        address factory,
        address collateralToken,
        address debtToken
    );

    /**
     * @notice Get a preview of the cooler migrations
     * @param allLoans All cooler loans to migrate
     * @return preview Migration preview
     */
    function previewMigration(
        AllCoolerLoansPreview calldata allLoans
    ) external view returns (MigrationPreview memory preview);
    
}