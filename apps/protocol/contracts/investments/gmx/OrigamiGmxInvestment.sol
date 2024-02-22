pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/gmx/OrigamiGmxInvestment.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";
import { IOrigamiGmxManager } from "contracts/interfaces/investments/gmx/IOrigamiGmxManager.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami GMX
/// @notice Users purchase oGMX with pre-purchased GMX
/// Upon investment, users receive the same as amount of oGMX as deposited GMX
contract OrigamiGmxInvestment is OrigamiInvestment {
    using SafeERC20 for IERC20;

    /// @notice The Origami contract managing the holdings of GMX and derived esGMX/mult point rewards
    IOrigamiGmxManager public origamiGmxManager;

    event OrigamiGmxManagerSet(address indexed origamiGmxManager);
    
    constructor(
        address _initialOwner
    ) OrigamiInvestment("Origami GMX Token", "oGMX", _initialOwner) {}

    /// @notice Set the Origami GMX Manager contract used to apply GMX to earn rewards.
    function setOrigamiGmxManager(address _origamiGmxManager) external onlyElevatedAccess {
        if (_origamiGmxManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit OrigamiGmxManagerSet(_origamiGmxManager);
        origamiGmxManager = IOrigamiGmxManager(_origamiGmxManager);
    }

    /**
     * @notice The underlying token this investment wraps. 
     * In this case, it's the $GMX token
     */
    function baseToken() external view returns (address) {
        return address(origamiGmxManager.gmxToken());
    }

    /**
     * @notice The set of accepted tokens which can be used to invest.
     */
    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        return origamiGmxManager.acceptedOGmxTokens();
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     */
    function acceptedExitTokens() external override view returns (address[] memory) {
        return origamiGmxManager.acceptedOGmxTokens();
    }
        
    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external override view returns (bool) {
        return origamiGmxManager.paused().gmxInvestmentsPaused;
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external override view returns (bool) {
        return origamiGmxManager.paused().gmxExitsPaused;
    }

    /**
     * @notice Get a quote to buy the oGMX using GMX.
     * @param fromTokenAmount How much of GMX to invest with
     * @param fromToken This must be the address of the GMX token
     * @param maxSlippageBps The maximum acceptable slippage of the received investment amount
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
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
        return origamiGmxManager.investOGmxQuote(fromTokenAmount, fromToken, maxSlippageBps, deadline);
    }

    /** 
      * @notice User buys oGMX with an amount GMX.
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData
    ) external override nonReentrant returns (uint256 investmentAmount) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Send the investment token to the gmx manager
        IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(origamiGmxManager), quoteData.fromTokenAmount);
        investmentAmount = origamiGmxManager.investOGmx(quoteData);

        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);

        // Mint the oGMX for the user
        _mint(msg.sender, investmentAmount);
    }

    /** 
      * @notice Unsupported - cannot invest in oGMX using native chain ETH/AVAX
      */
    function investWithNative(
        InvestQuoteData calldata /*quoteData*/
    ) external payable override returns (uint256) {
        revert Unsupported();
    }

    /**
     * @notice Get a quote to sell oGMX to GMX.
     * @param investmentTokenAmount The amount of oGMX to sell
     * @param toToken This must be the address of the GMX token
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee]
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
        return origamiGmxManager.exitOGmxQuote(investmentTokenAmount, toToken, maxSlippageBps, deadline);
    }

    /** 
      * @notice Sell oGMX to receive GMX. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `t\oToken`
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

        // Send the oGMX to the gmx manager
        _transfer(msg.sender, address(origamiGmxManager), quoteData.investmentTokenAmount);
        uint256 oGmxToBurn;
        (toTokenAmount, oGmxToBurn) = origamiGmxManager.exitOGmx(quoteData, recipient);
        
        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);
        
        // Burn the oGMX
        _burn(address(origamiGmxManager), oGmxToBurn);
    }

    /** 
      * @notice Unsupported - cannot exit oGMX to native chain ETH/AVAX
      */
    function exitToNative(
        ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/
    ) external pure override returns (uint256 /*nativeAmount*/) {
        revert Unsupported();
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     * For oGMX it's simplified -- assume no cap
     */
    function maxInvest(address /*fromToken*/) external override pure returns (uint256 amount) {
        amount = type(uint256).max;
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     * For oGMX it's simplified -- assume no cap
     */
    function maxExit(address /*toToken*/) external override pure returns (uint256 amount) {
        amount = type(uint256).max;
    }
}
