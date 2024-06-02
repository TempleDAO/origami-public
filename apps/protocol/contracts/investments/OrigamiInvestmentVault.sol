pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiInvestmentVault.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { RepricingToken } from "contracts/common/RepricingToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Whitelisted } from "contracts/common/access/Whitelisted.sol";

/**
 * @title Origami Investment Vault
 * @notice A repricing Origami Investment. Users invest in the underlying protocol and are allocated shares.
 * Origami will apply the supplied token into the underlying protocol in the most optimal way.
 * The pricePerShare() will increase over time as upstream rewards are claimed by the protocol added to the reserves.
 * This makes the Origami Investment Vault auto-compounding.
 */
contract OrigamiInvestmentVault is IOrigamiInvestmentVault, RepricingToken, Whitelisted, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /**
     * @notice The performance fee which Origami takes from harvested rewards before compounding into reserves.
     * @dev Represented in basis points
     */
    uint256 public override performanceFee;

    string public constant API_VERSION = "0.2.0";

    /**
     * @notice The helper contract to retrieve Origami USD prices
     * @dev Required for off-chain/subgraph integration
     */
    ITokenPrices public tokenPrices;

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        address _origamiInvestment,
        address _tokenPrices,
        uint256 _performanceFee,
        uint48 _reservesActualisationDuration
    ) RepricingToken(_name, _symbol, _origamiInvestment, _reservesActualisationDuration, _initialOwner) {
        tokenPrices = ITokenPrices(_tokenPrices);
        if (_performanceFee > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        performanceFee = _performanceFee;
    }
    
    /**
     * @notice Track the depoyed version of this contract. 
     */
    function apiVersion() external override pure returns (string memory) {
        return API_VERSION;
    }

    /**
     * @notice The underlying token this investment wraps. 
     * @dev For an investment vault, this is the underyling reserve token
     */
    function baseToken() external view returns (address) {
        return reserveToken;
    }

    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external override view returns (bool) {
        return IOrigamiInvestment(reserveToken).areInvestmentsPaused();
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external override view returns (bool) {
        return IOrigamiInvestment(reserveToken).areExitsPaused();
    }

    /**
     * @notice Set the helper to calculate current off-chain/subgraph integration
     */
    function setTokenPrices(address _tokenPrices) external onlyElevatedAccess {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit TokenPricesSet(_tokenPrices);
        tokenPrices = ITokenPrices(_tokenPrices);
    }

    /**
     * @notice Set the vault performance fee
     * @dev Represented in basis points
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyElevatedAccess {
        if (_performanceFee > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit PerformanceFeeSet(_performanceFee);
        performanceFee = _performanceFee;
    }

    /// @dev The reseve token is a valid invest/exit token, and needs to be appended.
    /// Unforunately needs to copy the input array as this is memory defined storage.
    function appendReserveToken(address[] memory items) private view returns (address[] memory newItems) {
        newItems = new address[](items.length+1);

        uint256 _length = items.length;
        uint256 i;
        for (; i < _length; ++i) {
            newItems[i] = items[i];
        }
        newItems[i] = reserveToken;
    }

    /**
     * @notice The set of accepted tokens which can be used to invest.
     * For the Origami Investment Vault, this is the underlying OrigamiInvestment's acceptedInvestTokens()
     * Plus the reserve token.
     */
    function acceptedInvestTokens() external override view returns (address[] memory) {
        return appendReserveToken(IOrigamiInvestment(reserveToken).acceptedInvestTokens());
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     * For the Origami Investment Vault, this is the underlying OrigamiInvestment's acceptedExitTokens()
     * Plus the reserve token.
     */
    function acceptedExitTokens() external override view returns (address[] memory) {
        return appendReserveToken(IOrigamiInvestment(reserveToken).acceptedExitTokens());
    }

    /**
     * @notice Get a quote to invest into the Origami investment vault using one of the accepted tokens. 
     * @dev The 0x0 address can be used for native chain ETH/AVAX
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
    ) external override view returns (
        InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // If investing with the reserve token, it's based off the current pricePerShare()
        // Otherwise first get a quote for the number of underlying reserve tokens using the fromToken
        // and then calculate the number of shares based off the current pricePerShare
        address _reserveToken = reserveToken;
        if (fromToken == _reserveToken) {
            quoteData.fromToken = fromToken;
            quoteData.fromTokenAmount = fromTokenAmount;
            quoteData.maxSlippageBps = maxSlippageBps;
            quoteData.deadline = deadline;
            quoteData.expectedInvestmentAmount = reservesToShares(fromTokenAmount);
            quoteData.minInvestmentAmount = quoteData.expectedInvestmentAmount.subtractBps(
                maxSlippageBps, 
                OrigamiMath.Rounding.ROUND_UP
            );
            // quoteData.underlyingInvestmentQuoteData remains as bytes(0)
            investFeeBps = new uint256[](0);
        } else {
            // Get the underlying quote and encode into underlyingInvestmentQuoteData
            // Safe to assume 100% slippage for the imtermediate/underlying investment as the
            // final amount of shares are checked at the end.
            (quoteData, investFeeBps) = IOrigamiInvestment(_reserveToken).investQuote(
                fromTokenAmount, fromToken, OrigamiMath.BASIS_POINTS_DIVISOR, deadline
            );
            quoteData.underlyingInvestmentQuoteData = abi.encode(quoteData);
            quoteData.maxSlippageBps = maxSlippageBps;

            // Now calculate how many shares that translates to.
            quoteData.expectedInvestmentAmount = reservesToShares(quoteData.expectedInvestmentAmount);
            quoteData.minInvestmentAmount = quoteData.expectedInvestmentAmount.subtractBps(
                maxSlippageBps, 
                OrigamiMath.Rounding.ROUND_UP
            );
        }
    }

    /** 
      * @notice User invests into this Origami investment vault with an amount of one of the approved ERC20 tokens. 
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData
    ) external override nonReentrant returns (
        uint256 investmentAmount
    ) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (!_isAllowed(msg.sender)) revert CommonEventsAndErrors.InvalidAccess();

        // If investing with the reserve token, pull them from the user
        // Otherwise pull the fromToken and use to invest in the underlying Origami Investment
        address _reserveToken = reserveToken;
        uint256 reservesAmount;
        if (quoteData.fromToken == _reserveToken) {
            // Pull the `reserveToken` from the user
            reservesAmount = quoteData.fromTokenAmount;
            IERC20(_reserveToken).safeTransferFrom(msg.sender, address(this), reservesAmount);
        } else {
            // Use the `fromToken` to invest in the underlying and receive `reserveToken`           
            InvestQuoteData memory underlyingQuoteData = abi.decode(
                quoteData.underlyingInvestmentQuoteData, (InvestQuoteData)
            );

            // The underlying quote fromToken must match
            if (quoteData.fromToken != underlyingQuoteData.fromToken) revert CommonEventsAndErrors.InvalidToken(
                underlyingQuoteData.fromToken
            );
            if (quoteData.fromTokenAmount != underlyingQuoteData.fromTokenAmount) revert CommonEventsAndErrors.InvalidAmount(
                underlyingQuoteData.fromToken, 
                underlyingQuoteData.fromTokenAmount
            );

            // Pull the `fromToken` into this contract and approve the reserveToken to pull it.
            IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(this), quoteData.fromTokenAmount);
            IERC20(quoteData.fromToken).safeIncreaseAllowance(_reserveToken, quoteData.fromTokenAmount);

            reservesAmount = IOrigamiInvestment(_reserveToken).investWithToken(underlyingQuoteData);
        }

        // Now issue shares to the user based off the `reserveAmount`
        investmentAmount = _issueSharesFromReserves(
            reservesAmount,
            msg.sender,
            quoteData.minInvestmentAmount
        );

        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);
    }

    /** 
      * @notice User invests into this Origami investment vault with an amount of native chain token (ETH/AVAX)
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithNative(
        InvestQuoteData calldata quoteData
    ) external override nonReentrant payable returns (
        uint256 investmentAmount
    ) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.fromTokenAmount != msg.value) revert CommonEventsAndErrors.InvalidAmount(address(0), msg.value);
        if (quoteData.fromToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);
        if (!_isAllowed(msg.sender)) revert CommonEventsAndErrors.InvalidAccess();

        // Invest in the underlying first using the user supplied native ETH/AVAX
        InvestQuoteData memory underlyingQuoteData = abi.decode(
            quoteData.underlyingInvestmentQuoteData, (InvestQuoteData)
        );
        uint256 reservesAmount = IOrigamiInvestment(reserveToken).investWithNative{value: msg.value}(
            underlyingQuoteData
        );

        // Now issue shares to the user based off the `reservesAmount`
        investmentAmount = _issueSharesFromReserves(
            reservesAmount,
            msg.sender,
            quoteData.minInvestmentAmount
        );
        emit Invested(msg.sender, quoteData.fromTokenAmount, address(0), investmentAmount);
    }

    /**
     * @notice Get a quote to exit out of this Origami investment vault to receive one of the accepted tokens.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
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
    ) external override view returns (
        ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        if (investmentAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // If exiting to the reserve token, it's based off the current pricePerShare()
        // Otherwise first find the expected amount of reserves based on the current pricePerShare()
        // and then get a quote from the underlying Origami Investment for the number of toTokens to expect
        if (toToken == reserveToken) {
            // If it's the reserves, can redeem reserves directly from the shares.
            quoteData.investmentTokenAmount = investmentAmount;
            quoteData.toToken = toToken;
            quoteData.maxSlippageBps = maxSlippageBps;
            quoteData.deadline = deadline;
            quoteData.expectedToTokenAmount = sharesToReserves(investmentAmount);
            quoteData.minToTokenAmount = quoteData.expectedToTokenAmount.subtractBps(
                maxSlippageBps, 
                OrigamiMath.Rounding.ROUND_UP
            );
            // quoteData.underlyingInvestmentQuoteData remains as bytes(0)
            exitFeeBps = new uint256[](0);
        } else {
            uint256 expectedReserveAmount = sharesToReserves(investmentAmount);
            // Safe to assume 100% slippage for the imtermediate/underlying exit as the
            // final amount of toToken's are checked at the end.
            (quoteData, exitFeeBps) = IOrigamiInvestment(reserveToken).exitQuote(
                expectedReserveAmount, toToken, OrigamiMath.BASIS_POINTS_DIVISOR, deadline
            );

            quoteData = ExitQuoteData({
                investmentTokenAmount: investmentAmount,
                toToken: toToken,
                maxSlippageBps: maxSlippageBps,
                deadline: deadline,
                expectedToTokenAmount: quoteData.expectedToTokenAmount,
                minToTokenAmount: quoteData.expectedToTokenAmount.subtractBps(
                    maxSlippageBps, 
                    OrigamiMath.Rounding.ROUND_UP
                ),
                underlyingInvestmentQuoteData: abi.encode(quoteData)
            });
        }
    }

    /** 
      * @notice Exit out of this Origami investment vault to receive one of the accepted tokens.
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the Origami investment tokens.
      */
    function exitToToken(
        ExitQuoteData calldata quoteData,
        address recipient
    ) external override returns (
        uint256 toTokenAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);
        
        // If exiting to the reserve token, redeem and send them to the user
        // Otherwise first redeem the reserve tokens and then exit the underlying Origami investment
        if (quoteData.toToken == reserveToken) {
            toTokenAmount = _redeemReservesFromShares(
                quoteData.investmentTokenAmount,
                msg.sender,
                quoteData.minToTokenAmount,
                recipient
            );
        } else {
            ExitQuoteData memory underlyingQuoteData = abi.decode(
                quoteData.underlyingInvestmentQuoteData, (ExitQuoteData)
            );

            // The underlying quote toToken must match
            if (quoteData.toToken != underlyingQuoteData.toToken) revert CommonEventsAndErrors.InvalidToken(underlyingQuoteData.toToken);

            // Update the underlying quote data with the actual amount of reserves we received.
            // Safe to assume no slippage for the imtermediate/underlying exit as the final amount of toToken's are checked at the end.
            underlyingQuoteData.investmentTokenAmount = _redeemReservesFromShares(
                quoteData.investmentTokenAmount,
                msg.sender,
                0,
                address(this)
            );

            // Now exchange the reserve token to the actual token the user requested.
            toTokenAmount = IOrigamiInvestment(reserveToken).exitToToken(
                underlyingQuoteData,
                recipient
            );

            if (toTokenAmount < quoteData.minToTokenAmount) revert CommonEventsAndErrors.Slippage(quoteData.minToTokenAmount, toTokenAmount);
        }

        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);
    }

    /** 
      * @notice Sell this Origami investment to native ETH/AVAX.
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the native chain token.
      * @return nativeAmount The number of native chain ETH/AVAX/etc tokens received upon selling the Origami investment tokens.
      */
    function exitToNative(
        ExitQuoteData calldata quoteData,
        address payable recipient
    ) external override nonReentrant returns (uint256 nativeAmount) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.toToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        // Otherwise first redeem the reserve tokens and then exit the underlying Origami investment
        ExitQuoteData memory underlyingQuoteData = abi.decode(
            quoteData.underlyingInvestmentQuoteData, (ExitQuoteData)
        );

        // Update the underlying quote data with the actual amount of reserves we received.
        // Safe to assume no slippage for the imtermediate/underlying exit as the final amount of toToken's are checked at the end.
        underlyingQuoteData.investmentTokenAmount = _redeemReservesFromShares(
            quoteData.investmentTokenAmount,
            msg.sender,
            0,
            address(this)
        );

        // Now exchange the reserve token to the actual token the user requested.
        nativeAmount = IOrigamiInvestment(reserveToken).exitToNative(
            underlyingQuoteData,
            recipient
        );

        if (nativeAmount < quoteData.minToTokenAmount) revert CommonEventsAndErrors.Slippage(quoteData.minToTokenAmount, nativeAmount);

        emit Exited(msg.sender, quoteData.investmentTokenAmount, address(0), nativeAmount, recipient);
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     */
    function maxInvest(address fromToken) external override view returns (uint256 amount) {
        // Unbounded if using the reserveToken
        // Delegate to the underlying reserveToken for any other token
        address _reserveToken = reserveToken;
        amount = fromToken == _reserveToken
            ? type(uint256).max
            : IOrigamiInvestment(_reserveToken).maxInvest(fromToken);
    }

    /**
     * @notice The maximum amount of tokens that can be exited into the toToken
     * taking any other underlying protocol constraints into consideration
     */
    function maxExit(address toToken) external override view returns (uint256 amount) {
        // Unbounded if to the reserveToken
        // Delegate to the underlying reserveToken for any other token
        address _reserveToken = reserveToken;
        amount = toToken == _reserveToken
            ? type(uint256).max
            : reservesToShares(
                IOrigamiInvestment(_reserveToken).maxExit(toToken)
              );
    }
}
