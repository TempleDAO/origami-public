pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiOTokenWithNative.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { OrigamiOToken } from "contracts/investments/OrigamiOToken.sol";
import { IOrigamiOTokenManagerWithNative } from "contracts/interfaces/investments/IOrigamiOTokenManagerWithNative.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IWrappedToken } from "contracts/interfaces/common/IWrappedToken.sol";

/// @title Origami oToken (with native ETH support for deposits/exits)
///
/// @notice Users deposit with an accepted token and are minted oTokens
/// Generally speaking this oToken will represent the underlying protocol it is wrapping, 1:1
///
/// @dev The logic on how to handle the deposits/exits is delegated to a manager contract.
contract OrigamiOTokenWithNative is OrigamiOToken {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /**
     * @notice The ETH (Arbitrum) or AVAX (Avalanche) native token which can be used for buying and selling the oToken
     */
    address public immutable wrappedNativeToken;

    error InvalidSender(address caller);

    constructor(
        address _initialOwner,
        address _wrappedNativeToken,
        string memory _name,
        string memory _symbol
    ) OrigamiOToken(_initialOwner, _name, _symbol) {
        wrappedNativeToken = _wrappedNativeToken;
    }

    /**
     * @dev Only the wrappedNativeToken contract (eg weth) can send us ETH
     */
    receive() external payable {
        if (msg.sender != wrappedNativeToken) revert InvalidSender(msg.sender);
    }

    /** 
     * @notice User buys oTokens with an amount of native chain token (ETH/AVAX)
     * @param quoteData The quote data received from investQuote()
     * @return investmentAmount The number of oTokens to expect, inclusive of any fees.
     */
    function investWithNative(
        InvestQuoteData calldata quoteData
    ) external payable override nonReentrant returns (uint256 investmentAmount) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.fromTokenAmount != msg.value) revert CommonEventsAndErrors.InvalidAmount(address(0), msg.value);
        if (quoteData.fromToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);

        // Convert the native to the wrapped token (eg weth)
        IWrappedToken(wrappedNativeToken).deposit{value: quoteData.fromTokenAmount}();

        // Send the wrapped native token to the manager then invest
        address _managerAddr = address(manager);
        IERC20(wrappedNativeToken).safeTransfer(_managerAddr, quoteData.fromTokenAmount);
        investmentAmount = IOrigamiOTokenManagerWithNative(_managerAddr).investWithWrappedNative(quoteData);

        emit Invested(msg.sender, msg.value, address(0), investmentAmount);

        // Mint the oToken for the user
        _mint(msg.sender, investmentAmount);
    }
   
    /** 
     * @notice Sell oToken to native ETH/AVAX.
     * @param quoteData The quote data received from exitQuote()
     * @param recipient The receiving address of the native chain token.
     * @return nativeAmount The number of native chain ETH/AVAX/etc tokens received upon selling the oToken.
     */
    function exitToNative(
        ExitQuoteData calldata quoteData, 
        address payable recipient
    ) external override nonReentrant returns (
        uint256 nativeAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.toToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        // Send the oToken to the manager then exit
        address _managerAddr = address(manager);
        _transfer(msg.sender, _managerAddr, quoteData.investmentTokenAmount);
        uint256 oTokenToBurn;
        (nativeAmount, oTokenToBurn) = IOrigamiOTokenManagerWithNative(_managerAddr).exitToWrappedNative(quoteData, address(this));

        emit Exited(msg.sender, quoteData.investmentTokenAmount, address(0), nativeAmount, recipient);
        
        // Burn the oToken
        _burn(_managerAddr, oTokenToBurn);

        // Convert the wrapped native token (weth/wavax) to the native token (ETH/AVAX)
        IWrappedToken(wrappedNativeToken).withdraw(nativeAmount);
        recipient.sendValue(nativeAmount);
    }
}
