pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/OrigamiLendingManager.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLendingSupplyManager } from "contracts/interfaces/investments/lending/IOrigamiLendingSupplyManager.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { Whitelisted } from "contracts/common/access/Whitelisted.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title Origami Lending Supply Manager
 * @notice Manages the deposits/exits into an Origami oToken vault for lending purposes,
 * eg oUSDC. The supplied assets are forwarded onto a 'lending clerk' which manages the
 * collateral and debt
 * @dev supports an asset with decimals <= 18 decimal places
 */
contract OrigamiLendingSupplyManager is IOrigamiLendingSupplyManager, OrigamiElevatedAccess, OrigamiManagerPausable, Whitelisted {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;
    using OrigamiMath for uint256;

    /**
     * @notice The asset which users supply
     * eg USDC for oUSDC
     */
    IERC20Metadata public immutable override asset;

    /**
     * @notice The scalar to convert asset to `PRECISION` decimals (used for both the `oToken` and `debtToken`)
     */
    uint256 private immutable _assetScalar;

    /**
     * @notice The Origami oToken which uses this manager
     */
    address public immutable override oToken;

    /**
     * @notice The Origami ovToken which wraps the oToken
     */
    address public immutable override ovToken;

    /**
     * @notice A circuit breaker is used to ensure no more than a cap
     * is exited in a given period
     */
    IOrigamiCircuitBreakerProxy public immutable override circuitBreakerProxy;

    /**
     * @notice The clerk responsible for managing borrows, repays and debt of borrowers
     */
    IOrigamiLendingClerk public override lendingClerk;

    /**
     * @notice The address used to collect the Origami fees.
     */
    address public override feeCollector;

    /**
     * @notice The proportion of fees retained when users exit their position.
     * @dev represented in basis points
     */
    uint96 public override exitFeeBps;

    constructor(
        address _initialOwner,
        address _asset,
        address _oToken,
        address _ovToken,
        address _circuitBreakerProxy,
        address _feeCollector,
        uint96 _exitFeeBps
    ) OrigamiElevatedAccess(_initialOwner) {
        asset = IERC20Metadata(_asset);

        // Set the asset scalar to convert from asset <--> oToken
        // The asset cannot have more than 18 decimal places
        {
            uint8 _assetDecimals = asset.decimals();
            uint8 _origamiDecimals = IERC20Metadata(_oToken).decimals();
            if (_assetDecimals > _origamiDecimals) revert CommonEventsAndErrors.InvalidToken(_asset);
            _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);
        }

        oToken = _oToken;
        ovToken = _ovToken;
        circuitBreakerProxy = IOrigamiCircuitBreakerProxy(_circuitBreakerProxy);
        feeCollector = _feeCollector;
        exitFeeBps = _exitFeeBps;
    }

    /**
     * @notice Set the clerk responsible for managing borrows, repays and debt of borrowers
     */
    function setLendingClerk(address _lendingClerk) external override onlyElevatedAccess {
        if (_lendingClerk == address(0)) revert CommonEventsAndErrors.InvalidAddress(_lendingClerk);

        // Update the approval's
        address _oldClerk = address(lendingClerk);
        if (_oldClerk != address(0)) {
            asset.forceApprove(_oldClerk, 0);
        }
        asset.forceApprove(_lendingClerk, type(uint256).max);

        emit LendingClerkSet(_lendingClerk);
        lendingClerk = IOrigamiLendingClerk(_lendingClerk);
    }

    /**
     * @notice Set the Origami fee collector address
     */
    function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(_feeCollector);
        feeCollector = _feeCollector;
    }

    /**
     * @notice Set the proportion of fees retained when users exit their position.
     * @dev represented in basis points
     */
    function setExitFeeBps(uint96 feeBps) external onlyElevatedAccess {
        if (feeBps > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit ExitFeeBpsSet(feeBps);
        exitFeeBps = feeBps;
    }

    /**
     * @notice Recover any token -- this contract won't hold any asset tokens
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20Metadata(token).safeTransfer(to, amount);
    }

    /** 
      * @notice User buys oToken with an amount `asset`.
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investWithToken(
        address account,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external override onlyOToken returns (
        uint256 investmentAmount
    ) {
        if (_paused.investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.fromToken != address(asset)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);

        // Only the ovToken (which does it's own checks) and explicitly allowed contracts are allowed
        if (account != ovToken) {
            if (!_isAllowed(account)) revert CommonEventsAndErrors.InvalidAccess();
        }

        lendingClerk.deposit(quoteData.fromTokenAmount);

        // User gets 1:1 oToken for the token provided, but scaled up form the asset decimals
        // to the oToken decimals
        investmentAmount = quoteData.fromTokenAmount.scaleUp(_assetScalar);
    }

    /** 
      * @notice Sell oToken to receive `asset`. 
      * param account The account to exit on behalf of
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `asset`
      * @return toTokenAmount The number of `asset` tokens received upon selling the oToken.
      * @return toBurnAmount The number of oToken to be burnt after exiting this position
      */
    function exitToToken(
        address /*account*/,
        IOrigamiInvestment.ExitQuoteData calldata quoteData,
        address recipient
    ) external override onlyOToken returns (
        uint256 toTokenAmount,
        uint256 toBurnAmount
    ) {
        if (_paused.exitsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.toToken != address(asset)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        // Ensure that this exit doesn't break the circuit breaker limits for oToken
        circuitBreakerProxy.preCheck(
            address(oToken),
            quoteData.investmentTokenAmount
        );

        // Exit fees are taken from the sender's oToken amount.
        (uint256 nonFees, uint256 fees) = quoteData.investmentTokenAmount.splitSubtractBps(
            exitFeeBps, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        toBurnAmount = nonFees;

        // Collect the fees
        if (fees != 0) {
            IERC20Metadata(oToken).safeTransfer(feeCollector, fees);
        }

        if (nonFees != 0) {
            // This scaleDown intentionally rounds down (so it's not in the user's benefit)
            toTokenAmount = nonFees.scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_DOWN);
            if (toTokenAmount != 0) {
                lendingClerk.withdraw(toTokenAmount, recipient);
            }
        }
    }

    /**
     * @notice The underlying token this investment wraps. 
     * In this case, it's the `asset`
     */
    function baseToken() external override view returns (address) {
        return address(asset);
    }

    /**
     * @notice The set of accepted tokens which can be used to invest.
     */
    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(asset);
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     */
    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(asset);
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
    ) external view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromToken != address(asset)) revert CommonEventsAndErrors.InvalidToken(fromToken);
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // oToken is minted 1:1, no fees or slippage
        uint256 amountOut = fromTokenAmount.scaleUp(_assetScalar);
        quoteData = IOrigamiInvestment.InvestQuoteData({
            fromToken: fromToken,
            fromTokenAmount: fromTokenAmount,
            maxSlippageBps: maxSlippageBps,
            deadline: deadline,
            expectedInvestmentAmount: amountOut,
            minInvestmentAmount: amountOut,
            underlyingInvestmentQuoteData: "" // No extra underlyingInvestmentQuoteData
        });
        
        investFeeBps = new uint256[](0);
    }
    
    /**
     * @notice Get a quote to sell this Origami investment to receive one of the accepted tokens.
     * @param investmentAmount The number of Origami investment tokens to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return _exitFeeBps Any fees expected when exiting the investment to the nominated token, either from Origami or from the underlying investment.
     */
    function exitQuote(
        uint256 investmentAmount,
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory _exitFeeBps
    ) {
        if (investmentAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (toToken != address(asset)) revert CommonEventsAndErrors.InvalidToken(toToken);

        // Exit fees are taken from the sender's oToken amount. 
        // Calculate the remainder rounding down
        uint256 _feeBps = exitFeeBps;
        uint256 toExitAmount = investmentAmount.subtractBps(_feeBps, OrigamiMath.Rounding.ROUND_DOWN);

        // This scaleDown intentionally rounds down (so it's not in the user's benefit)
        uint256 amountOut = toExitAmount.scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_DOWN);
        quoteData.investmentTokenAmount = investmentAmount;
        quoteData.toToken = toToken;
        quoteData.maxSlippageBps = maxSlippageBps;
        quoteData.deadline = deadline;
        quoteData.expectedToTokenAmount = amountOut;
        quoteData.minToTokenAmount = amountOut;
        // No extra underlyingInvestmentQuoteData

        _exitFeeBps = new uint256[](1);
        _exitFeeBps[0] = _feeBps;
    }

    modifier onlyOToken() {
        if (msg.sender != oToken) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     * For lending supply oToken's, this is unbounded if supplying the correct asset, otherwise zero
     */
    function maxInvest(address fromToken) external override view returns (uint256 amount) {
        if (fromToken == address(asset)) {
            amount = type(uint256).max;
        }
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     * For lending supply oToken's, this is bounded by the currently available 
     * amount of the supply asset that can be withdrawn
     */
    function maxExit(address toToken) external override view returns (uint256 amount) {
        if (toToken == address(asset)) {
            // Capacity is bound by the available remaining in the circuit breaker (18dp)
            amount = circuitBreakerProxy.available(address(oToken), address(this));

            // And also by what's available in the lendingClerk.
            // Convert from the underlying asset to the oToken decimals
            uint256 amountFromLendingClerk = lendingClerk.totalAvailableToWithdraw().scaleUp(_assetScalar);
            if (amountFromLendingClerk < amount) {
                amount = amountFromLendingClerk;
            }

            // Since exit fees are taken when exiting,
            // reverse out the fees
            // Round down to be the inverse of when they're applied (and rounded up) when exiting
            amount = amount.inverseSubtractBps(exitFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
        }
    }
}
