pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiOTokenManagerWithNative.sol)

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

/**
 * @title Origami oToken Manager (with native ETH/AVAX/etc)
 * @notice The delegated logic to handle deposits/exits into an oToken, and allocating the deposit tokens
 * into the underlying protocol
 */
interface IOrigamiOTokenManagerWithNative is IOrigamiOTokenManager {

    /// @notice $wrappedNative - wrapped ETH/AVAX
    function wrappedNativeToken() external view returns (address);

    /** 
      * @notice User buys this Origami investment with an amount of one of the approved ERC20 tokens. 
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithWrappedNative(
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external returns (
        uint256 investmentAmount
    );

    /** 
      * @notice Sell this oToken to receive one of the accepted tokens. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the oToken
      * @return toBurnAmount The number of oToken to be burnt after exiting this position
      */
    function exitToWrappedNative(
        IOrigamiInvestment.ExitQuoteData calldata quoteData,
        address recipient
    ) external returns (uint256 toTokenAmount, uint256 toBurnAmount);
}
