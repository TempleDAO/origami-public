pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiMorphoBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiMorphoBorrowAndLend.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Range } from "contracts/libraries/Range.sol";
import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

/**
 * @title Origami LovToken Manager, for use with Morpho markets
 * @notice The `reserveToken` is deposited by users and supplied into Morpho as collateral
 * Upon a rebalanceDown (to decrease the A/L), the position is levered up
 */
contract OrigamiLovTokenMorphoManager is IOrigamiLovTokenMorphoManager, OrigamiAbstractLovTokenManager {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /**
     * @notice reserveToken that this lovToken levers up on
     * This is also the asset which users deposit/exit with in this lovToken manager
     */
    IERC20 private immutable _reserveToken;

    /**
     * @notice The asset which lovToken borrows from the money market to increase the A/L ratio
     */
    IERC20 private immutable _debtToken;

    /**
     * @notice The base asset used when retrieving the prices for dynamic fee calculations.
     */
    address public immutable override dynamicFeeOracleBaseToken;

    /**
     * @notice The contract responsible for borrow/lend via external markets
     */
    IOrigamiMorphoBorrowAndLend public override borrowLend;

    /**
     * @notice The oracle to convert `debtToken` <--> `reserveToken`
     */
    IOrigamiOracle public override debtTokenToReserveTokenOracle;

    /**
     * @notice The oracle to use when observing prices which are used for the dynamic fee calculations
     */
    IOrigamiOracle public override dynamicFeePriceOracle;

    /**
     * @dev Internal struct used to abi.encode params through a flashloan request
     */
    enum RebalanceCallbackType {
        REBALANCE_DOWN,
        REBALANCE_UP
    }

    constructor(
        address _initialOwner,
        address _reserveToken_,
        address _debtToken_,
        address _dynamicFeeOracleBaseToken,
        address _lovToken,
        address _borrowLend
    ) OrigamiAbstractLovTokenManager(_initialOwner, _lovToken) {
        _reserveToken = IERC20(_reserveToken_);
        _debtToken = IERC20(_debtToken_);
        dynamicFeeOracleBaseToken = _dynamicFeeOracleBaseToken;
        borrowLend = IOrigamiMorphoBorrowAndLend(_borrowLend);

        // Validate the decimals of the reserve token
        // A borrow token of non-18dp has been tested and is ok
        // A reserve token of non-18dp has not been tested as yet.
        {
            uint256 _decimals = IERC20Metadata(_lovToken).decimals();
            if (IERC20Metadata(_reserveToken_).decimals() != _decimals) revert CommonEventsAndErrors.InvalidToken(_reserveToken_);
        }
    }

    /**
     * @notice Set the `debtToken` <--> `reserveToken` oracle configuration 
     */
    function setOracles(address _debtTokenToReserveTokenOracle, address _dynamicFeePriceOracle) external override onlyElevatedAccess {
        debtTokenToReserveTokenOracle = _validatedOracle(_debtTokenToReserveTokenOracle, address(_reserveToken), address(_debtToken));
        dynamicFeePriceOracle = _validatedOracle(_dynamicFeePriceOracle, dynamicFeeOracleBaseToken, address(_debtToken));
        emit OraclesSet(_debtTokenToReserveTokenOracle, _dynamicFeePriceOracle);
    }

    /**
     * @notice Set the Origami Borrow/Lend position holder
     */
    function setBorrowLend(address _address) external override onlyElevatedAccess {
        if (_address == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        borrowLend = IOrigamiMorphoBorrowAndLend(_address);
        emit BorrowLendSet(_address);
    }

    /**
     * @notice Increase the A/L by reducing liabilities. Flash loan and repay debt, and withdraw collateral to repay the flash loan
     */
    function rebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess {
        _rebalanceUp(params, false);
    }

    /**
     * @notice Force a rebalanceUp ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceUp(RebalanceUpParams calldata params) external override onlyElevatedAccess {
        _rebalanceUp(params, true);
    }

    /**
     * @notice Decrease the A/L by increasing liabilities. Flash loan `debtToken` swap to `reserveToken`
     * and add as collateral into a money market. Then borrow `debtToken` to repay the flash loan.
     */
    function rebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess {
        _rebalanceDown(params, false);
    }
    
    /**
     * @notice Force a rebalanceDown ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceDown(RebalanceDownParams calldata params) external override onlyElevatedAccess {
        _rebalanceDown(params, true);
    }

    function _rebalanceDown(RebalanceDownParams calldata params, bool force) internal {
        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is lower after the rebalance
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);

        uint256 _totalCollateralSupplied = borrowLend.increaseLeverage(
            params.supplyAmount,
            params.borrowAmount,
            params.swapData,
            params.supplyCollateralSurplusThreshold
        );

        // Validate that the new A/L is still within the `rebalanceALRange` and expected slippage range
        uint128 alRatioAfter = _validateAfterRebalance(
            cache, 
            alRatioBefore, 
            params.minNewAL, 
            params.maxNewAL, 
            AlValidationMode.LOWER_THAN_BEFORE, 
            force
        );

        emit Rebalance(
            int256(_totalCollateralSupplied),
            int256(params.borrowAmount),
            alRatioBefore,
            alRatioAfter
        );
    }

    function _rebalanceUp(RebalanceUpParams calldata params, bool force) internal {
        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is lower after the rebalance
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);

        (uint256 _debtRepaidAmount, uint256 _surplusRepaidAmount) = borrowLend.decreaseLeverage(
            params.repayAmount,
            params.withdrawCollateralAmount,
            params.swapData,
            params.repaySurplusThreshold
        );

        // Repaying less than what was asked is only allowed in force mode.
        // This will only happen when there is no more debt in the money market, ie we are fully delevered
        if (_debtRepaidAmount != params.repayAmount) {
            if (!force) revert CommonEventsAndErrors.InvalidAmount(address(_debtToken), params.repayAmount);
        }

        // Validate that the new A/L is still within the `rebalanceALRange` and expected slippage range
        uint128 alRatioAfter = _validateAfterRebalance(
            cache, 
            alRatioBefore, 
            params.minNewAL, 
            params.maxNewAL, 
            AlValidationMode.HIGHER_THAN_BEFORE, 
            force
        );

        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(_debtRepaidAmount + _surplusRepaidAmount),
            alRatioBefore,
            alRatioAfter
        );
    }

    /**
     * @notice Recover accidental donations.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice The total balance of reserve tokens this lovToken holds.
     */
    function reservesBalance() public override(OrigamiAbstractLovTokenManager,IOrigamiLovTokenManager) view returns (uint256) {
        return borrowLend.suppliedBalance();
    }

    /**
     * @notice The underlying token this investment wraps. In this case, it's the `reserveToken`
     */
    function baseToken() external override view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The set of accepted tokens which can be used to invest. 
     * Only the `reserveToken` in this instance
     */
    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(_reserveToken);
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     * Only the `reserveToken` in this instance
     */
    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(_reserveToken);
    }

    /**
     * @notice The reserveToken that the lovToken levers up on
     */
    function reserveToken() public override(OrigamiAbstractLovTokenManager,IOrigamiLovTokenManager) view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The asset which lovToken borrows to increase the A/L ratio
     */
    function debtToken() external override view returns (address) {
        return address(_debtToken);
    }

    /**
     * @notice The debt of the lovToken to the money market, converted into the `reserveToken`
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function liabilities(IOrigamiOracle.PriceType debtPriceType) public override(OrigamiAbstractLovTokenManager,IOrigamiLovTokenManager) view returns (uint256) {
        // In [debtToken] terms.
        uint256 debt = borrowLend.debtBalance();
        if (debt == 0) return 0;

        // Convert the [debtToken] into the [reserveToken] terms
        return debtTokenToReserveTokenOracle.convertAmount(
            address(_debtToken),
            debt,
            debtPriceType, 
            OrigamiMath.Rounding.ROUND_UP
        );
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
            dynamicFeePriceOracle,
            dynamicFeeOracleBaseToken,
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
            dynamicFeePriceOracle,
            dynamicFeeOracleBaseToken,
            _minExitFeeBps,
            _feeLeverageFactor
        );
    }

    /**
     * @notice Deposit a number of `fromToken` into the `reserveToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _depositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override returns (uint256 newReservesAmount) {
        if (fromToken == address(_reserveToken)) {
            newReservesAmount = fromTokenAmount;

            // Supply into the money market
            IOrigamiMorphoBorrowAndLend _borrowLend = borrowLend;
            _reserveToken.safeTransfer(address(_borrowLend), fromTokenAmount);
            _borrowLend.supply(fromTokenAmount);
        } else {
            revert CommonEventsAndErrors.InvalidToken(fromToken);
        }
    }

    /**
     * @notice Calculate the amount of `reserveToken` will be deposited given an amount of `fromToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _previewDepositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override view returns (uint256 newReservesAmount) {
        return fromToken == address(_reserveToken) ? fromTokenAmount : 0;
    }
    
    /**
     * @notice Maximum amount of `fromToken` that can be deposited into the `reserveToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _maxDepositIntoReserves(address fromToken) internal override view returns (uint256 fromTokenAmount) {
        if (fromToken == address(_reserveToken)) {
            (uint256 _supplyCap, uint256 _available) = borrowLend.availableToSupply();
            return _supplyCap == 0 ? MAX_TOKEN_AMOUNT : _available;
        }

        // Anything else returns 0
    }

    /**
     * @notice Calculate the number of `toToken` required in order to mint a given number of `reserveToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _previewMintReserves(address toToken, uint256 reservesAmount) internal override view returns (uint256 newReservesAmount) {
        return toToken == address(_reserveToken) ? reservesAmount : 0;
    }

    /**
     * @notice Redeem a number of `reserveToken` into `toToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _redeemFromReserves(uint256 reservesAmount, address toToken, address recipient) internal override returns (uint256 toTokenAmount) {
        if (toToken == address(_reserveToken)) {
            toTokenAmount = reservesAmount;
            uint256 _amountWithdrawn = borrowLend.withdraw(reservesAmount, recipient);
            if (_amountWithdrawn != reservesAmount) revert CommonEventsAndErrors.InvalidAmount(toToken, reservesAmount);
        } else {
            revert CommonEventsAndErrors.InvalidToken(toToken);
        }
    }

    /**
     * @notice Calculate the number of `toToken` recevied if redeeming a number of `reserveToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _previewRedeemFromReserves(uint256 reservesAmount, address toToken) internal override view returns (uint256 toTokenAmount) {
        return toToken == address(_reserveToken) ? reservesAmount : 0;
    }

    /**
     * @notice Maximum amount of `reserveToken` that can be redeemed to `toToken`
     * This vault only accepts where `fromToken` == `reserveToken`
     */
    function _maxRedeemFromReserves(address toToken, Cache memory /*cache*/) internal override view returns (uint256 reservesAmount) {
        if (toToken == address(_reserveToken)) {
            // Within Morpho, we can always withdraw our supplied collateral as it is siloed.
            reservesAmount = borrowLend.suppliedBalance();
        }

        // Anything else returns 0
    }

    /**
     * @dev Revert if the range is invalid comparing to upstrea Aave/Spark
     */
    function _validateAlRange(Range.Data storage range) internal override view {
        if (!borrowLend.isSafeAlRatio(range.floor)) revert Range.InvalidRange(range.floor, range.ceiling);
    }

    function _validatedOracle(
        address oracleAddress, 
        address baseAsset, 
        address quoteAsset
    ) private view returns (IOrigamiOracle oracle) {
        if (oracleAddress == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        oracle = IOrigamiOracle(oracleAddress);

        // Validate the assets on the oracle match what this lovToken needs
        if (!oracle.matchAssets(baseAsset, quoteAsset)) {
            revert CommonEventsAndErrors.InvalidParam();
        }
    }
}
