pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/olympus/OrigamiHOhmManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiHOhmManager } from "contracts/interfaces/investments/olympus/IOrigamiHOhmManager.sol";
import { IMonoCooler } from "contracts/interfaces/external/olympus/IMonoCooler.sol";
import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";

import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { OlympusCoolerDelegation } from "contracts/libraries/OlympusCoolerDelegation.sol";

/**
 * @title Origami lovOHM Manager
 * @notice Handles adding and removing collateral and max borrowing in Olympus' MonoCooler
 *
 * @dev
 *   - There will be a surplus `debtToken` amount held by this contract which can expand and contract
 *     on each join and exit. 
 *   - This surplus is excluded from the balance sheet totals used to calculate the `debtToken per hOHM` 
 *     share price.
 *   - Under normal circumstances it will grow on aggregate:
 *     a/ The origination LTV within cooler increases every second to some set gradient. 
 *        This increases the capacity to borrow
 *     b/ The cooler interest rate is flat (0.5% APY as of writing). 
 *        This decreases the capacity to borrow
 *     c/ Any surplus is added into a savings vault (eg sUSDS) which has a higher interest rate than (b). 
 *        The surplus in debtToken terms (eg USDS) increases faster than the cooler debt.
 *     It is expected that (a)+(c) will outpace (b)
 *   - sweep() can be called in order to use the surplus `debtToken` to buy hOHM from the open market
 *     and then burn the hOHM. 
 *     When this happens the totalSupply decreases, which increases the share price of both the collateral and 
 *     debt tokens per hOHM
 */
contract OrigamiHOhmManager is 
    IOrigamiHOhmManager,
    OrigamiElevatedAccess,
    OrigamiManagerPausable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for OrigamiHOhmVault;
    using SafeCast for uint256;
    using OrigamiMath for uint256;
    using OlympusCoolerDelegation for OlympusCoolerDelegation.Data;

    /// @dev The lovOhm vault
    OrigamiHOhmVault private immutable _vault;

    /// @inheritdoc IOrigamiHOhmManager
    IMonoCooler public immutable override cooler;

    /// @inheritdoc IOrigamiHOhmManager
    IERC20 public immutable override collateralToken;

    /// @inheritdoc IOrigamiHOhmManager
    IERC20 public override debtToken;

    /// @inheritdoc IOrigamiHOhmManager
    uint96 public override debtTokenDecimalsToWadScalar;

    /// @inheritdoc IOrigamiHOhmManager
    IERC4626 public override debtTokenSavingsVault;

    /// @inheritdoc IOrigamiHOhmManager
    uint16 public override exitFeeBps;

    /// @inheritdoc IOrigamiHOhmManager
    bool public override coolerBorrowsDisabled;

    /// @inheritdoc IOrigamiHOhmManager
    IOrigamiSwapper public override sweepSwapper;

    /// @inheritdoc IOrigamiHOhmManager
    uint96 public override maxSweepSellAmount;

    /// @inheritdoc IOrigamiHOhmManager
    uint40 public override sweepCooldownSecs;

    /// @inheritdoc IOrigamiHOhmManager
    uint40 public override lastSweepTime;

    /// @inheritdoc IOrigamiHOhmManager
    uint16 public override performanceFeeBps;

    /// @inheritdoc IOrigamiHOhmManager
    address public override feeCollector;

    /// @inheritdoc IOrigamiHOhmManager
    mapping(address account => OlympusCoolerDelegation.Data delegation) public override delegations;

    /// @inheritdoc IOrigamiHOhmManager
    uint16 public override constant MAX_EXIT_FEE_BPS = 330; // 3.3%

    /// @inheritdoc IOrigamiHOhmManager
    uint16 public constant override MAX_PERFORMANCE_FEE_BPS = 330; // 3.3%

    /// @inheritdoc IOrigamiHOhmManager
    uint256 public constant override MIN_DELEGATION_AMOUNT = 0.1e18; // gOHM collateral per account

    constructor(
        address initialOwner_,
        address vault_,
        address cooler_,
        address debtTokenSavingsVault_,
        uint16 performanceFeeBps_,
        address feeCollector_
    ) 
        OrigamiElevatedAccess(initialOwner_)
    {
        _vault = OrigamiHOhmVault(vault_);
        collateralToken = IERC20(_vault.collateralToken());
        cooler = IMonoCooler(cooler_);

        // Max approve the collateral token to cooler (to add collateral)
        collateralToken.safeApprove(address(cooler), type(uint256).max);

        // Set the state and max approvals for the cooler debtToken and savings (if set)
        _setDebtTokenAndSavings(cooler.debtToken(), IERC4626(debtTokenSavingsVault_));

        if (performanceFeeBps_ > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        performanceFeeBps = performanceFeeBps_;
        feeCollector = feeCollector_;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setExitFees(uint16 newFeeBps) external override onlyElevatedAccess {
        if (newFeeBps > MAX_EXIT_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();

        emit ExitFeeBpsSet(newFeeBps);
        exitFeeBps = newFeeBps;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setCoolerBorrowsDisabled(bool value) external override onlyElevatedAccess {
        coolerBorrowsDisabled = value;
        emit CoolerBorrowsDisabledSet(value);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setSweepParams(
        uint40 newSweepCooldownSecs,
        uint96 newMaxSweepSellAmount
    ) external override onlyElevatedAccess {
        sweepCooldownSecs = newSweepCooldownSecs;
        maxSweepSellAmount = newMaxSweepSellAmount;
        emit SweepParamsSet(newSweepCooldownSecs, newMaxSweepSellAmount);
    }
    
    /// @inheritdoc IOrigamiHOhmManager
    function setSweepSwapper(address newSwapper) external override onlyElevatedAccess {
        if (newSwapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(newSwapper);

        emit SwapperSet(newSwapper);
        sweepSwapper = IOrigamiSwapper(newSwapper);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setPerformanceFeesBps(uint16 newFeeBps) external override onlyElevatedAccess {
        /// @dev Cannot be raised higher than MAX_PERFORMANCE_FEE_BPS
        if (newFeeBps > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();

        emit PerformanceFeeSet(newFeeBps);
        performanceFeeBps = newFeeBps;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setFeeCollector(address newFeeCollector) external override onlyElevatedAccess {
        if (newFeeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(newFeeCollector);
        feeCollector = newFeeCollector;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setDebtTokenFromCooler(address newDebtTokenSavingsVault) external override onlyElevatedAccess {
        // Ensure the vault is paused first -- see the natspec for considerations.
        if (!_paused.investmentsPaused || !_paused.exitsPaused) revert IsNotPaused();

        // Remove approvals for the old debtToken and savings vault
        IERC20 _oldDebtToken = debtToken;
        address _oldDebtTokenSavingsVault = address(debtTokenSavingsVault);
        _oldDebtToken.safeApprove(address(cooler), 0);
        if (address(_oldDebtTokenSavingsVault) != address(0)) {
            _oldDebtToken.safeApprove(_oldDebtTokenSavingsVault, 0);
        }
    
        // Set the state and approvals for the new debt token and savings
        IERC20 _newDebtToken = cooler.debtToken();
        IERC4626 _newSavingsVault = IERC4626(newDebtTokenSavingsVault);
        _setDebtTokenAndSavings(_newDebtToken, _newSavingsVault);

        emit DebtTokenSet(address(_newDebtToken), address(_newSavingsVault));
    }

    /**
     * @notice Recover tokens accidentally sent here
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        // Collateral is added/removed from Cooler just in time. Any other collateral sent here by mistake can be recovered.
        // The current debt token surplus cannot be recovered, it can only be transferred by using `sweep()`
        if (token == address(debtToken) || token == address(debtTokenSavingsVault)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function syncDebtTokenSavings(uint256 requiredDebtTokenBalance) external override onlyElevatedAccess {
        _syncSavings(requiredDebtTokenBalance);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function sweep(
        uint256 amount,
        bytes memory swapData
    ) external override onlyElevatedAccess {
        if (amount > maxSweepSellAmount) revert SweepTooLarge();
        if (block.timestamp < lastSweepTime + sweepCooldownSecs) revert BeforeCooldownEnd();
        lastSweepTime = uint40(block.timestamp);

        // Send the debtTokens to the swapper
        IOrigamiSwapper _swapper = sweepSwapper;
        IERC4626 _savingsVault = debtTokenSavingsVault;
        IERC20 _debtToken = debtToken;
        IERC20 _sweepDebtToken = address(_savingsVault) == address(0)
            ? _debtToken
            : _savingsVault;

        _sweepDebtToken.safeTransfer(address(_swapper), amount);

        emit SweepStarted(address(_sweepDebtToken), amount);

        // This swap may be synchronous (eg via 1Inch/Kyberswap/0x), or asynchronous (eg CoW swap programmatic orders)
        // The swapper is responsible for checking slippage (minBuyAmount) and calling the permisionless `sweepCallback()`
        // after the swap has concluded. For CoW swap that may be via their hooks framework.
        _swapper.execute(_sweepDebtToken, amount, _vault, swapData);
    }

    /// @inheritdoc IOrigamiSwapCallback
    function swapCallback() external override {
        uint256 vaultBalance = _vault.balanceOf(address(this));
        (uint256 amountToBurn, uint256 feeAmount) = vaultBalance.splitSubtractBps(performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);

        // No correlation id between the SweepStarted and SweepFinished events since this can be
        // permissionlessly called anyway
        emit SweepFinished(amountToBurn, feeAmount);
        if (feeAmount > 0) {
            _vault.safeTransfer(feeCollector, feeAmount);
        }

        if (amountToBurn > 0) {
            _vault.burn(amountToBurn);
        }
    }

    /// @inheritdoc IOrigamiHOhmManager
    function join(
        uint256 collateralAmount,
        uint256 debtAmount,
        address receiver,
        uint256 receiverSharesPostMint,
        uint256 totalSupplyPostMint
    ) external override onlyVault {
        // Sync delegations to the latest proportional gOHM the will have after the join.
        // If it doesn't have a delegate set, there will be no delegation requests.
        IDLGTEv1.DelegationRequest[] memory delegationRequests = _delegationRequest(
            receiver,
            int256(collateralAmount),
            receiverSharesPostMint,
            totalSupplyPostMint
        );

        // Add the gOHM balance as collateral. The vault is trusted to have sent the exact amount first
        IDLGTEv1.DelegationRequest[] memory emptyDR;
        cooler.addCollateral(collateralAmount.encodeUInt128(), address(this), emptyDR);

        // Now apply the delegation requests
        // NB: This needs to be done as a separate step after addCollateral() because of the `MIN_DELEGATION_AMOUNT`
        // Otherwise MonoCooler could revert as it may try and delegate more than it's trying to add, if the 
        // delegation was previously floored at zero
        if (delegationRequests.length != 0) cooler.applyDelegations(delegationRequests, address(this));

        // borrow or repay such that this contract has a cooler LTV equal to the origination LTV
        int128 coolerDebtDeltaInWad = _coolerMaxBorrow(0, debtAmount);

        // Transfer the `debtToken` to the receiver
        debtToken.safeTransfer(receiver, debtAmount);

        emit Join(collateralAmount, debtAmount, receiver, coolerDebtDeltaInWad);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function exit(
        uint256 collateralAmount,
        uint256 debtAmount,
        address sharesOwner,
        address receiver,
        uint256 ownerSharesPostBurn,
        uint256 totalSupplyPostBurn
    ) external override onlyVault {
        // The vault is trusted to have sent the exact amount of debt first
        // borrow or repay such that this contract has a cooler LTV equal to the origination LTV
        uint128 collateralAmount128 = collateralAmount.encodeUInt128();
        int128 negCollateralAmount128 = -int128(collateralAmount128);
        int128 coolerDebtDeltaInWad = _coolerMaxBorrow(negCollateralAmount128, 0);

        // Sync delegations to the latest proportional gOHM the will have after the exit.
        {
            // If `sharesOwner` doesn't have a delegate set, there will be no delegation requests.
            IDLGTEv1.DelegationRequest[] memory delegationRequests = _delegationRequest(
                sharesOwner,
                negCollateralAmount128,
                ownerSharesPostBurn,
                totalSupplyPostBurn
            );

            // NB: This needs to be done as a separate step prior to withdrawCollateral() because of the `MIN_DELEGATION_AMOUNT`
            // Otherwise MonoCooler could revert as it may try and undelegate more than it's trying to withdraw in order to bring
            // the delegation to zero
            if (delegationRequests.length != 0) cooler.applyDelegations(delegationRequests, address(this));
        }

        IDLGTEv1.DelegationRequest[] memory emptyDR;
        cooler.withdrawCollateral(collateralAmount128, address(this), receiver, emptyDR);

        emit Exit(collateralAmount, debtAmount, receiver, coolerDebtDeltaInWad);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function updateDelegateAndAmount(
        address account, 
        uint256 accountShares, 
        uint256 totalSupply, 
        address newDelegateAddress
    ) external override onlyVault {
        _applyDelegations(
            delegations[account].updateDelegateAndAmount(
                account,
                newDelegateAddress,
                _convertSharesToCollateral(accountShares, collateralTokenBalance(), totalSupply, true)
            )
        );
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setDelegationAmount1(
        address account,
        uint256 accountShares,
        uint256 totalSupply
    ) external override onlyVault {
        _applyDelegations(
            delegations[account].syncAccountAmount(
                account,
                _convertSharesToCollateral(accountShares, collateralTokenBalance(), totalSupply, true)
            )
        );
    }

    /// @inheritdoc IOrigamiHOhmManager
    function setDelegationAmount2(
        address account1,
        uint256 account1Shares,
        address account2,
        uint256 account2Shares,
        uint256 totalSupply
    ) external override onlyVault {
        uint256 totalGOhm = collateralTokenBalance();

        _applyDelegations(
            OlympusCoolerDelegation.syncAccountAmount(
                delegations[account1],
                account1,
                _convertSharesToCollateral(account1Shares, totalGOhm, totalSupply, true),
                delegations[account2],
                account2,
                _convertSharesToCollateral(account2Shares, totalGOhm, totalSupply, true)
            )
        );
    }

    /// @inheritdoc IOrigamiHOhmManager
    function maxBorrowFromCooler() external override returns (int128 coolerDebtDeltaInWad) {
        return _coolerMaxBorrow(0, 0);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function vault() external override view returns (address) {
        return address(_vault);
    }

    /// @inheritdoc IOrigamiHOhmManager
    function areJoinsPaused() external virtual override view returns (bool) {
        return _paused.investmentsPaused;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function areExitsPaused() external virtual override view returns (bool) {
        return _paused.exitsPaused;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function debtTokenBalance() external override view returns (uint256) {
        // Convert the debt into the debt token units, rounding up
        uint256 _coolerDebtInDebtTokens = OrigamiMath.scaleDown(
            coolerDebtInWad(),
            debtTokenDecimalsToWadScalar,
            OrigamiMath.Rounding.ROUND_UP
        );
        uint256 _surplus = surplusDebtTokenAmount();

        // Since:
        //  - The cooler debt could be repaid by someone else
        //  - The surplus just trackes current token balances
        // Either is a donation which will change the [debtToken per hOHM] share price
        return _coolerDebtInDebtTokens > _surplus
            ? _coolerDebtInDebtTokens - _surplus
            : 0;
    }

    /// @inheritdoc IOrigamiHOhmManager
    function coolerDebtInWad() public override view returns (uint128) {
        return cooler.accountDebt(address(this));
    }

    /// @inheritdoc IOrigamiHOhmManager
    function surplusDebtTokenAmount() public override view returns (uint256 surplus) {
        IERC20 _debtToken = debtToken;
        IERC4626 _savingsVault = debtTokenSavingsVault;
        bool hasSavingsVault = address(_savingsVault) != address(0);
        address _sweepSwapper = address(sweepSwapper);
        bool hasSweepSwapper = address(_sweepSwapper) != address(0);

        // This contract's balance - may have either the savings vault or the debt token
        surplus = _debtToken.balanceOf(address(this));
        if (hasSavingsVault) {
            surplus += _uncappedSavingsVaultBalance(_savingsVault, address(this));
        }

        // The sweep swapper's balance
        // It may be asynchronous, and may also have a balance of either the savingsVault token or the debtToken
        if (hasSweepSwapper) {
            surplus += _debtToken.balanceOf(_sweepSwapper);
            if (hasSavingsVault) {
                surplus += _uncappedSavingsVaultBalance(_savingsVault, _sweepSwapper);
            }
        }
    }

    /// @inheritdoc IOrigamiHOhmManager
    function collateralTokenBalance() public override view returns (uint256) {
        // Donations are allowed - if someone adds collateral into cooler on this contracts behalf.
        // A donation will change the [collateral token per hOHM] share price
        return cooler.accountCollateral(address(this));
    }

    /// @inheritdoc IOrigamiHOhmManager
    function convertSharesToCollateral(
        uint256 shares,
        uint256 totalSupply
    ) public override view returns (uint256) {
        return _convertSharesToCollateral(
            shares,
            collateralTokenBalance(),
            totalSupply,
            false
        );
    }

    /// @inheritdoc IOrigamiHOhmManager
    function accountDelegationBalances(
        address account,
        uint256 shares,
        uint256 totalSupply
    ) external override view returns (
        uint256 totalCollateral,
        address delegateAddress,
        uint256 delegatedCollateral
    ) {
        totalCollateral = convertSharesToCollateral(shares, totalSupply);
        OlympusCoolerDelegation.Data memory delegation = delegations[account];
        (delegateAddress, delegatedCollateral) = (delegation.delegateAddress, delegation.amount);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override pure returns (bool) {
        return interfaceId == type(IOrigamiHOhmManager).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /// @dev Perform either a borrow or repayment in the cooler, in order to get the LTV
    /// as close to the cooler max Origination LTV as possible, given an amount of added/removed collateral
    /// and a required of raw debtTokens (not in the savings vault) to be available in this contract.
    /// 
    /// This will withdraw the required debtToken from the `debtTokenSavingsVault` if required.
    /// @param changeInCollateral The change in `collateralToken` to use when solving for the required change 
    ///        in debt to hit max origination LTV in cooler, in the native decimals of the collateralToken
    /// @param requiredDebtTokenAmount The amount of `debtToken` required to be available in the contract
    ///        after the cooler borrow or repay
    function _coolerMaxBorrow(
        int128 changeInCollateral, 
        uint256 requiredDebtTokenAmount
    ) private returns (int128 debtDeltaInWad) {
        // Calculate the change in debt (always 18dp regardless of the token) in order to get the LTV
        // to the max cooler origination LTV.
        debtDeltaInWad = cooler.debtDeltaForMaxOriginationLtv(address(this), changeInCollateral);
        if (debtDeltaInWad > 0) {
            if (coolerBorrowsDisabled) return 0;

            // A positive `debtDeltaInWad` means we have surplus which can be borrowed to the Origination LTV
            cooler.borrow(uint128(debtDeltaInWad), address(this), address(this));

            // Sync any surplus debtToken into savings, leaving the requiredDebtTokenAmount as raw debtTokens to send to the receiver
            _syncSavings(requiredDebtTokenAmount);
        } else if (debtDeltaInWad < 0) {
            // A negative `debtDeltaInWad` means we need to repay that amount to get to the Origination LTV

            // Sync any surplus debtToken into savings, ensuring there's raw debtToken amounts of
            // the requiredDebtTokenAmount to send the reciever + the amount we want to repay.
            // Convert `debtDeltaInWad` into the debt token decimals, rounding up to ensure there's enough
            uint128 repayAmountWad = uint128(-debtDeltaInWad);
            uint256 repayAmountNative = OrigamiMath.scaleDown(
                repayAmountWad,
                debtTokenDecimalsToWadScalar,
                OrigamiMath.Rounding.ROUND_UP
            );

            _syncSavings(requiredDebtTokenAmount + repayAmountNative);

            // And then repay
            // In the case where there is not enough debtToken to repay, this will (intentionally) revert.
            // The surplus is expected to always be growing/replenishing, if not it means Cooler interest rate is increasing
            // faster than the Olympus treasury, then Cooler no longer has product market fit.
            // Debt repayment will need to be funded from external sources for remaining users to exit.
            cooler.repay(repayAmountWad, address(this));
        }
    }

    function _syncSavings(uint256 requiredDebtTokenBalance) private {
        IERC4626 _savingsVault = debtTokenSavingsVault;
        if (address(_savingsVault) == address(0)) return;

        uint256 _debtTokenBalance = debtToken.balanceOf(address(this));
        uint256 delta;
        if (_debtTokenBalance > requiredDebtTokenBalance) {
            // deposit any surplus into savings
            unchecked {
                delta = _debtTokenBalance - requiredDebtTokenBalance;
            }
            uint256 maxDeposit = _savingsVault.maxDeposit(address(this));
            if (delta > maxDeposit) delta = maxDeposit;
            if (delta > 0) {
                _savingsVault.deposit(delta, address(this));
            }
        } else {
            // withdraw deficit from savings. Cap to the max amount which can be withdrawn.
            unchecked {
                delta = requiredDebtTokenBalance - _debtTokenBalance;
            }
            uint256 maxWithdraw = _savingsVault.maxWithdraw(address(this));
            if (delta > maxWithdraw) delta = maxWithdraw;
            if (delta > 0) {
                _savingsVault.withdraw(delta, address(this), address(this));
            }
        }
    }

    /// @dev The total delegated amount for this account should equal the proportional amount of gOHM collateral
    /// held on behalf of this account based on their share balance.
    function _convertSharesToCollateral(
        uint256 shares,
        uint256 totalCollateral,
        uint256 totalSupply,
        bool applyMinDelegationAmount
    ) private pure returns (uint256 collateral) {
        if (totalSupply == 0) return 0;
        if (shares > totalSupply) revert CommonEventsAndErrors.InvalidParam();
        collateral = totalCollateral.mulDiv(shares, totalSupply, OrigamiMath.Rounding.ROUND_DOWN);
        if (applyMinDelegationAmount && collateral < MIN_DELEGATION_AMOUNT) collateral = 0;
    }

    // @dev Set the debtToken and debtTokenSavingsVault, along with setting
    // max approvals for those.
    function _setDebtTokenAndSavings(
        IERC20 newDebtToken,
        IERC4626 newDebtTokenSavingsVault
    ) private {
        uint8 _decimals = IERC20Metadata(address(newDebtToken)).decimals();
        if (_decimals > OrigamiMath.WAD_DECIMALS) revert CommonEventsAndErrors.InvalidToken(address(newDebtToken));
        debtToken = newDebtToken;
        debtTokenDecimalsToWadScalar = uint96(10 ** (OrigamiMath.WAD_DECIMALS - _decimals));
        debtTokenSavingsVault = newDebtTokenSavingsVault;

        // Max approve the debt token to cooler (to repay)
        // And the debt token to the savings vault if set
        newDebtToken.safeApprove(address(cooler), type(uint256).max);
        if (address(newDebtTokenSavingsVault) != address(0)) {
            if (address(newDebtTokenSavingsVault.asset()) != address(newDebtToken)) {
                revert CommonEventsAndErrors.InvalidToken(address(newDebtTokenSavingsVault));
            }
            newDebtToken.safeApprove(address(newDebtTokenSavingsVault), type(uint256).max);
        }
    }

    /// @dev Use the entire balance rather maxRedeem, so this amount isn't capped by redemption limits
    function _uncappedSavingsVaultBalance(
        IERC4626 sVault, 
        address account
    ) private view returns (uint256 balance) {
        uint256 savingsSurplus = sVault.balanceOf(account);
        if (savingsSurplus > 0) {
            balance = sVault.previewRedeem(savingsSurplus);
        }
    }

    /// @dev Create a Cooler DelegationRequest if an account already has a delegate
    /// set. Uses the existing gOHM collateral balance plus the `_collateralDelta`,
    /// then calculates the user prorportional gOHM given the account shares and totalSupply
    function _delegationRequest(
        address account,
        int256 collateralDelta,
        uint256 newAccountShares,
        uint256 newTotalSupply
    ) private returns (IDLGTEv1.DelegationRequest[] memory delegationRequests) {
        OlympusCoolerDelegation.Data storage $delegation = delegations[account];
        if ($delegation.delegateAddress != address(0)) {
            int256 newTotalCollateral = int256(collateralTokenBalance()) + collateralDelta;

            // An underflow shouldn't be possible, as it would fail later when withdrawing collateral
            // (can't withdraw more than the supplied collateral)
            // But added here as insurance, for safer int256=>uint256 casting
            if (newTotalCollateral < 0) revert CommonEventsAndErrors.InvalidParam();

            delegationRequests = $delegation.syncAccountAmount(
                account,
                _convertSharesToCollateral(
                    newAccountShares,
                    uint256(newTotalCollateral),
                    newTotalSupply,
                    true
                )
            );
        }

        // else left uninitialized
    }

    function _applyDelegations(IDLGTEv1.DelegationRequest[] memory requests) private {
        if (requests.length > 0) {
            cooler.applyDelegations(requests, address(this));
        }
    }
    
    modifier onlyVault() {
        if (msg.sender != address(_vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}