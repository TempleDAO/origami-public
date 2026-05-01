pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/borrowAndLend/OrigamiEulerV2BorrowAndLend.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IMerklDistributor } from "contracts/interfaces/external/merkl/IMerklDistributor.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { IOrigamiEulerV2BorrowAndLend } from
    "contracts/interfaces/common/borrowAndLend/IOrigamiEulerV2BorrowAndLend.sol";

import { EVCUtil } from "contracts/external/ethereum-vault-connector/utils/EVCUtil.sol";
import { IEVC } from "contracts/interfaces/external/ethereum-vault-connector/IEthereumVaultConnector.sol";
import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { AmountCap, AmountCapLib } from "contracts/external/euler-vault-kit/AmountCapLib.sol";

/**
 * @notice An Origami abstraction over a borrow/lend Euler money market for
 * a single `supplyToken` and a single `borrowToken`.
 */
contract OrigamiEulerV2BorrowAndLend is IOrigamiEulerV2BorrowAndLend, OrigamiElevatedAccess, EVCUtil {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;
    using AmountCapLib for AmountCap;

    /**
     * @notice The token supplied as collateral
     */
    IERC20 private immutable _supplyToken;

    /**
     * @notice The token which is borrowed
     */
    IERC20 private immutable _borrowToken;

    /**
     * @notice The approved owner of the borrow/lend position
     */
    address public override positionOwner;

    /**
     * @notice The swapper for `borrowToken` <--> `supplyToken`
     */
    IOrigamiSwapper public override swapper;

    /**
     * @notice An Euler's ERC4626 EVault where `supplyToken` is deposited
     */
    IEVault public immutable override supplyVault;

    /**
     * @notice An Euler's ERC4626 EVault where `borrowToken` is borrowed from
     */
    IEVault public immutable override borrowVault;

    /**
     * @notice Euler's Ethereum Vault Connector
     */
    IEVC public immutable override eulerEVC;

    /**
     * @dev Scaling precision of Euler's EVaults LTV (basis points)
     */
    uint256 private constant LTV_SCALE = 1e4;

    constructor(
        address _initialOwner,
        address __supplyToken,
        address __borrowToken,
        address _supplyVault,
        address _borrowVault,
        address _ethereumVaultConnector
    )
        EVCUtil(_ethereumVaultConnector)
        OrigamiElevatedAccess(_initialOwner)
    {
        if (__supplyToken == __borrowToken) revert CommonEventsAndErrors.InvalidAddress(__borrowToken);

        _supplyToken = IERC20(__supplyToken);
        _borrowToken = IERC20(__borrowToken);
        eulerEVC = IEVC(_ethereumVaultConnector);
        borrowVault = IEVault(_borrowVault);
        supplyVault = IEVault(_supplyVault);

        if (borrowVault.asset() != __borrowToken) revert CommonEventsAndErrors.InvalidAddress(_borrowVault);
        if (supplyVault.asset() != __supplyToken) revert CommonEventsAndErrors.InvalidAddress(_supplyVault);

        // Euler's EVC setup and vault approvals
        eulerEVC.enableController(address(this), _borrowVault);
        eulerEVC.enableCollateral(address(this), _supplyVault);

        bytes19 addressPrefix = eulerEVC.getAddressPrefix(address(this));

        // Lockdown mode restricts operations on the EVC, but not on the EVaults
        // As we don't plan to reconfigure this contract once deployed, we can lock it down from the start
        eulerEVC.setLockdownMode(addressPrefix, true);
        // We don't need Permit2 either, as allowances are handled here manually
        eulerEVC.setPermitDisabledMode(addressPrefix, true);

        // The only tokens that are expected to be held in this contract are
        // the surplus borrowTokens after the full-deleverage swap, or potential donations.
        // So these max approvals are not putting too many funds at risk.
        _supplyToken.forceApprove(_supplyVault, type(uint256).max);
        _borrowToken.forceApprove(_borrowVault, type(uint256).max);
    }

    /**
     * @dev Only the positionOwner or Elevated Access is allowed to call.
     */
    modifier onlyPositionOwnerOrElevated() {
        // The _msgSender() here is taken from the EVCUtils, which uses the EVC execution context.
        // If `msg.sender` is the EVC, _msgSender() returns the `onBehalfOf` account, which would be the original caller
        // Thus, if msg.sender==EVC and onBehalfOf!=ElevatedAccess or PossitionOwner the modifier should revert
        address sender = _msgSender();
        if (sender != address(positionOwner)) {
            if (!isElevatedAccess(sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        }
        _;
    }

    /**
     * @notice Set the position owner who can borrow/lend via this contract
     */
    function setPositionOwner(address account) external override onlyElevatedAccess {
        if (account == address(0)) revert CommonEventsAndErrors.InvalidAddress(account);

        positionOwner = account;
        emit PositionOwnerSet(account);
    }

    /**
     * @notice Set the swapper responsible for `borrowToken` <--> `supplyToken` swaps
     */
    function setSwapper(address _swapper) external override onlyElevatedAccess {
        if (_swapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(_swapper);
        // Update the approval's for both `supplyToken` and `borrowToken`
        address _oldSwapper = address(swapper);
        swapper = IOrigamiSwapper(_swapper);

        emit SwapperSet(_swapper);

        if (_oldSwapper != address(0)) {
            _supplyToken.forceApprove(_oldSwapper, 0);
            _borrowToken.forceApprove(_oldSwapper, 0);
        }
        // as mentioned in the constructor, this contract is not expected to hold supply/borrow tokens
        // so in case the swapper was compromised, there won't be too many funds at risk
        _supplyToken.forceApprove(_swapper, type(uint256).max);
        _borrowToken.forceApprove(_swapper, type(uint256).max);
    }

    /**
     * @notice Toggles whitelisting an operator to claim rewards, for a given Merkl distributor
     */
    function merklToggleOperator(address distributor, address operator) external override onlyElevatedAccess {
        IMerklDistributor(distributor).toggleOperator(address(this), operator);
    }

    /**
     * @notice Sets an address to receive Merkl rewards on behalf of this contract
     */
    function merklSetClaimRecipient(address distributor, address recipient, address token) external override onlyElevatedAccess {
        IMerklDistributor(distributor).setClaimRecipient(recipient, token);
    }

    /**
     * @notice Supply tokens as collateral. The `supplyAmount` must be in this contract's balance
     * @dev EVault: set `supplyAmount=type(uint256).max` to supply all balance in this contract.
     * @dev The amount supplied will match exactly `supplyAmount` (except for type(uint256).max), otherwise the EVault
     *      will revert
     */
    function supply(uint256 supplyAmount) external override onlyPositionOwnerOrElevated returns (uint256 supplied) {
        supplied = _supply(supplyAmount);
    }

    /**
     * @notice Withdraw collateral tokens to recipient
     * @dev Set `withdrawAmount = type(uint256).max` to withdraw the full balance
     */
    function withdraw(
        uint256 withdrawAmount,
        address recipient
    )
        external
        override
        onlyPositionOwnerOrElevated
        returns (uint256 amountWithdrawn)
    {
        amountWithdrawn = _withdraw(withdrawAmount, recipient);
    }

    /**
     * @notice Borrow tokens and send to recipient
     * @dev EVault: set `borrowAmount=type(uint256).max` to borrow the max available amount.
     * @dev The amount borrowed will match exactly `borrowAmount` (except for type(uint256).max), otherwise the EVault
     * reverts
     */
    function borrow(
        uint256 borrowAmount,
        address recipient
    )
        external
        override
        onlyPositionOwnerOrElevated
        returns (uint256 borrowedAmount)
    {
        borrowedAmount = _borrow(borrowAmount, recipient);
    }

    /**
     * @notice Repay debt.
     * @dev If repayAmount is higher than the outstanding debt, the repayAmount will be capped to that debt.
     * @dev As a consequence, type(uint256).max can also be used here to full-repay.
     */
    function repay(uint256 repayAmount)
        external
        override
        onlyPositionOwnerOrElevated
        returns (uint256 debtRepaidAmount)
    {
        debtRepaidAmount = _repay(repayAmount);
    }

    /**
     * @notice Repay debt and withdraw collateral in one step
     * @dev EVault: set `repayAmount=type(uint256).max` to repay the full outstanding debt.
     * @dev EVault: set `withdrawAmount=type(uint256).max` to withdraw max amount.
     * @dev If `repayAmount>debt & repayAmount!=type(uint256).max`, the EVault reverts with `E_RepayTooMuch()`
     */
    function repayAndWithdraw(
        uint256 repayAmount,
        uint256 withdrawAmount,
        address recipient
    )
        external
        override
        onlyPositionOwnerOrElevated
        returns (uint256 debtRepaidAmount, uint256 withdrawnAmount)
    {
        // first repay the debt, then withdraw the backing collateral
        debtRepaidAmount = _repay(repayAmount);
        withdrawnAmount = _withdraw(withdrawAmount, recipient);
    }

    /**
     * @notice Supply collateral and borrow in one step
     * @dev EVault: set `supplyAmount=type(uint256).max` to supply all balance in this contract.
     * @dev EVault: set `borrowAmount=type(uint256).max` to borrow the max available amount.
     * @dev The amount supplied will match exactly `supplyAmount` (except for type(uint256).max), otherwise EVault
     *      reverts
     * @dev The amount borrowed will match exactly `borrowAmount` (except for type(uint256).max), otherwise EVault
     *      reverts
     */
    function supplyAndBorrow(
        uint256 supplyAmount,
        uint256 borrowAmount,
        address recipient
    )
        external
        override
        onlyPositionOwnerOrElevated
        returns (uint256 suppliedAmount, uint256 borrowedAmount)
    {
        suppliedAmount = _supply(supplyAmount);
        borrowedAmount = _borrow(borrowAmount, recipient);
    }

    /**
     * @notice Increase the leverage of the existing position, by supplying `supplyToken` as collateral
     *         and borrowing `borrowToken` and swapping that back to `supplyToken`
     * @dev borrowAmount=type(uint256).max is not supported
     * @dev No need for surplus threshold to trigger an extra deposit, as all swapped is deposited.
     * @dev Any Protocol invariants that must be held after this function (A/L ratio) must be checked on the caller
     *      contract (posOwner)
     * @dev `supplyCollateralSurplusThreshold` not unused but it's here to comply with IOrigamiBorrowAndLendWithLeverage
     */
    function increaseLeverage(
        uint256 minSupplyAmount,
        uint256 borrowAmount,
        bytes memory swapData,
        uint256 /*supplyCollateralSurplusThreshold*/
    )
        external
        override
        callThroughEVC
        onlyPositionOwnerOrElevated
        returns (uint256 collateralSupplied)
    {
        // max borrow and max supply are allowed in the individual functions (borrow() and supply())
        // but not here because of the implications on slippage checks
        if (borrowAmount == type(uint256).max) revert MaxBorrowNotSupported();

        uint256 borrowed = _borrow(borrowAmount, address(this));

        // Swaps the borrowed tokens for the supply token.
        // Using `borrowed` for the swap, means we are not actively depositing donations here.
        // They can be deposited manually, though.
        uint256 collateralSwapped = swapper.execute(_borrowToken, borrowed, _supplyToken, swapData);
        if (collateralSwapped < minSupplyAmount) {
            revert CommonEventsAndErrors.Slippage(minSupplyAmount, collateralSwapped);
        }

        // supplies the collateral received (which might be higher than `minSupplyAmount`)
        // Once the slippage is checked, we can use type(uint256).max to deposit all collateral in this contract
        // including donations. This will affect the A/L ratio, but towards the safer side.
        // If we hit the supply cap, EVault will revert, so we should never go to the wrong side of the A.L ratio
        collateralSupplied = _supply(type(uint256).max);
    }

    /**
     * @notice Decrease the leverage of the existing position, by withdrawing `supplyToken` collateral,
     *         swapping it for `borrowToken` and then repaying debt (of `borrowToken`)
     * @dev For full deleverage, pass withdrawCollateralAmount=type(uint256).max, but still use
     *      `minBorrowTokensReceived` to act as slippage protection.
     * @dev if `withdrawCollateralAmount > suppliedBalance`, EVault will revert except for full withdraws
     * @dev `minBorrowTokensReceived` can be set higher than the outstanding debt;
     *      any surplus tokens after repaying all debt will stay in this contract until recovered
     * @dev Any Protocol invariants that must be held after this function (A/L ratio) must be checked on the caller
     * contract (posOwner)
     * @dev `repaySurplusThreshold` not unused but it's here to comply with IOrigamiBorrowAndLendWithLeverage
     */
    function decreaseLeverage(
        uint256 minBorrowTokensReceived,
        uint256 withdrawCollateralAmount,
        bytes memory swapData,
        uint256 /*repaySurplusThreshold*/
    )
        external
        override
        callThroughEVC
        onlyPositionOwnerOrElevated
        returns (uint256 debtRepaidAmount, uint256 surplusDebtRepaid)
    {
        // if withdrawCollateralAmount is type(unit256).max, it will perform a full withdraw
        uint256 withdrawn = _withdraw(withdrawCollateralAmount, address(this));

        // The amount of [borrowToken] received after swapping from [supplyToken]
        // needs to at least cover the minBorrowTokensReceived
        // Here we only swap `withdrawn` instead of balanceOf(this) to avoid the effect of donations
        // that could impact the size of the swap - since it needs to align with the offchain `swapData` quote.
        // In full deleverage, it is possible that a small surplus of borrowTokens stay in this contract which
        // can be recovered manually and supplied back in as collateral.
        uint256 borrowTokensReceived = swapper.execute(_supplyToken, withdrawn, _borrowToken, swapData);
        if (borrowTokensReceived < minBorrowTokensReceived) {
            revert CommonEventsAndErrors.Slippage(minBorrowTokensReceived, borrowTokensReceived);
        }

        // Within _repay(), if (borrowTokensReceived > outstanding debt), only outstanding debt is repaid
        debtRepaidAmount = _repay(borrowTokensReceived);
        surplusDebtRepaid = 0; // Always zero since Euler has no surplus
    }

    /**
     * @notice Recover accidental donations.
     * @dev Will revert when attempting to recover shares of either the collateral or borrow EVaults
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        // This contract is expected to hold shares of the supplyVault and borrowVault, that should not be recoverable
        if ((token == address(supplyVault) || (token == address(borrowVault)))) {
            revert CommonEventsAndErrors.InvalidToken(token);
        }
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice The token supplied as collateral
     */
    function supplyToken() public view override returns (address) {
        return address(_supplyToken);
    }

    /**
     * @notice The token which is borrowed
     */
    function borrowToken() public view override returns (address) {
        return address(_borrowToken);
    }

    /**
     * @notice The current balance of tokens in the Collateral EVault.
     * @dev It also includes any accrued interest, as that forms part of the redeemable shares
     * @dev previewRedeem includes also withdraw fees from the Vault if any, so it is more accurate than
     *      convertToAssets.
     *      previewRedeem rounds down, so it is possible that the suppliedBalance right after deposit returns a slighly
     *      lower than the deposited amount
     * @return The amount of supplyToken that can be withdrawn from the supplyVault, including interest
     */
    function suppliedBalance() public view override returns (uint256) {
        return supplyVault.previewRedeem(supplyVault.balanceOf(address(this)));
    }

    /**
     * @notice The current debt balance of tokens borrowed
     * @dev The output also includes any accrued interest, as it is part of the debt that has to be repaid
     */
    function debtBalance() public view override returns (uint256) {
        return borrowVault.debtOf(address(this));
    }

    /**
     * @notice Whether a given Assets/Liabilities Ratio is safe, given the upstream
     *         money market parameters
     * @param alRatio The Assets/Liabilities Ratio to check expressed with 18 dps
     */
    function isSafeAlRatio(uint256 alRatio) external view override returns (bool) {
        // The EulerV2 system has a borrow LTV that is less or equal than the liquidation LTV, (safety margin)
        // This call returns Borrowing LTV for a given collateral, in 1e4 scale
        uint16 eulerBorrowLtvLimit = borrowVault.LTVBorrow(address(supplyVault));

        // In order to make the eulerBorrowLimit (4 dps) comparable to the alRatio (18 dps)
        // we need to multiply the eulerBorrowLimit by the LTV_SCALE (= 1e22)

        // the lower the alRatio, the more risky the position (assets/liabilities)
        // upwards rounding here makes the threshold to consider a safe ALratio more strict
        uint256 borrowLtvInALratioTerms = LTV_SCALE.mulDiv(
            1e18, // Origami's ALratio scale
            eulerBorrowLtvLimit, // denominator
            OrigamiMath.Rounding.ROUND_UP
        );

        // Moreover, we use strict ">" instead of ">=" to make it even safer
        return alRatio > borrowLtvInALratioTerms;
    }

    /**
     * @notice How many `supplyToken` are available to withdraw from collateral,
     *         assuming this contract has already fully paid down its debt.
     * @dev Since suppliedBalance rounds down, the output from this function right after
     *      a deposit may look slightly smaller (by 1 wei)
     * @dev availableToWithdraw() is the portion of suppliedBalance() that can be withdrawn, given for
     *      any potential withdraw limits by the EVault, like the cash available in the vault.
     */
    function availableToWithdraw() external view override returns (uint256) {
        // Assuming that we have paid our debt in full,
        // The supplied balance gives us the assets that would we would be entitled to withdraw
        // However, as the vaults are not siloed markets, we have to compare it to the cash available in the vault
        uint256 entitledToWithdraw = suppliedBalance();
        uint256 cashAvailable = supplyVault.cash();
        return (entitledToWithdraw < cashAvailable) ? entitledToWithdraw : cashAvailable;
    }

    /**
     * @notice How much more capacity is available to supply
     */
    function availableToSupply() external view override returns (uint256 supplyCap, uint256 available) {
        // The outputs from caps() are in Euler's `AmountCap` fromat
        // (16-bit decimal floating point values: 10 bits mantissa, 6 bits exponent)
        (uint16 _supplyCap,) = supplyVault.caps();

        // AmountCap can be unwrapped into uint256 with AmountCapLib.resolve()
        // If the output is 0 (no cap set), the `resolve()` function converts it to type(uint256).max
        // to represent "no-cap".
        supplyCap = AmountCap.wrap(_supplyCap).resolve();
        available = supplyVault.maxDeposit(address(this));
    }

    /**
     * @notice How many `borrowToken` are available to borrow from the borrowVault
     */
    function availableToBorrow() external view override returns (uint256) {
        (, uint16 _borrowCap) = borrowVault.caps();
        uint256 borrowCap = AmountCap.wrap(_borrowCap).resolve();

        // cash() is the vault total holdings of `asset` (borrowToken)
        uint256 vaultCash = borrowVault.cash();

        return (borrowCap < vaultCash) ? borrowCap : vaultCash;
    }

    /**
     * @notice Returns the curent Euler position data
     */
    function debtAccountData()
        external
        view
        override
        returns (
            uint256 supplied, // in supplyToken
            uint256 borrowed, // in borrowToken
            uint256 collateralValueInUnitOfAcct,
            uint256 liabilityValueInUnitOfAcct,
            uint256 currentLtv, // 1e4 scale
            uint256 liquidationLtv, // 1e4 scale
            uint256 healthFactor
        )
    {
        // `supplied` includes the interest earned on the supplied balance (expressed in supplyToken decimals)
        supplied = suppliedBalance();
        // `borrowed` includes the interest (expressed in borrowToken decimals)
        borrowed = debtBalance();
        // `liquidationLtv` in basis points. example: 9500 = 95%
        liquidationLtv = borrowVault.LTVLiquidation(address(supplyVault));

        // From Euler's IEVault.accountLiquidity():
        // `collateralValue`: Total risk adjusted value of all collaterals in unit of account
        // `liabilityValue`: Value of debt in unit of account (no adjustments)
        // Risk adjustment always decreases the collateral value by the liquidation margin
        // Example: for a deposit worth 10k USD, and a liquidationLTV of 95%, the riskAdjustedCollateralValue would be
        // 9.5k
        // Read more about the risk adjustment in the Euler docs:
        //      https://github.com/euler-xyz/euler-vault-kit/blob/master/docs/whitepaper.md#risk-adjustment
        // `liquidation=true` parameter in accountLiquidity to flag liquidation vs account status
        (uint256 _riskAdjustedCollateralValueInUnitOfAcct, uint256 _liabilityValueInUnitOfAcct) =
            borrowVault.accountLiquidity(address(this), true);

        // liabilities are not risk-adjusted, so we can return them directly
        liabilityValueInUnitOfAcct = _liabilityValueInUnitOfAcct;

        // Undo the risk adjustment to get the actual collateral value
        // riskAdjustedCollateral = collateral * liquidationLTV
        // collateral = riskAdjustedCollateral / liquidationLTV
        // round down to underestimate collateral (more conservative).
        // liquidationLtv would rarely be 0, but just in case.
        collateralValueInUnitOfAcct = (liquidationLtv == 0)
            ? 0
            : _riskAdjustedCollateralValueInUnitOfAcct.mulDiv(LTV_SCALE, liquidationLtv, OrigamiMath.Rounding.ROUND_DOWN);

        // current account LTV (following Aave's standard). Round up to overestimate LTV (more conservative)
        currentLtv = (collateralValueInUnitOfAcct == 0)
            ? 0
            : liabilityValueInUnitOfAcct.mulDiv(LTV_SCALE, collateralValueInUnitOfAcct, OrigamiMath.Rounding.ROUND_UP);

        // health factor following aave's standards (HF >> 1 is safe). Round down to underestimate the HF (conservative)
        healthFactor = (currentLtv == 0)
            ? type(uint256).max
            : liquidationLtv.mulDiv(1e18, currentLtv, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @dev IEVault supports type(uint256).max, to deposit all assets held by the depositor (this contract in this
    /// case)
    /// @dev IERC4626 reverts if supplyAmount cannot be deposited (if the assets are not held by this contract)
    /// @dev IEVault also reverts if mintedShares == 0
    function _supply(uint256 supplyAmount) internal returns (uint256 suppliedAmount) {
        // when supplyAmount is type(uint256).max, the EVault will attempt to deposit all assets held by the
        // depositor and will revert if hitting the vault's supply cap
        // This is preferred over supplying up to the cap, as it can affect the A/L ratio negatively
        uint256 shares = supplyVault.deposit(supplyAmount, address(this));
        // depositedAmount is considered by the manager as `newReservesAmount`,
        // which is then used to calculate the lovToken shares minted to the depositor
        // The following line accounts for rounding errors and potential future deposit fees
        // in euler vaults
        suppliedAmount = supplyVault.previewRedeem(shares);
    }

    /// @dev IEVault does not support type(uint256).max for withdrawals,
    ///      so for max withdrawals we use redeem, with type(uint256).max
    /// @dev if withdrawAmount > supplied balance, IEVault will revert
    function _withdraw(uint256 withdrawAmount, address recipient) internal returns (uint256 amountWithdrawn) {
        if (withdrawAmount == type(uint256).max) {
            amountWithdrawn = supplyVault.redeem(type(uint256).max, recipient, address(this));
        } else {
            // the output of withdraw is the shares burned, not the assets withdrawn
            // euler will revert if amountWithdraw != withdrawAmount (except for type(uint256).max, which is handled
            // separately above)
            supplyVault.withdraw(withdrawAmount, recipient, address(this));
            amountWithdrawn = withdrawAmount;
        }
    }

    /// @dev IEVault supports type(uint256).max to borrow the max available amount (vault.cash())
    /// @dev IEVault If not in max-borrow mode, assetsBorrowed==borrowAmount. If not enough cash in vault, it reverts
    function _borrow(uint256 borrowAmount, address recipient) internal returns (uint256 assetsBorrowed) {
        assetsBorrowed = borrowVault.borrow(borrowAmount, recipient);
    }

    /// @dev IEVault: supports type(uint256).max, to repay the outstandingDebt in full
    function _repay(uint256 repayAmount) internal returns (uint256 debtRepaidAmount) {
        // IEVault reverts with `E_RepayTooMuch()` if attempting to repay more than outstandingDebt (except with
        // type(uint256).max), so we need to handle here manually the case when (repayAmount > outstandingDebt)
        uint256 outstandingDebt = debtBalance();
        uint256 toRepay = (repayAmount < outstandingDebt) ? repayAmount : type(uint256).max;

        debtRepaidAmount = borrowVault.repay(toRepay, address(this));
    }
}
