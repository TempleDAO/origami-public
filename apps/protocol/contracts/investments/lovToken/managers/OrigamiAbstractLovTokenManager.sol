pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { Range } from "contracts/libraries/Range.sol";
import { Whitelisted } from "contracts/common/access/Whitelisted.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title Abstract Origami lovToken Manager
 * @notice The delegated logic to handle deposits/exits, and borrow/repay (rebalances) into the underlying reserve token
 * @dev The `reserveToken` must have <= 18 decimal places.
 */
abstract contract OrigamiAbstractLovTokenManager is IOrigamiLovTokenManager, OrigamiElevatedAccess, OrigamiManagerPausable, Whitelisted {
    using Range for Range.Data;
    using OrigamiMath for uint256;

    /**
     * @notice lovToken contract - eg lovDSR
     */
    IERC20 public immutable override lovToken;

    /**
     * @notice The minimum fee (in basis points) when users deposit into from the lovToken. 
     * The fee is applied on the lovToken shares -- which are not minted, benefiting remaining holders.
     */
    uint64 internal _minDepositFeeBps;

    /**
     * @notice The minimum fee (in basis points) when users exit out from the lovToken. 
     * The fee is applied on the lovToken shares which are being exited
     * These lovToken shares are burned, benefiting remaining holders.
     */
    uint64 internal _minExitFeeBps;

    /**
     * @notice The nominal leverage factor applied to the difference between the
     * oracle SPOT_PRICE vs the HISTORIC_PRICE. Used within the fee calculation.
     * eg: depositFee = 15 * (HISTORIC_PRICE - SPOT_PRICE) [when spot < historic]
     */
    uint64 internal _feeLeverageFactor;

    /**
     * @notice A buffer added to the amount of debt (in the reserveToken terms)
     * held back from user redeemable reserves, in order to protect from bad debt.
     * @dev stored as 1+buffer% in basis points
     */
    uint64 public override redeemableReservesBufferBps;

    /**
     * @notice The valid lower and upper bounds of A/L allowed when users deposit/exit into lovToken
     * @dev Transactions will revert if the resulting A/L is outside of this range
     */
    Range.Data public override userALRange;

    /**
     * @notice The valid range for when a rebalance is not required.
     * When a rebalance occurs, the transaction will revert if the resulting A/L is outside of this range.
     */
    Range.Data public override rebalanceALRange;

    /**
     * @notice The common precision used
     */
    uint256 public constant override PRECISION = 1e18;

    /**
     * @notice The maximum A/L ratio possible (eg if debt=0)
     */
    uint128 internal constant MAX_AL_RATIO = type(uint128).max;

    /**
     * @notice The maxmimum EE ratio possible (eg if liabilities >= reserves)
     */
    uint128 internal constant MAX_EFECTIVE_EXPOSURE = type(uint128).max;

    /**
     * @dev Max ERC20 token amount for supply/allowances/etc
     */
    uint256 internal constant MAX_TOKEN_AMOUNT = type(uint256).max;

    enum AlValidationMode {
        LOWER_THAN_BEFORE, 
        HIGHER_THAN_BEFORE
    }

    constructor(
        address _initialOwner,
        address _lovToken
    ) OrigamiElevatedAccess(_initialOwner) {
        lovToken = IERC20(_lovToken);
        redeemableReservesBufferBps = uint64(OrigamiMath.BASIS_POINTS_DIVISOR);
    }

    /**
     * @notice Set the minimum fee (in basis points) of lovToken's for deposit and exit,
     * and also the nominal leverage factor applied within the fee calculations
     */
    function setFeeConfig(
        uint16 minDepositFeeBps, 
        uint16 minExitFeeBps, 
        uint16 feeLeverageFactor
    ) external override onlyElevatedAccess {
        if (minDepositFeeBps > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        if (minExitFeeBps > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit FeeConfigSet(minDepositFeeBps, minExitFeeBps, feeLeverageFactor);
        _minDepositFeeBps = minDepositFeeBps;
        _minExitFeeBps = minExitFeeBps;
        _feeLeverageFactor = feeLeverageFactor;
    }

    /**
     * @notice The min deposit/exit fee and feeLeverageFactor configuration
     */
    function getFeeConfig() external override view returns (uint64, uint64, uint64) {
        return (_minDepositFeeBps, _minExitFeeBps, _feeLeverageFactor);
    }

    /**
     * @notice Set the amount of reserves buffer that is held proportionate to the debt
     * @dev represented in basis points
     * Since this will change the lovToken share price, it should be executed with a private mempool
     * or it could get front run
     */
    function setRedeemableReservesBufferBps(uint16 buffer) external override onlyElevatedAccess {
        if (buffer > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();

        // Set to 100+buffer% now to save the addition later.
        buffer += uint16(OrigamiMath.BASIS_POINTS_DIVISOR);
        emit RedeemableReservesBufferSet(buffer);

        redeemableReservesBufferBps = buffer;
    }

    /**
     * @notice Set the valid lower and upper bounds of A/L when users deposit/exit into lovToken
     */
    function setUserALRange(uint128 floor, uint128 ceiling) external override onlyElevatedAccess {
        if (floor <= PRECISION) revert Range.InvalidRange(floor, ceiling);
        emit UserALRangeSet(floor, ceiling);
        userALRange.set(floor, ceiling);

        // Any extra validation on AL depending on the strategy
        _validateAlRange(userALRange);
    }

    /**
     * @notice Set the valid range for when a rebalance is not required.
     */
    function setRebalanceALRange(uint128 floor, uint128 ceiling) external override onlyElevatedAccess {
        if (floor <= PRECISION) revert Range.InvalidRange(floor, ceiling);
        emit RebalanceALRangeSet(floor, ceiling);
        rebalanceALRange.set(floor, ceiling);

        // Any extra validation on AL depending on the strategy
        _validateAlRange(rebalanceALRange);
    }

    /**
     * @notice Recover any token - should not be able to recover tokens which are normally
     * held in this contract
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external virtual;

    /** 
      * @notice Deposit into the reserve token on behalf of a user
      * @param account The user account which is investing.
      * @param quoteData The quote data to deposit into the reserve token
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investWithToken(
        address account,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external virtual override onlyLovToken returns (
        uint256 investmentAmount
    ) {
        if (_paused.investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        if (!_isAllowed(account)) revert CommonEventsAndErrors.InvalidAccess();
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        // Note this also checks that the debtToken/reserveToken oracle prices are valid.
        uint128 oldAL = _assetToLiabilityRatio(cache);

        uint256 newReservesAmount = _depositIntoReserves(quoteData.fromToken, quoteData.fromTokenAmount);

        // The number of shares is calculated based off this `newReservesAmount`
        // However not all of these shares are minted and given to the user -- the deposit fee is removed
        investmentAmount = _reservesToShares(cache, newReservesAmount);
        investmentAmount = investmentAmount.subtractBps(_dynamicDepositFeeBps());

        // Verify the amount
        if (investmentAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (investmentAmount < quoteData.minInvestmentAmount) {
            revert CommonEventsAndErrors.Slippage(quoteData.minInvestmentAmount, investmentAmount);
        }

        // A user deposit will raise the A/L (more reserves, but the same debt)
        // This needs to be validated so it doesn't go above the ceiling
        // Not required if there are not yet any liabilities (where A/L would be uint128.max)
        if (cache.liabilities != 0) {
            // Need to recalculate the assets in the cache
            cache.assets = reservesBalance();

            // The underlying debt (in reserveToken terms) may have changed as more was deposited into reserves
            cache.liabilities = liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);

            uint128 newAL = _assetToLiabilityRatio(cache);
            _validateALRatio(userALRange, oldAL, newAL, AlValidationMode.HIGHER_THAN_BEFORE);
        }
    }

    /** 
      * @notice Exit from the reserve token on behalf of a user.
      * param account The account to exit on behalf of
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the exit token
      * @return toTokenAmount The number of tokens received upon selling the lovToken
      * @return toBurnAmount The number of lovTokens to be burnt after exiting this position
      */
    function exitToToken(
        address /*account*/,
        IOrigamiInvestment.ExitQuoteData calldata quoteData,
        address recipient
    ) external virtual override onlyLovToken returns (
        uint256 toTokenAmount,
        uint256 toBurnAmount
    ) {
        if (_paused.exitsPaused) revert CommonEventsAndErrors.IsPaused();
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        // Note this also checks that the debtToken/reserveToken oracle prices are valid.
        uint128 oldAL = _assetToLiabilityRatio(cache);

        // The entire amount of lovTokens will be burned
        // But only the non-fee portion is redeemed to reserves and sent to the user
        toBurnAmount = quoteData.investmentTokenAmount;
        uint256 reservesAmount = toBurnAmount.subtractBps(_dynamicExitFeeBps());

        // Given the number of redeemable lovToken's calculate how many reserves this equates to
        // at the current share price and the reserve supply prior to exiting
        reservesAmount = _sharesToReserves(cache, reservesAmount);

        // Now exit from the reserves and check slippage
        toTokenAmount = _redeemFromReserves(reservesAmount, quoteData.toToken, recipient);
        if (toTokenAmount < quoteData.minToTokenAmount) {
            revert CommonEventsAndErrors.Slippage(quoteData.minToTokenAmount, toTokenAmount);
        }

        // A user exit will lower the A/L (less reserves, but the same debt)
        // This needs to be validated so it doesn't go below the floor
        // Not required if there are not yet any liabilities (where A/L would be uint128.max)
        if (cache.liabilities != 0) {
            // Need to recalculate the assets in the cache
            cache.assets = reservesBalance();

            // The underlying debt (in reserveToken terms) may have changed as more was redeemed from reserves
            cache.liabilities = liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);

            uint128 newAL = _assetToLiabilityRatio(cache);
            _validateALRatio(userALRange, oldAL, newAL, AlValidationMode.LOWER_THAN_BEFORE);
        }
    }

    /**
     * @notice Get a quote to buy this Origami investment using one of the accepted tokens. 
     * @param fromTokenAmount How much of `fromToken` to invest with
     * @param fromToken What ERC20 token to purchase with. This must be one of `acceptedInvestTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received investment amount
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return investFeeBps Any fees expected when investing with the given token, either from Origami or from the underlying investment.
     */
    function investQuote(
        uint256 fromTokenAmount, 
        address fromToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external virtual override view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _newReservesAmount = _previewDepositIntoReserves(fromToken, fromTokenAmount);

        // The number of shares is calculated based off this `_newReservesAmount`
        // However not all of these shares are minted and given to the user -- the deposit fee is removed
        uint256 _investmentAmount = _reservesToShares(cache, _newReservesAmount);
        uint256 _depositFeeRate = _dynamicDepositFeeBps();
        _investmentAmount = _investmentAmount.subtractBps(_depositFeeRate);

        quoteData.fromToken = fromToken;
        quoteData.fromTokenAmount = fromTokenAmount;
        quoteData.maxSlippageBps = maxSlippageBps;
        quoteData.deadline = deadline;
        quoteData.expectedInvestmentAmount = _investmentAmount;
        quoteData.minInvestmentAmount = _investmentAmount.subtractBps(maxSlippageBps);
        // quoteData.underlyingInvestmentQuoteData remains as bytes(0)

        investFeeBps = new uint256[](1);
        investFeeBps[0] = _depositFeeRate;
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited into the lovToken
     * taking into consideration: 
     *    1/ The max reserves in possible until the A/L ceiling would be hit
     *    2/ Any other constraints of the underlying implementation
     */
    function maxInvest(address fromToken) external override view returns (uint256 fromTokenAmount) {
        // First get the underlying implementation's max allowed
        fromTokenAmount = _maxDepositIntoReserves(fromToken);

        // Also bound by the max amount of reserves which can be added before the A/L ceiling is hit
        uint256 _maxReserves = _maxUserReserves(IOrigamiOracle.PriceType.SPOT_PRICE);
        if (_maxReserves < MAX_TOKEN_AMOUNT) {
            uint256 _currentReserves = reservesBalance();
            uint256 _remainingCapacity;

            if (_maxReserves > _currentReserves) {
                unchecked {
                    _remainingCapacity = _maxReserves - _currentReserves;
                }
                // Convert to the fromToken. Use previewMint as this amount of fromToken's
                // should return the exact shares when invested
                _remainingCapacity = _previewMintReserves(fromToken, _remainingCapacity);
            }

            // Finally, use the minimum of the underlying implementation's max allowed, and this A/L capped max amount
            if (_remainingCapacity < fromTokenAmount) {
                fromTokenAmount = _remainingCapacity;
            }
        }
    }

    /**
     * @notice Get a quote to sell this Origami investment to receive one of the accepted tokens.
     * @param investmentAmount The number of Origami investment tokens to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return exitFeeBps Any fees expected when exiting the investment to the nominated token, either from Origami or from the underlying investment.
     */
    function exitQuote(
        uint256 investmentAmount,
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external virtual override view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        if (investmentAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Exit fees are taken from the lovToken amount, so get the non-fee amount to actually exit
        uint256 _exitFeeRate = _dynamicExitFeeBps();
        uint256 toExitAmount = investmentAmount.subtractBps(_exitFeeRate);

        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        // Convert to the underlying toToken
        toExitAmount = _previewRedeemFromReserves(
            // Convert the non-fee lovToken amount to ERC-4626 reserves
            _sharesToReserves(cache, toExitAmount),
            toToken
        );

        quoteData.investmentTokenAmount = investmentAmount;
        quoteData.toToken = toToken;
        quoteData.maxSlippageBps = maxSlippageBps;
        quoteData.deadline = deadline;
        quoteData.expectedToTokenAmount = toExitAmount;
        quoteData.minToTokenAmount = toExitAmount.subtractBps(maxSlippageBps);
        // quoteData.underlyingInvestmentQuoteData remains as bytes(0)

        exitFeeBps = new uint256[](1);
        exitFeeBps[0] = _exitFeeRate;
    }

    /**
     * @notice The maximum amount of lovToken shares that can be exited into the `toToken`
     * taking into consideration: 
     *    1/ The max reserves out possible until the A/L floor would be hit
     *    2/ Any other constraints from the underyling implementation
     */
    function maxExit(address toToken) external override view returns (uint256 sharesAmount) {
        // Calculate the max reserves which can be removed before the A/L floor is hit
        // Round up for the minimum reserves
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        uint256 _minReserves = cache.liabilities.mulDiv(
            userALRange.floor, 
            PRECISION, 
            OrigamiMath.Rounding.ROUND_UP
        );

        // Only check the underlying implementation if there's capacity to remove reserves
        if (cache.assets > _minReserves) {
            // Calculate the max number of lovToken shares which can be exited given the A/L 
            // floor on reserves
            uint256 _amountFromAvailableCapacity;
            unchecked {
                _amountFromAvailableCapacity = cache.assets - _minReserves;
            }

            // Check the underlying implementation's max reserves that can be redeemed
            uint256 _underlyingAmount = _maxRedeemFromReserves(toToken);

            // Use the minimum of both the underlying implementation max and
            // the capacity based on the A/L floor
            if (_underlyingAmount < _amountFromAvailableCapacity) {
                _amountFromAvailableCapacity = _underlyingAmount;
            }

            // Convert reserves to lovToken shares
            sharesAmount = _reservesToShares(cache, _amountFromAvailableCapacity);

            // Since exit fees are taken when exiting (so these reserves aren't actually redeemed),
            // reverse out the fees
            sharesAmount = sharesAmount.inverseSubtractBps(_dynamicExitFeeBps());

            // Finally use the min of the derived amount and the lovToken total supply
            if (sharesAmount > cache.totalSupply) {
                sharesAmount = cache.totalSupply;
            }
        }
    }

    /**
     * @notice The current deposit and exit fee based on market conditions.
     * Fees are the equivalent of burning lovToken shares - benefit remaining vault users
     * @dev represented in basis points
     */
    function getDynamicFeesBps() external view returns (uint256 depositFeeBps, uint256 exitFeeBps) {
        depositFeeBps = _dynamicDepositFeeBps();
        exitFeeBps = _dynamicExitFeeBps();
    }

    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external override view returns (bool) {
        return _paused.investmentsPaused;
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external override view returns (bool) {
        return _paused.exitsPaused;
    }

    /**
     * @notice The reserveToken that the lovToken levers up on
     */
    function reserveToken() public virtual override view returns (address);

    /**
     * @notice The total balance of reserve tokens this lovToken holds, and also if deployed as collateral
     * in other platforms
     * @dev Explicitly tracked rather than via reserveToken.balanceOf() to avoid donation/inflation vectors.
     */
    function reservesBalance() public virtual override view returns (uint256);

    /**
     * @notice The debt of the lovToken from the borrower, converted into the reserveToken
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function liabilities(IOrigamiOracle.PriceType debtPriceType) public virtual override view returns (uint256);

    /**
     * @notice The current asset/liability (A/L) of this lovToken
     * to `PRECISION` precision
     * @dev = reserves / liabilities
     */
    function assetToLiabilityRatio() external override view returns (uint128) {
        return _assetToLiabilityRatio(populateCache(IOrigamiOracle.PriceType.SPOT_PRICE));
    }

    /**
     * @notice Retrieve the current assets, liabilities and calculate the ratio
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function assetsAndLiabilities(IOrigamiOracle.PriceType debtPriceType) external override view returns (
        uint256 /*assets*/,
        uint256 /*liabilities*/,
        uint256 /*ratio*/
    ) {
        Cache memory cache = populateCache(debtPriceType);
        return (
            cache.assets,
            cache.liabilities,
            _assetToLiabilityRatio(cache)
        );
    }

    /**
     * @notice The current effective exposure (EE) of this lovToken
     * to `PRECISION` precision
     * @dev = reserves / (reserves - liabilities)
     * Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function effectiveExposure(IOrigamiOracle.PriceType debtPriceType) external override view returns (uint128) {
        Cache memory cache = populateCache(debtPriceType);
        if (cache.assets > cache.liabilities) {
            uint256 redeemableReserves;
            unchecked {
                redeemableReserves = cache.assets - cache.liabilities;
            }

            // Round up for EE calc
            uint256 ee = cache.assets.mulDiv(PRECISION, redeemableReserves, OrigamiMath.Rounding.ROUND_UP);
            if (ee < MAX_EFECTIVE_EXPOSURE) {
                return uint128(ee);
            }
        }

        return MAX_EFECTIVE_EXPOSURE;
    }

    /**
     * @notice The amount of reserves that users may redeem their lovTokens as of this block
     * A small buffer amount is added to the current debt to protect from variations in
     * debt calculation
     * @dev = reserves - (1 + buffer%) * liabilities
     * Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function userRedeemableReserves(IOrigamiOracle.PriceType debtPriceType) external override view returns (uint256) {
        return _userRedeemableReserves(populateCache(debtPriceType));
    }

    /**
     * @notice How many reserve tokens would one get given a number of lovToken shares 
     * and the current lovToken totalSupply
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function sharesToReserves(uint256 shares, IOrigamiOracle.PriceType debtPriceType) external override view returns (uint256) {
        return _sharesToReserves(populateCache(debtPriceType), shares);
    }

    /**
     * @notice How many lovToken shares would one get given a number of reserve tokens
     * and the current lovToken totalSupply
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function reservesToShares(uint256 reserves, IOrigamiOracle.PriceType debtPriceType) external override view returns (uint256) {
        return _reservesToShares(populateCache(debtPriceType), reserves);
    }

    // An internal cache to save having to recalculate
    struct Cache {
        uint256 assets;
        uint256 liabilities;
        uint256 totalSupply;
    }

    function populateCache(IOrigamiOracle.PriceType debtPriceType) internal view returns (Cache memory cache) {
        cache.assets = reservesBalance();
        cache.liabilities = liabilities(debtPriceType);
        cache.totalSupply = lovToken.totalSupply();
    }

    /**
     * @notice The current deposit fee based on market conditions.
     * Deposit fees are applied to the portion of lovToken shares the depositor 
     * would have received. Instead that fee portion isn't minted (benefiting remaining users)
     * @dev represented in basis points
     */
    function _dynamicDepositFeeBps() internal virtual view returns (uint256);

    /**
     * @notice The current exit fee based on market conditions.
     * Exit fees are applied to the lovToken shares the user is exiting. 
     * That portion is burned prior to being redeemed (benefiting remaining users)
     * @dev represented in basis points
     */
    function _dynamicExitFeeBps() internal virtual view returns (uint256);

    /**
     * @dev Perform any extra validation on the A/L range
     * By default, nothing extra validation is required, however a manager implementation
     * may decide to perform extra. For example if borrowing from Aave/Spark, 
     * this can check that the A/L floor is within a tolerable range which won't get liquidated
     * Since those parameters could be updated at a later date by Aave/Spark
     */
    function _validateAlRange(Range.Data storage range) internal virtual view {}

    function _userRedeemableReserves(Cache memory cache) internal view returns (uint256) {
        // Round up for liabilities with buffer
        uint256 _bufferBps = redeemableReservesBufferBps;
        uint256 _liabilitiesWithBuffer = _bufferBps == OrigamiMath.BASIS_POINTS_DIVISOR
            ? cache.liabilities
            : cache.liabilities.mulDiv(
                _bufferBps, 
                OrigamiMath.BASIS_POINTS_DIVISOR,
                OrigamiMath.Rounding.ROUND_UP
            );

        unchecked {
            return cache.assets > _liabilitiesWithBuffer
                ? cache.assets - _liabilitiesWithBuffer
                : 0;
        }
    }

    function _assetToLiabilityRatio(Cache memory cache) internal pure returns (uint128) {
        if (cache.liabilities != 0) {
            // Round down for A/L calc
            uint256 alr = cache.assets.mulDiv(PRECISION, cache.liabilities, OrigamiMath.Rounding.ROUND_DOWN);
            if (alr < MAX_AL_RATIO) {
                return uint128(alr);
            }
        }

        return MAX_AL_RATIO;
    }

    function _sharesToReserves(Cache memory cache, uint256 shares) internal view returns (uint256) {
        // If totalSupply is zero, then just return shares 1:1 scaled down to the reserveToken decimals
        // If > 0 then the decimal conversion is handled already (numerator cancels out denominator)
        // Round down for calculating reserves from shares
        return cache.totalSupply == 0
            ? shares.scaleDown(_reservesToSharesScalar(), OrigamiMath.Rounding.ROUND_DOWN)
            : shares.mulDiv(_userRedeemableReserves(cache), cache.totalSupply, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function _reservesToShares(Cache memory cache, uint256 reserves) private view returns (uint256) {
        // If totalSupply is zero, then just return reserves 1:1 scaled up to the shares decimals
        // If > 0 then the decimal conversion is handled already (numerator cancels out denominator)
        if (cache.totalSupply == 0) {
            return reserves.scaleUp(_reservesToSharesScalar());
        }

        // In the unlikely case that no available reserves for user withdrawals (100% of reserves are held back to repay debt),
        // then revert
        uint256 _redeemableReserves = _userRedeemableReserves(cache);
        if (_redeemableReserves == 0) {
            revert NoAvailableReserves();
        }

        // Round down for calculating shares from reserves
        return reserves.mulDiv(cache.totalSupply, _redeemableReserves, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /**
      * @dev Calculate the asset scalar to convert from reserveToken --> 18 decimal places (`PRECISION`)
      * The reserveToken cannot have more than the lovToken decimals (18dp)
      */
    function _reservesToSharesScalar() internal view returns (uint256) {
        uint8 _reservesDecimals = IERC20Metadata(reserveToken()).decimals();
        uint8 _sharesDecimals = IERC20Metadata(address(lovToken)).decimals();
        if (_reservesDecimals > _sharesDecimals) revert CommonEventsAndErrors.InvalidToken(reserveToken());
        return 10 ** (_sharesDecimals - _reservesDecimals);
    }

    /**
     * @notice Deposit a number of `fromToken` into the `reserveToken`
     */
    function _depositIntoReserves(address fromToken, uint256 fromTokenAmount) internal virtual returns (uint256 newReservesAmount);

    /**
     * @notice Calculate the amount of `reserveToken` will be deposited given an amount of `fromToken`
     */
    function _previewDepositIntoReserves(address fromToken, uint256 fromTokenAmount) internal virtual view returns (uint256 newReservesAmount);

    /**
     * @notice Maximum amount of `fromToken` that can be deposited into the `reserveToken`
     */
    function _maxDepositIntoReserves(address fromToken) internal virtual view returns (uint256 fromTokenAmount);

    /**
     * @notice Calculate the number of `toToken` required in order to mint a given number of `reserveTokens`
     */
    function _previewMintReserves(address toToken, uint256 reservesAmount) internal virtual view returns (uint256 toTokenAmount);

    /**
     * @notice Redeem a number of `reserveToken` into `toToken`
     */
    function _redeemFromReserves(uint256 reservesAmount, address toToken, address recipient) internal virtual returns (uint256 toTokenAmount);

    /**
     * @notice Calculate the number of `toToken` recevied if redeeming a number of `reserveToken`
     */
    function _previewRedeemFromReserves(uint256 reservesAmount, address toToken) internal virtual view returns (uint256 toTokenAmount);

    /**
     * @notice Maximum amount of `reserveToken` that can be redeemed to `toToken`
     */
    function _maxRedeemFromReserves(address toToken) internal virtual view returns (uint256 reservesAmount);

    /**
     * @notice Calculate the max number of reserves allowed before the user debt ceiling is hit, 
     * taking into consideration any current liabiltiies
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function _maxUserReserves(IOrigamiOracle.PriceType debtPriceType) internal virtual view returns (uint256 reservesAmount);

    /**
     * @notice Validate that the A/L ratio hasn't moved beyond the given A/L range.
     */
    function _validateALRatio(Range.Data storage validRange, uint128 ratioBefore, uint128 ratioAfter, AlValidationMode alMode) internal virtual {
        if (alMode == AlValidationMode.LOWER_THAN_BEFORE) {
            // A/L needs to be decreasing (may be equal if a very small amount is deposited/exited)
            if (ratioAfter > ratioBefore) revert ALTooHigh(ratioBefore, ratioAfter, ratioBefore);
            
            // Check that the new A/L is not below the floor
            // In this mode, the A/L may be above the ceiling still, but should be decreasing
            // Note: The A/L may not be strictly decreasing in this mode since the liabilities (in reserve terms) is also
            // fluctuating
            if (ratioAfter < validRange.floor) revert ALTooLow(ratioBefore, ratioAfter, validRange.floor);
        } else {
            // A/L needs to be increasing (may be equal if a very small amount is deposited/exited)
            if (ratioAfter < ratioBefore) revert ALTooLow(ratioBefore, ratioAfter, ratioBefore);

            // Check that the new A/L is not above the ceiling
            // In this mode, the A/L may be below the floor still, but should be increasing
            // Note: The A/L may not be strictly increasing in this mode since the liabilities (in reserve terms) is also
            // fluctuating
            if (ratioAfter > validRange.ceiling) revert ALTooHigh(ratioBefore, ratioAfter, validRange.ceiling);
        }
    }

    modifier onlyLovToken() {
        if (msg.sender != address(lovToken)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
