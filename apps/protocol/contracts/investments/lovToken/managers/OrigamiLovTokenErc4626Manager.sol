pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

/**
 * @title Origami lovToken Manager for ERC-4626
 * @notice A lovToken which has reserves as ERC-4626 tokens.
 * This will rebalance by borrowing funds from the Origami Lending Clerk, 
 * and swapping to the origami deposit tokens using a DEX Aggregator.
 * @dev `depositAsset` and `reserveToken` are required to be exactly 18 decimal places (if this changes, a new version will be created)
 * `debtAsset` can be any decimal places <= 18
 */
contract OrigamiLovTokenErc4626Manager is IOrigamiLovTokenErc4626Manager, OrigamiAbstractLovTokenManager {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC4626;
    using OrigamiMath for uint256;

    /**
     * @notice The asset which users deposit/exit with into the lovToken
     */
    IERC20Metadata public immutable override depositAsset;

    /**
     * @notice The asset which lovToken borrows to increase the A/L ratio
     */
    IERC20Metadata private immutable _debtAsset;

    /**
     * @notice The ERC-4626 reserves that this lovToken levers up on
     * @dev This is the reserve token for lovToken when calculating the reservesPerShare
     */
    IERC4626 private immutable _reserveToken;

    /**
     * @notice The number of reserves this lovToken holds.
     * @dev Explicitly tracked rather than via using the reserveToken.balanceOf() 
     * to avoid donation/inflation vectors.
     */
    uint256 private _internalReservesBalance;

    /**
     * @notice The Origami Lending Clerk responsible for managing borrows, repays and debt of borrowers
     */
    IOrigamiLendingClerk public override lendingClerk;

    /**
     * @notice The swapper for `debtAsset` <--> `depositAsset`
     */
    IOrigamiSwapper public override swapper;

    /**
     * @notice The oracle to convert `debtAsset` <--> `depositAsset`
     */
    IOrigamiOracle public debtAssetToDepositAssetOracle;

    /**
     * @notice A human readable name for the borrower
     */
    string public override name;

    /**
     * @notice Track the deployed version of this contract. 
     */
    string public constant override version = "1.0.0";

    constructor(
        address _initialOwner,
        address _depositAsset,
        address _debtAsset_,
        address _reserveToken_,
        address _lovToken
    ) OrigamiAbstractLovTokenManager(_initialOwner, _lovToken) {
        depositAsset = IERC20Metadata(_depositAsset);
        _debtAsset = IERC20Metadata(_debtAsset_);
        _reserveToken = IERC4626(_reserveToken_);
        name = IERC20Metadata(_lovToken).symbol();
    }

    /**
     * @notice Set the clerk responsible for managing borrows, repays and debt of borrowers
     */
    function setLendingClerk(address _lendingClerk) external override onlyElevatedAccess {
        if (_lendingClerk == address(0)) revert CommonEventsAndErrors.InvalidAddress(_lendingClerk);

        // Update the approval's
        address _oldClerk = address(lendingClerk);
        if (_oldClerk != address(0)) {
            _debtAsset.forceApprove(_oldClerk, 0);
        }
        _debtAsset.forceApprove(_lendingClerk, MAX_TOKEN_AMOUNT);

        emit LendingClerkSet(_lendingClerk);
        lendingClerk = IOrigamiLendingClerk(_lendingClerk);
    }

    /**
     * @notice Set the swapper responsible for `depositAsset` <--> `debtAsset` swaps
     */
    function setSwapper(address _swapper) external override onlyElevatedAccess {
        if (_swapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(_swapper);

        // Remove approvals from the old swapper
        address _oldSwapper = address(swapper);
        if (_oldSwapper != address(0)) {
            depositAsset.forceApprove(_oldSwapper, 0);
            _debtAsset.forceApprove(_oldSwapper, 0);
        }

        // Add approvals to the new swapper
        depositAsset.forceApprove(_swapper, MAX_TOKEN_AMOUNT);
        _debtAsset.forceApprove(_swapper, MAX_TOKEN_AMOUNT);

        emit SwapperSet(_swapper);
        swapper = IOrigamiSwapper(_swapper);
    }

    /**
     * @notice Set the `depositAsset` <--> `debtAsset` oracle configuration 
     */
    function setOracle(address oracle) external override onlyElevatedAccess {
        if (oracle == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        IOrigamiOracle _debtAssetToDepositAssetOracle = IOrigamiOracle(oracle);

        // Validate the assets on the oracle match what this lovToken needs
        if (!_debtAssetToDepositAssetOracle.matchAssets(address(_debtAsset), address(depositAsset))) {
            revert CommonEventsAndErrors.InvalidParam();
        }

        debtAssetToDepositAssetOracle = _debtAssetToDepositAssetOracle;
        emit OracleSet(oracle);
    }

    /**
     * @notice Increase the A/L by reducing liabilities. Exit some of the reserves and repay the debt
     */
    function rebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {
        alRatioAfter = _rebalanceUp(params, false);
    }

    /**
     * @notice Force a rebalanceUp ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {
        alRatioAfter = _rebalanceUp(params, true);
    }

    /**
     * @notice Decrease the A/L by increasing liabilities. Borrow new `debtAsset` and deposit into the reserves
     */
    function rebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {
        alRatioAfter = _rebalanceDown(params, false);
    }
    
    /**
     * @notice Force a rebalanceDown ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess returns (uint128 alRatioAfter) {
        alRatioAfter = _rebalanceDown(params, true);
    }

    /**
     * @notice Recover accidental donations. `reserveToken` can only be recovered for amounts greater than the 
     * internally tracked balance.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        // If the token to recover is the reserve token, can only remove any *surplus* reserves (ie donation reserves).
        // It can't dip into the actual user added reserves. 
        if (token == address(_reserveToken)) {
            uint256 bal = _reserveToken.balanceOf(address(this));
            if (amount > (bal - _internalReservesBalance)) revert CommonEventsAndErrors.InvalidAmount(token, amount);
        }

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20Metadata(token).safeTransfer(to, amount);
    }

    /**
     * @notice The total balance of reserve tokens this lovToken holds, and also if deployed as collateral
     * in other platforms
     * @dev Explicitly tracked rather than via reserveToken.balanceOf() to avoid donation/inflation vectors.
     * All internally held tokens for the ERC-4626 implementation.
     */
    function reservesBalance() public override(OrigamiAbstractLovTokenManager,IOrigamiLovTokenManager) view returns (uint256) {
        return _internalReservesBalance;
    }

    /**
     * @notice The underlying token this investment wraps.
     * In this case, it's the ERC-4626 `reserveToken`
     */
    function baseToken() external override view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The set of accepted tokens which can be used to invest. 
     * Either the ERC-4626 `reserveToken` or the underlying `depositAsset`
     */
    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](2);
        (tokens[0], tokens[1]) = (address(depositAsset), address(_reserveToken));
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     * Either the ERC-4626 `reserveToken` or the underlying `depositAsset`
     */
    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](2);
        (tokens[0], tokens[1]) = (address(depositAsset), address(_reserveToken));
    }

    /**
     * @notice The reserveToken that the lovToken levers up on
     */
    function reserveToken() public override(OrigamiAbstractLovTokenManager,IOrigamiLovTokenManager) view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The token which lovToken borrows to increase the A/L ratio
     */
    function debtToken() external override view returns (address) {
        return address(_debtAsset);
    }

    /**
     * @notice The debt of the lovToken to the Origami `lendingClerk`, converted into the `reserveToken`
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function liabilities(IOrigamiOracle.PriceType debtPriceType) public override(OrigamiAbstractLovTokenManager,IOrigamiLovTokenManager) view returns (uint256) {
        // In [debtAsset] terms - eg iUSDC or iUSDT, always 18 decimal places
        uint256 debt = lendingClerk.borrowerDebt(address(this));
        if (debt == 0) return 0;

        uint256 debtInDepositAsset = debtAssetToDepositAssetOracle.convertAmount(
            address(_debtAsset),
            debt,
            debtPriceType, 
            OrigamiMath.Rounding.ROUND_UP
        );

        // Calculate the number of shares this debt equates to if withdrawn from the reserves.
        // This will round up.
        return _reserveToken.previewWithdraw(debtInDepositAsset);
    }

    /**
     * @notice Checkpoint the underlying idle strategy to get the latest balance.
     * If no checkpoint is required (eg AToken in aave doesn't need this) then
     * calling this will be identical to just calling `latestAssetBalances()`
     */
    function checkpointAssetBalances() external virtual override returns (
        IOrigamiLendingBorrower.AssetBalance[] memory assetBalances
    ) {
        return latestAssetBalances();
    }

    /**
     * @notice The latest checkpoint of each asset balance this borrower holds.
     *
     * @dev The asset value may be stale at any point in time, depending on the borrower. 
     * It may optionally implement `checkpointAssetBalances()` in order to update those balances.
     */
    function latestAssetBalances() public virtual override view returns (IOrigamiLendingBorrower.AssetBalance[] memory assetBalances) {
        assetBalances = new IOrigamiLendingBorrower.AssetBalance[](1);
        assetBalances[0] = IOrigamiLendingBorrower.AssetBalance(reserveToken(), _internalReservesBalance);
    }

    /**
     * @notice The current deposit fee based on market conditions.
     * Deposit fees are applied to the portion of lovToken shares the depositor 
     * would have received. Instead that fee portion isn't minted (benefiting remaining users)
     * @dev represented in basis points
     */
    function _dynamicDepositFeeBps() internal override view returns (uint256) {
        return DynamicFees.dynamicFeeBps(
            DynamicFees.FeeType.DEPOSIT_FEE,
            debtAssetToDepositAssetOracle,
            address(depositAsset),
            _minDepositFeeBps,
            _feeLeverageFactor
        );
    }

    /**
     * @notice The current exit fee based on market conditions.
     * Exit fees are applied to the lovToken shares the user is exiting. 
     * That portion is burned prior to being redeemed (benefiting remaining users)
     * @dev represented in basis points
     */
    function _dynamicExitFeeBps() internal override view returns (uint256) {
        return DynamicFees.dynamicFeeBps(
            DynamicFees.FeeType.EXIT_FEE,
            debtAssetToDepositAssetOracle,
            address(depositAsset),
            _minExitFeeBps,
            _feeLeverageFactor
        );
    }

    function _rebalanceUp(RebalanceUpParams calldata params, bool force) private returns (uint128 alRatioAfter) {
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is higher after the rebalance
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);
        uint256 _reservesAmount = cache.assets;

        // Withdraw `depositAsset` from the ERC4626 `reserveToken`
        // With ERC-4626, the exact amount of depositAsset can be specified (so we get the exact amount), but then
        // slippage needs to be checked on both the amount of shares actually withdrawn and
        // also on the swap to debtAsset below
        uint256 reserveAssetSharesWithdrawn = _reserveToken.withdraw(params.depositAssetsToWithdraw, address(this), address(this));
        if (reserveAssetSharesWithdrawn < params.minReserveAssetShares) {
            revert CommonEventsAndErrors.Slippage(params.minReserveAssetShares, reserveAssetSharesWithdrawn);
        }
        if (reserveAssetSharesWithdrawn > _reservesAmount) {
            revert CommonEventsAndErrors.InsufficientBalance(address(_reserveToken), reserveAssetSharesWithdrawn, _reservesAmount);
        }

        // Swap from the `depositAsset` to the `debtAsset`, based on the quotes obtained off chain (for the exact amount of depositAssetsToWithdraw)
        uint256 debtAmountToRepay = swapper.execute(depositAsset, params.depositAssetsToWithdraw, _debtAsset, params.swapData);
        if (debtAmountToRepay < params.minDebtAmountToRepay) {
            revert CommonEventsAndErrors.Slippage(params.minDebtAmountToRepay, debtAmountToRepay);
        }

        // Repay the debt. It will be capped to the amount actually owing
        uint256 amountRepaid = lendingClerk.repay(debtAmountToRepay, address(this));

        // Update the amount of reserves
        // unchecked is fine because it's verified above
        unchecked {
            _internalReservesBalance = _reservesAmount - reserveAssetSharesWithdrawn;
        }

        // Validate that the new A/L is still within the `rebalanceALRange` and expected slippage range
        alRatioAfter = _validateAfterRebalance(
            cache, 
            alRatioBefore, 
            params.minNewAL, 
            params.maxNewAL, 
            AlValidationMode.HIGHER_THAN_BEFORE, 
            force
        );

        emit Rebalance(
            -int256(reserveAssetSharesWithdrawn),
            -int256(amountRepaid),
            alRatioBefore,
            alRatioAfter
        );
    }

    function _rebalanceDown(RebalanceDownParams calldata params, bool force) private returns (uint128 alRatioAfter) {
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is lower after the rebalance
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);
        uint256 _reservesAmount = _internalReservesBalance;

        // Borrow the `debtAsset`. This will get the exact amount requested or revert
        lendingClerk.borrow(params.borrowAmount, address(this));

        // Swap the `debtAsset` to the `depositAsset` based on the quotes obtained off chain
        uint256 depositAssetReceived = swapper.execute(_debtAsset, params.borrowAmount, depositAsset, params.swapData);

        // Can optimistically use the entire amount of depositAsset received from doing the swap,
        // as it will give at least, if not more the minReservesOut.
        depositAsset.safeIncreaseAllowance(address(_reserveToken), depositAssetReceived);
        uint256 reserveTokensReceived = _reserveToken.deposit(depositAssetReceived, address(this));
        if (reserveTokensReceived < params.minReservesOut) {
            revert CommonEventsAndErrors.Slippage(params.minReservesOut, reserveTokensReceived);
        }

        // Update the amount of reserves
        _internalReservesBalance = _reservesAmount + reserveTokensReceived;
        
        // Validate that the new A/L is still within the `rebalanceALRange`       
        alRatioAfter = _validateAfterRebalance(
            cache, 
            alRatioBefore, 
            params.minNewAL, 
            params.maxNewAL, 
            AlValidationMode.LOWER_THAN_BEFORE, 
            force
        );

        emit Rebalance(
            int256(reserveTokensReceived),
            int256(params.borrowAmount),
            alRatioBefore,
            alRatioAfter
        );
    }

    /**
     * @notice Deposit a number of `fromToken` into the `reserveToken`
     * A ERC-4626 based lovToken either accepts the `depositAsset` (and deposits into the ERC-4626 vault), or the existing ERC-4626 shares
     */
    function _depositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override returns (uint256 newReservesAmount) {
        if (fromToken == address(depositAsset)) {
            // Use the `fromToken` to deposit in the underlying and receive `reserveToken`
            // No need to check for slippage on this, as it's done based on the total lovToken's received.
            depositAsset.safeIncreaseAllowance(address(_reserveToken), fromTokenAmount);
            newReservesAmount = _reserveToken.deposit(fromTokenAmount, address(this));
        } else if (fromToken == address(_reserveToken)) {
            // If depositing with the reserve token, nothing else to do. 
            newReservesAmount = fromTokenAmount;
        } else {
            revert CommonEventsAndErrors.InvalidToken(fromToken);
        }

        // Increase the counter of reserves
        _internalReservesBalance = _internalReservesBalance + newReservesAmount;
    }

    /**
     * @notice Calculate the amount of `reserveToken` will be deposited given an amount of `fromToken`
     * A ERC-4626 based lovToken either accepts the `depositAsset` (and deposits into the ERC-4626 vault), or the existing ERC-4626 shares
     */
    function _previewDepositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override view returns (uint256 newReservesAmount) {
        if (fromToken == address(depositAsset)) {
            // Deposit into the ERC4626 first
            newReservesAmount = _reserveToken.previewDeposit(fromTokenAmount);
        } else if (fromToken == address(_reserveToken)) {
            // Just the existing ERC4626 token
            newReservesAmount = fromTokenAmount;
        }

        // Anything else returns 0
    }

    /**
     * @notice Maximum amount of `fromToken` that can be deposited into the `reserveToken`
     */
    function _maxDepositIntoReserves(address fromToken) internal override view returns (uint256 fromTokenAmount) {
        if (fromToken == address(depositAsset)) {
            fromTokenAmount = _reserveToken.maxDeposit(address(this));
        } else if (fromToken == address(_reserveToken)) {
            fromTokenAmount = MAX_TOKEN_AMOUNT;
        }

        // Anything else returns 0
    }

    /**
     * @notice Calculate the number of `toToken` required in order to mint a given number of `reserveTokens`
     */
    function _previewMintReserves(address toToken, uint256 reservesAmount) internal override view returns (uint256 newReservesAmount) {
        if (toToken == address(depositAsset)) {
            newReservesAmount = _reserveToken.previewMint(reservesAmount);
        } else if (toToken == address(_reserveToken)) {
            newReservesAmount = reservesAmount;
        }

        // Anything else returns 0
    }

    /**
     * @notice Redeem a number of `reserveToken` into `toToken`
     * A ERC-4626 based lovToken can exit to the ERC-4626 shares, or to the `depositAsset` by redeeming from the ERC-4626 vault
     */
    function _redeemFromReserves(uint256 reservesAmount, address toToken, address recipient) internal override returns (uint256 toTokenAmount) {
        // Now redeem the non-fee user lovToken's
        // If exiting to the reserve token, redeem and send them to the user
        // Otherwise first redeem the reserve tokens and then exit the underlying Origami investment
        if (toToken == address(depositAsset)) {
            toTokenAmount = _reserveToken.redeem(reservesAmount, recipient, address(this));
        } else if (toToken == address(_reserveToken)) {
            toTokenAmount = reservesAmount;
            _reserveToken.safeTransfer(recipient, reservesAmount);
        } else {
            revert CommonEventsAndErrors.InvalidToken(toToken);
        }

        // Decrease the counter of reserves
        _internalReservesBalance = _internalReservesBalance - reservesAmount;
    }

    /**
     * @notice Calculate the number of `toToken` recevied if redeeming a number of `reserveToken`
     */
    function _previewRedeemFromReserves(uint256 reservesAmount, address toToken) internal override view returns (uint256 toTokenAmount) {
        if (toToken == address(depositAsset)) {
            // Redeem from the ERC4626 first
            toTokenAmount = _reserveToken.previewRedeem(reservesAmount);
        } else if (toToken == address(_reserveToken)) {
            // Just the existing ERC4626 token
            toTokenAmount = reservesAmount;
        }

        // Anything else returns 0
    }

    /**
     * @notice Maximum amount of `reserveToken` that can be redeemed to `toToken`
     * For an ERC-4626 based lovToken, use the max redeemable from that vault
     */
    function _maxRedeemFromReserves(address toToken, Cache memory /*cache*/) internal override view returns (uint256 reservesAmount) {
        if (toToken == address(depositAsset)) {
            // The standard ERC-4626 implementation uses the balance of reserveToken's that this contract holds.
            // But could also constrain in other ways depending on the implementation
            uint256 _maxUnderlyingRedeem = _reserveToken.maxRedeem(address(this));

            // Use the min of the reserve balance and the underlying maxRedeem
            reservesAmount = _internalReservesBalance;
            if (_maxUnderlyingRedeem < reservesAmount) {
                reservesAmount = _maxUnderlyingRedeem;
            }
        } else if (toToken == address(_reserveToken)) {
            // Just use the current balance of reserveToken
            reservesAmount = _internalReservesBalance;
        }

        // Anything else returns 0
    }
}
