// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "contracts/test/external/olympus/src/Kernel.sol";
import {ROLESv1, RolesConsumer} from "contracts/test/external/olympus/src/modules/ROLES/OlympusRoles.sol";
import {ICoolerTreasuryBorrower} from "contracts/test/external/olympus/src/policies/interfaces/cooler/ICoolerTreasuryBorrower.sol";
import {SafeERC20 as SafeTransferLib} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import {TRSRYv1} from "contracts/test/external/olympus/src/modules/TRSRY/TRSRY.v1.sol";

// Handles unit conversion - eg if the debt token is 6dp (USDC)
// No staking token (eg sUSDS) at rest.
contract MockCoolerTreasuryBorrower is ICoolerTreasuryBorrower, Policy, RolesConsumer {
    using SafeTransferLib for IERC20Metadata;

    /// @inheritdoc ICoolerTreasuryBorrower
    uint8 public constant override DECIMALS = 18;

    /// @notice Olympus V3 Treasury Module
    TRSRYv1 public TRSRY;

    IERC20Metadata private immutable _debtToken;

    uint256 private immutable _conversionScalar;

    bytes32 public constant COOLER_ROLE = bytes32("treasuryborrower_cooler");
    bytes32 public constant ADMIN_ROLE = bytes32("treasuryborrower_admin");

    constructor(
        address kernel_,
        address debtToken_
    ) Policy(Kernel(kernel_)) {
        _debtToken = IERC20Metadata(debtToken_);

        uint8 tokenDecimals = _debtToken.decimals();
        if (tokenDecimals > DECIMALS) revert InvalidParam();
        _conversionScalar = 10 ** (DECIMALS - tokenDecimals);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));

        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (
            ROLES_MAJOR != 1 ||
            TRSRY_MAJOR != 1
        ) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        requests = new Permissions[](3);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function borrow(uint256 amountInWad, address recipient) external override onlyRole(COOLER_ROLE) {
        if (amountInWad == 0) revert ExpectedNonZero();
        if (recipient == address(0)) revert InvalidAddress();

        // Convert into the debtToken scale rounding UP
        uint256 debtTokenAmount = _convertToDebtTokenAmount(amountInWad);

        uint256 outstandingDebt = TRSRY.reserveDebt(_debtToken, address(this));
        TRSRY.setDebt({
            debtor_: address(this),
            token_: _debtToken,
            amount_: outstandingDebt + debtTokenAmount
        });

        TRSRY.increaseWithdrawApproval(address(this), _debtToken, debtTokenAmount);
        TRSRY.withdrawReserves(recipient, _debtToken, debtTokenAmount);
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function repay() external override onlyRole(COOLER_ROLE) {
        uint256 debtTokenAmount = _debtToken.balanceOf(address(this));
        _reduceDebtToTreasury(debtTokenAmount);

        _debtToken.safeTransfer(address(TRSRY), debtTokenAmount);
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function writeOffDebt(uint256 debtTokenAmount) external override onlyRole(COOLER_ROLE) {
        _reduceDebtToTreasury(debtTokenAmount);
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function setDebt(uint256 debtTokenAmount) external override onlyRole(ADMIN_ROLE) {
        TRSRY.setDebt({
            debtor_: address(this),
            token_: _debtToken,
            amount_: debtTokenAmount
        });
    }

    /// @inheritdoc ICoolerTreasuryBorrower
    function convertToDebtTokenAmount(
        uint256 amountInWad
    ) external override view returns (IERC20 dToken, uint256 dTokenAmount) {
        dToken = _debtToken;
        dTokenAmount = _convertToDebtTokenAmount(amountInWad);
    }

    function debtToken() external override view returns (IERC20) {
        return _debtToken;
    }

    function _convertToDebtTokenAmount(uint256 amountInWad) private view returns (uint256) {
        return FixedPointMathLib.mulDivUp(amountInWad, 1, _conversionScalar);
    }

    /// @dev Decrease the debt to TRSRY, floored at zero
    function _reduceDebtToTreasury(uint256 debtTokenAmount) private {
        if (debtTokenAmount == 0) revert ExpectedNonZero();

        // This policy is allowed to overpay TRSRY, in which case it's debt is set to zero
        // and any future repayments are just deposited. There are no 'credits' for overpaying
        uint256 outstandingDebt = TRSRY.reserveDebt(_debtToken, address(this));
        uint256 delta;
        if (outstandingDebt > debtTokenAmount) {
            unchecked {
                delta = outstandingDebt - debtTokenAmount;
            }
        }
        TRSRY.setDebt({debtor_: address(this), token_: _debtToken, amount_: delta});
    }
}
