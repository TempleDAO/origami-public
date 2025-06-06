pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/olympus/IOlympusCoolerV1.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice The cooler interface for Olympus Cooler v1.1, v1.2, v1.3
interface ICooler {
    /// @notice A loan begins with a borrow request.
    struct Request {
        uint256 amount;             // Amount to be borrowed.
        uint256 interest;           // Annualized percentage to be paid as interest.
        uint256 loanToCollateral;   // Requested loan-to-collateral ratio.
        uint256 duration;           // Time to repay the loan before it defaults.
        bool active;                // Any lender can clear an active loan request.
        address requester;          // The address that created the request.
    }

    /// @notice A request is converted to a loan when a lender clears it.
    struct Loan {
        Request request;        // Loan terms specified in the request.
        uint256 principal;      // Amount of principal debt owed to the lender.
        uint256 interestDue;    // Interest owed to the lender.
        uint256 collateral;     // Amount of collateral pledged.
        uint256 expiry;         // Time when the loan defaults.
        address lender;         // Lender's address.
        address recipient;      // Recipient of repayments.
        bool callback;          // If this is true, the lender must inherit CoolerCallback.
    }

    /// @notice Repay a loan to get the collateral back.
    /// @dev    Despite a malicious lender could reenter with the callback, the
    ///         usage of `msg.sender` prevents any economical benefit to the
    ///         attacker, since they would be repaying the loan themselves.
    /// @param  loanID_ index of loan in loans[].
    /// @param  repayment_ debt tokens to be repaid.
    /// @return collateral given back to the borrower.
    function repayLoan(uint256 loanID_, uint256 repayment_) external returns (uint256);

    /// @notice This address owns the collateral in escrow.
    function owner() external pure returns (address _owner);

    /// @notice Getter for Loan data as a struct.
    /// @param loanID_ index of loan in loans[].
    /// @return Loan struct.
    function getLoan(uint256 loanID_) external view returns (Loan memory);
}

/// @notice The cooler factory interface for Olympus Cooler v1.1IOlympusClearinghouseV1_1
interface IOlympusCoolerFactoryV1_1 {
    /// @notice creates a new Escrow contract for collateral and debt tokens.
    /// @param  collateral_ the token given as collateral.
    /// @param  debt_ the token to be lent. Interest is denominated in debt tokens.
    /// @return cooler address of the contract.
    function generateCooler(IERC20 collateral_, IERC20 debt_) external returns (address cooler);

    /// @notice Mapping to validate deployed coolers.
    function created(address cooler) external view returns (bool);
}

/// @notice The cooler factory interface for Olympus Cooler v1.2 and v1.3
interface IOlympusCoolerFactoryV1_2 is IOlympusCoolerFactoryV1_1 {
    /// @notice Getter function to get an existing cooler for a given user <> collateral <> debt combination.
    function getCoolerFor(address user_, address collateral_, address debt_) external view returns (address);
}

interface IOlympusClearinghouseBase {
    /// @notice Lend to a cooler.
    /// @dev    To simplify the UX and easily ensure that all holders get the same terms,
    ///         this function requests a new loan and clears it in the same transaction.
    /// @param  cooler_ to lend to.
    /// @param  amount_ of DAI to lend.
    /// @return the id of the granted loan.
    function lendToCooler(ICooler cooler_, uint256 amount_) external returns (uint256);

    /// @notice view function computing loan for a collateral amount.
    /// @param  collateral_ amount of gOHM.
    /// @return debt (amount to be lent + interest) for a given collateral amount.
    function getLoanForCollateral(uint256 collateral_) external pure returns (uint256, uint256);
}

/// @notice The clearinghouse interface for Olympus Cooler v1.1
interface IOlympusClearinghouseV1_1 is IOlympusClearinghouseBase {
    function factory() external view returns (IOlympusCoolerFactoryV1_1);
}

/// @notice The clearinghouse interface for Olympus Cooler v1.2 and v1.3
interface IOlympusClearinghouseV1_2 is IOlympusClearinghouseBase {
    function factory() external view returns (IOlympusCoolerFactoryV1_2);
}
