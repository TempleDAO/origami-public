pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiOTokenManager.sol)

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

/**
 * @title Origami oToken Manager (no native ETH/AVAX/etc)
 * @notice The delegated logic to handle deposits/exits into an oToken, and allocating the deposit tokens
 * into the underlying protocol
 */
interface IOrigamiOTokenManager is IOrigamiManagerPausable {

    /**
     * @notice The underlying token this investment wraps. 
     * @dev For informational purposes only, eg integrations/FE
     */
    function baseToken() external view returns (address);

    /**
     * @notice The set of accepted tokens which can be used to invest.
     */
    function acceptedInvestTokens() external view returns (address[] memory);

    /**
     * @notice The set of accepted tokens which can be used to exit into.
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
     * @notice Get a quote to buy this oToken using one of the accepted tokens. 
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
    );

    /** 
      * @notice User buys this Origami investment with an amount of one of the approved ERC20 tokens. 
      * @param account The account to deposit on behalf of
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithToken(
        address account,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external returns (
        uint256 investmentAmount
    );

    /**
     * @notice Get a quote to sell this oToken to receive one of the accepted tokens.
     * @param investmentAmount The number of oTokens to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return exitFeeBps Any fees expected when exiting the investment to the nominated token, either from Origami or from the underlying protocol.
     */
    function exitQuote(
        uint256 investmentAmount,
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    );

    /** 
      * @notice Sell this oToken to receive one of the accepted tokens. 
      * @param account The account to exit on behalf of
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the oToken
      * @return toBurnAmount The number of oToken to be burnt after exiting this position
      */
    function exitToToken(
        address account,
        IOrigamiInvestment.ExitQuoteData calldata quoteData,
        address recipient
    ) external returns (uint256 toTokenAmount, uint256 toBurnAmount);

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     */
    function maxInvest(address fromToken) external view returns (uint256 amount);

    /**
     * @notice The maximum amount of tokens that can be exited into the toToken
     * taking any other underlying protocol constraints into consideration
     */
    function maxExit(address toToken) external view returns (uint256 amount);
}
