pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiInvestment.sol)

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

/**
 * @title Origami Investment
 * @notice Users invest in the underlying protocol and receive a number of this Origami investment in return.
 * Origami will apply the accepted investment token into the underlying protocol in the most optimal way.
 */
interface IOrigamiInvestment is IERC20, IERC20Permit {

    /**
     * @notice Track the depoyed version of this contract. 
     */
    function apiVersion() external pure returns (string memory);

    /**
     * @notice The underlying token this investment wraps. 
     * @dev For informational purposes only, eg integrations/FE
     * If the investment wraps a protocol without an ERC20 (eg a non-liquid staked position)
     * then this may be 0x0
     */
    function baseToken() external view returns (address);

    /** 
     * @notice Emitted when a user makes a new investment
     * @param user The user who made the investment
     * @param fromTokenAmount The number of `fromToken` used to invest
     * @param fromToken The token used to invest, one of `acceptedInvestTokens()`
     * @param investmentAmount The number of investment tokens received, after fees
     **/
    event Invested(address indexed user, uint256 fromTokenAmount, address indexed fromToken, uint256 investmentAmount);

    /**
     * @notice Emitted when a user exists a position in an investment
     * @param user The user who exited the investment
     * @param investmentAmount The number of Origami investment tokens sold
     * @param toToken The token the user exited into
     * @param toTokenAmount The number of `toToken` received, after fees
     * @param recipient The receipient address of the `toToken`s
     **/
    event Exited(address indexed user, uint256 investmentAmount, address indexed toToken, uint256 toTokenAmount, address indexed recipient);

    /// @notice Errors for unsupported functions - for example if native chain ETH/AVAX/etc isn't a vaild investment
    error Unsupported();

    /**
     * @notice The set of accepted tokens which can be used to invest.
     * If the native chain ETH/AVAX is accepted, 0x0 will also be included in this list.
     */
    function acceptedInvestTokens() external view returns (address[] memory);

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     * If the native chain ETH/AVAX is accepted, 0x0 will also be included in this list.
     */
    function acceptedExitTokens() external view returns (address[] memory);

    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external view returns (bool);

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external view returns (bool);

    /**
     * @notice Quote data required when entering into this investment.
     */
    struct InvestQuoteData {
        /// @notice The token used to invest, which must be one of `acceptedInvestTokens()`
        address fromToken;

        /// @notice The quantity of `fromToken` to invest with
        uint256 fromTokenAmount;

        /// @notice The maximum acceptable slippage of the `expectedInvestmentAmount`
        uint256 maxSlippageBps;

        /// @notice The maximum deadline to execute the transaction.
        uint256 deadline;

        /// @notice The expected amount of this Origami Investment token to receive in return
        uint256 expectedInvestmentAmount;

        /// @notice The minimum amount of this Origami Investment Token to receive after
        /// slippage has been applied.
        uint256 minInvestmentAmount;

        /// @notice Any extra quote parameters required by the underlying investment
        bytes underlyingInvestmentQuoteData;
    }

    /**
     * @notice Quote data required when exoomg this investment.
     */
    struct ExitQuoteData {
        /// @notice The amount of this investment to sell
        uint256 investmentTokenAmount;

        /// @notice The token to sell into, which must be one of `acceptedExitTokens()`
        address toToken;

        /// @notice The maximum acceptable slippage of the `expectedToTokenAmount`
        uint256 maxSlippageBps;

        /// @notice The maximum deadline to execute the transaction.
        uint256 deadline;

        /// @notice The expected amount of `toToken` to receive in return
        /// @dev Note slippage is applied to this when calling `invest()`
        uint256 expectedToTokenAmount;

        /// @notice The minimum amount of `toToken` to receive after
        /// slippage has been applied.
        uint256 minToTokenAmount;

        /// @notice Any extra quote parameters required by the underlying investment
        bytes underlyingInvestmentQuoteData;
    }

    /**
     * @notice Get a quote to buy this Origami investment using one of the accepted tokens. 
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
    ) external view returns (
        InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    );

    /** 
      * @notice User buys this Origami investment with an amount of one of the approved ERC20 tokens. 
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData
    ) external returns (
        uint256 investmentAmount
    );

    /** 
      * @notice User buys this Origami investment with an amount of native chain token (ETH/AVAX)
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithNative(
        InvestQuoteData calldata quoteData
    ) external payable returns (
        uint256 investmentAmount
    );

    /**
     * @notice Get a quote to sell this Origami investment to receive one of the accepted tokens.
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
    ) external view returns (
        ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    );

    /** 
      * @notice Sell this Origami investment to receive one of the accepted tokens.
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the Origami investment tokens.
      */
    function exitToToken(
        ExitQuoteData calldata quoteData,
        address recipient
    ) external returns (
        uint256 toTokenAmount
    );

    /** 
      * @notice Sell this Origami investment to native ETH/AVAX.
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the native chain token.
      * @return nativeAmount The number of native chain ETH/AVAX/etc tokens received upon selling the Origami investment tokens.
      */
    function exitToNative(
        ExitQuoteData calldata quoteData, 
        address payable recipient
    ) external returns (
        uint256 nativeAmount
    );
}
