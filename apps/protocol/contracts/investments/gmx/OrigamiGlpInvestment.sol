pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/gmx/OrigamiGlpInvestment.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";
import { IWrappedToken } from "contracts/interfaces/common/IWrappedToken.sol";
import { IOrigamiGmxManager } from "contracts/interfaces/investments/gmx/IOrigamiGmxManager.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami GLP
/// @notice Users purchase oGLP with an accepted GMX.io ERC20 token, ETH, or staked GLP
/// Upon investment, users receive the same as amount of oGLP 1:1 as if they were purchasing GLP directly via GMX.io.
contract OrigamiGlpInvestment is OrigamiInvestment {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice The ETH (Arbitrum) or AVAX (Avalanche) native token which can be used for buying and selling the origami receipt token
    address public immutable wrappedNativeToken;

    /// @notice The Origami contract managing the holdings of GLP and derived GMX/esGMX/mult point rewards
    IOrigamiGmxManager public origamiGlpManager;

    error InvalidSender(address caller);
    event OrigamiGlpManagerSet(address indexed origamiGlpManager);

    constructor(
        address _initialOwner,
        address _wrappedNativeToken
    ) OrigamiInvestment("Origami GLP Token", "oGLP", _initialOwner) {
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @dev Only the wrappedNativeToken contract (eg weth) can send us ETH, when we withdraw to pay out
    /// a user liquidation.
    receive() external payable {
        if (msg.sender != wrappedNativeToken) revert InvalidSender(msg.sender);
    }

    /// @notice Set the Origami GLP Manager contract used to apply GLP to earn rewards.
    function setOrigamiGlpManager(address _origamiGlpManager) external onlyElevatedAccess {
        if (_origamiGlpManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit OrigamiGlpManagerSet(_origamiGlpManager);
        origamiGlpManager = IOrigamiGmxManager(_origamiGlpManager);
    }

    /**
     * @notice The underlying token this investment wraps. 
     * In this case, it's the $GLP token
     */
    function baseToken() external view returns (address) {
        return address(origamiGlpManager.glpToken());
    }

    /**
     * @notice The set of accepted tokens which can be used to buy oGLP
     * @dev This is the same list as when investing in GLP at GMX.io
     * With the addition of 0x0 for native ETH/AVAX, and also existing user purchased & staked GLP
     */
    function acceptedInvestTokens() external override view returns (address[] memory) {
        return origamiGlpManager.acceptedGlpTokens();
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into
     * @dev For oGLP, this is the same set of tokens that can be used to invest
     */
    function acceptedExitTokens() external override view returns (address[] memory) {
        return origamiGlpManager.acceptedGlpTokens();
    }
    
    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external override view returns (bool) {
        return origamiGlpManager.paused().glpInvestmentsPaused;
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external override view returns (bool) {
        return origamiGlpManager.paused().glpExitsPaused;
    }

    /**
     * @notice Get a quote to buy the oGLP using one of the approved tokens, inclusive of GMX.io fees.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param fromTokenAmount How much of `fromToken` to invest with
     * @param fromToken What ERC20 token to purchase with. This must be one of `acceptedInvestTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received investment amount
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for the underlying investment type. To be passed through when executing the quote.
     * @return investFeeBps [GMX.io's fee when depositing with `fromToken`]
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
        return origamiGlpManager.investOGlpQuote(fromTokenAmount, fromToken, maxSlippageBps, deadline);
    }

    /** 
      * @notice User buys oGLP with an amount of one of the approved ERC20 tokens. 
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData
    ) external override nonReentrant returns (
        uint256 investmentAmount
    ) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Send the investment token to the glp manager then invest
        IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(origamiGlpManager), quoteData.fromTokenAmount);
        investmentAmount = origamiGlpManager.investOGlp(quoteData.fromToken, quoteData);

        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);

        // Mint the oGLP for the user
        _mint(msg.sender, investmentAmount);
    }

    /** 
      * @notice User buys oGLP tokens with an amount of native chain token (ETH/AVAX)
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The number of receipt tokens to expect, inclusive of any fees.
      */
    function investWithNative(
        InvestQuoteData calldata quoteData
    ) external payable override nonReentrant returns (uint256 investmentAmount) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.fromTokenAmount != msg.value) revert CommonEventsAndErrors.InvalidAmount(address(0), msg.value);
        if (quoteData.fromToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);

        // Convert the native to the wrapped token (eg weth)
        IWrappedToken(wrappedNativeToken).deposit{value: quoteData.fromTokenAmount}();

        // Send the wrapped native token to the glp manager then invest
        IERC20(wrappedNativeToken).safeTransfer(address(origamiGlpManager), quoteData.fromTokenAmount);
        investmentAmount = origamiGlpManager.investOGlp(wrappedNativeToken, quoteData);

        emit Invested(msg.sender, msg.value, address(0), investmentAmount);

        // Mint the oGLP for the user
        _mint(msg.sender, investmentAmount);
    }

    /**
     * @notice Get a quote to sell oGLP to receive one of the accepted tokens.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param investmentTokenAmount The amount of oGLP to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee, GMX.io's fee when selling to `toToken`]
     */
    function exitQuote(
        uint256 investmentTokenAmount, 
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external override view returns (
        ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        return origamiGlpManager.exitOGlpQuote(investmentTokenAmount, toToken, maxSlippageBps, deadline);
    }

    /** 
      * @notice Sell oGLP to receive one of the accepted tokens. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the Origami receipt token.
      */
    function exitToToken(
        ExitQuoteData calldata quoteData, 
        address recipient
    ) external override nonReentrant returns (
        uint256 toTokenAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        // Send the oGLP to the glp manager then exit. 
        _transfer(msg.sender, address(origamiGlpManager), quoteData.investmentTokenAmount);
        uint256 oGlpToBurn;
        (toTokenAmount, oGlpToBurn) = origamiGlpManager.exitOGlp(quoteData.toToken, quoteData, recipient);

        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);

        // Burn the oGlp
        _burn(address(origamiGlpManager), oGlpToBurn);
    }

    /** 
      * @notice Sell oGLP to native ETH/AVAX.
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the native chain token.
      * @return nativeAmount The number of native chain ETH/AVAX/etc tokens received upon selling the Origami receipt token.
      */
    function exitToNative(
        ExitQuoteData calldata quoteData, 
        address payable recipient
    ) external override nonReentrant returns (
        uint256 nativeAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.toToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        // Send the oGLP to the glp manager then exit
        _transfer(msg.sender, address(origamiGlpManager), quoteData.investmentTokenAmount);
        uint256 oGlpToBurn;
        (nativeAmount, oGlpToBurn) = origamiGlpManager.exitOGlp(wrappedNativeToken, quoteData, address(this));

        emit Exited(msg.sender, quoteData.investmentTokenAmount, address(0), nativeAmount, recipient);
        
        // Burn the oGlp
        _burn(address(origamiGlpManager), oGlpToBurn);

        // Convert the wrapped native token (weth/wavax) to the native token (ETH/AVAX)
        IWrappedToken(wrappedNativeToken).withdraw(nativeAmount);
        recipient.sendValue(nativeAmount);
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     * For oGLP it's simplified -- assume no cap
     */
    function maxInvest(address /*fromToken*/) external override pure returns (uint256 amount) {
        amount = type(uint256).max;
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     * For oGLP it's simplified -- assume no cap
     */
    function maxExit(address /*toToken*/) external override pure returns (uint256 amount) {
        amount = type(uint256).max;
    }
}
