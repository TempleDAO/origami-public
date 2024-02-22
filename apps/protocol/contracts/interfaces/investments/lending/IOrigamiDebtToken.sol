pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/IOrigamiDebtToken.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Origami Debt Token
 * @notice A rebasing ERC20 representing debt accruing at continuously compounding interest rate.
 * 
 * On a repayment, any accrued interest is repaid. When there is no more outstanding interest,
 * then the principal portion is paid down.
 * 
 * Only approved minters can mint/burn/transfer the debt on behalf of a user.
 */
interface IOrigamiDebtToken is IERC20Metadata {
    event InterestRateSet(address indexed debtor, uint96 rate);
    event MinterSet(address indexed account, bool value);
    event DebtorBalance(address indexed debtor, uint128 principal, uint128 interest);
    event Checkpoint(address indexed debtor, uint128 principal, uint128 interest);

    struct Debtor {
        /// @notice The current principal owed by this debtor
        uint128 principal;

        /// @notice The debtor's interest (no principal) owed as of the timeCheckpoint
        uint128 interestCheckpoint;

        /// @notice The last checkpoint time of this debtor's interest
        /// @dev uint32 => max time of Feb 7 2106
        uint32 timeCheckpoint;

        /// @notice The current interest rate specific to this debtor, set by elevated access
        /// @dev 1e18 format, where 0.01e18 = 1%
        uint96 rate;
    }

    /**
     * @notice Per address status of debt
     */
    function debtors(address account) external view returns (
        /// @notice The current principal owed by this debtor
        uint128 principal,

        /// @notice The debtor's interest (no principal) owed as of the timeCheckpoint
        uint128 interestCheckpoint,

        /// @notice The last checkpoint time of this debtor's interest
        /// @dev uint32 => max time of Feb 7 2106
        uint32 timeCheckpoint,

        /// @notice The current interest rate specific to this debtor, set by elevated access
        /// @dev 1e18 format, where 0.01e18 = 1%
        uint96 rate
    );

    /**
     * @notice Elevated access can add/remove an address which is able to mint/burn/transfer debt
     */
    function setMinter(address account, bool value) external;

    /**
     * @notice Update the continuously compounding interest rate for a debtor, from this block onwards.
     */
    function setInterestRate(address _debtor, uint96 _rate) external;

    /**
     * @notice Approved minters can add a new debt position on behalf of a user.
     * @param _debtor The address of the debtor who is issued new debt
     * @param _mintAmount The notional amount of debt tokens to issue.
     */
    function mint(address _debtor, uint256 _mintAmount) external;

    /**
     * @notice Approved minters can burn debt on behalf of a user.
     * @dev Interest is repaid prior to the principal.
     * @param _debtor The address of the debtor
     * @param _burnAmount The notional amount of debt tokens to repay.
     */
    function burn(address _debtor, uint256 _burnAmount) external;

    /**
     * @notice Approved minters can burn the entire debt on behalf of a user.
     * @param _debtor The address of the debtor
     */
    function burnAll(address _debtor) external returns (uint256 burnedAmount);

    /**
     * @notice Checkpoint multiple accounts interest (no principal) owed up to this block.
     */
    function checkpointDebtorsInterest(address[] calldata _debtors) external;

    struct DebtOwed {
        uint256 principal;
        uint256 interest;
    }

    /**
     * @notice The current debt for a given set of users split out by principal and interest
     */
    function currentDebtsOf(address[] calldata _debtors) external view returns (
        DebtOwed[] memory debtsOwed
    );

    /**
      * @notice The current total principal + total (estimate) interest owed by all debtors.
      * @dev Note the principal is up to date as of this block, however the interest portion is likely stale.
      * The `estimatedTotalInterest` is only updated when each debtor checkpoints, so it's going to be out of date.
      * For more up to date current totals, off-chain aggregation of balanceOf() will be required - eg via subgraph.
      */
    function currentTotalDebt() external view returns (
        DebtOwed memory debtOwed
    );

    /**
     * @notice A set of addresses which are approved to mint/burn
     */
    function minters(address account) external view returns (bool);

    /**
     * @notice The net amount of principal debt minted across all users.
     */
    function totalPrincipal() external view returns (uint128);

    /**
     * @notice The latest estimate of the interest (no principal) owed by all debtors as of now.
     * @dev Indicative only. This total is only updated on a per debtor basis when that debtor gets 
     * checkpointed
     * So it is generally slightly out of date as each debtor will accrue interest independently 
     * on different rates.
     */
    function estimatedTotalInterest() external view returns (uint128);

    /**
     * @notice The amount of interest which has been repaid to date across all debtors
     */
    function repaidTotalInterest() external view returns (uint256);

    /**
     * @notice The estimated amount of interest which has been repaid to date 
     * plus the (estimated) outstanding as of now
     */
    function estimatedCumulativeInterest() external view returns (uint256);

    /**
     * @notice The total supply as of the latest checkpoint, excluding a set of debtors
     */
    function totalSupplyExcluding(address[] calldata debtorList) external view returns (uint256);

    /**
     * @dev The latest position data for a debtor
     */
    struct DebtorPosition {
        /// @dev The debtor's principal
        uint128 principal;

        /// @dev The amount of interest this debtor owes
        uint128 interest;
        
        /// @dev The increase in interest this debtor owes since the last checkpoint
        uint128 interestDelta;

        /// @dev The risk premium interest rate for this debtor
        uint96 rate;
    }

    /**
     * @notice A view of the derived position data.
     */
    function getDebtorPosition(address debtor) external view returns (DebtorPosition memory);
}
