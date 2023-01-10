pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/gmx/OrigamiGmxLocker.sol)

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OrigamiInvestment} from "../OrigamiInvestment.sol";
import {IOrigamiGmxManager} from "../../interfaces/investments/gmx/IOrigamiGmxManager.sol";
import {IOrigamiGmxEarnAccount} from "../../interfaces/investments/gmx/IOrigamiGmxEarnAccount.sol";
import {CommonEventsAndErrors} from "../../common/CommonEventsAndErrors.sol";

/// @title Origami GMX Investment
/// @notice Users purchase oGMX with pre-purchased GMX
/// Upon investment, users receive the same as amount of oGMX as deposited GMX
/// Staked oGMX will earn boosted ETH/AVAX & oGMX rewards.
contract OrigamiGmxInvestment is OrigamiInvestment {
    using SafeERC20 for IERC20;

    /// @notice The GMX token used for purchases.
    IERC20 public immutable gmxToken;

    /// @notice The Origami contract managing the holdings of GMX and derived esGMX/mult point rewards
    IOrigamiGmxManager public origamiGmxManager;

    event OrigamiGmxManagerSet(address origamiGmxManager);
    
    constructor(
        address _gmxToken
    ) OrigamiInvestment("Origami GMX Investment", "oGMX") {
        gmxToken = IERC20(_gmxToken);
    }

    /// @notice Set the Origami GMX Manager contract used to apply GMX to earn rewards.
    function setOrigamiGmxManager(address _origamiGmxManager) external onlyOwner {
        if (_origamiGmxManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        origamiGmxManager = IOrigamiGmxManager(_origamiGmxManager);
        emit OrigamiGmxManagerSet(_origamiGmxManager);
    }

    /**
     * @notice Only GMX can be used to buy oGMX
     */
    function acceptedInvestTokens() public override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(gmxToken);
    }

    /**
     * @notice Only GMX can be used to exit oGMX into
     */
    function acceptedExitTokens() external override view returns (address[] memory) {
        return acceptedInvestTokens();
    }
    
    /**
     * @notice Get a quote to buy the oGMX using GMX.
     * @param fromTokenAmount How much of GMX to invest with
     * @param fromToken This must be the address of the GMX token
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return investFeeBps [GMX.io's fee when depositing with `fromToken`]
     */
    function investQuote(
        uint256 fromTokenAmount,
        address fromToken
    ) external override view returns (
        InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromToken != address(gmxToken)) revert CommonEventsAndErrors.InvalidToken(fromToken);
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // oGMX is minted 1:1, no fees
        quoteData.fromToken = fromToken;
        quoteData.fromTokenAmount = fromTokenAmount;
        quoteData.expectedInvestmentAmount = fromTokenAmount;
        // No extra underlyingInvestmentQuoteData

        investFeeBps = new uint256[](0);
    }

    /** 
      * @notice User buys oGMX with an amount GMX.
      * @param quoteData The quote data received from investQuote()
      * @return origamiReceiptAmountOut The actual number of receipt tokens received, inclusive of any fees.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData, 
        uint256 /*slippageBps*/
    ) external override whenNotPaused returns (uint256) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Transfer the GMX straight to the primary earn account which stakes the GMX at GMX.io
        // NB: There is no cooldown when transferring GMX, so using the primary earn account for deposits is fine.
        IOrigamiGmxEarnAccount earnAccount = origamiGmxManager.primaryEarnAccount();
        gmxToken.safeTransferFrom(msg.sender, address(earnAccount), quoteData.fromTokenAmount);
        earnAccount.stakeGmx(quoteData.fromTokenAmount);

        // Mint the oGMX for the user. User gets 1:1 oGMX for the GMX provided.
        _mint(msg.sender, quoteData.fromTokenAmount);
        emit Invested(msg.sender, quoteData.fromTokenAmount, address(gmxToken), quoteData.fromTokenAmount);
        return quoteData.fromTokenAmount;
    }

    /** 
      * @notice Unsupported - cannot invest in oGMX using native chain ETH/AVAX
      */
    function investWithNative(
        InvestQuoteData calldata /*encodedQuote*/, uint256 /*slippageBps*/
    ) external payable override returns (uint256) {
        revert Unsupported();
    }

    /**
     * @notice Get a quote to sell oGMX to GMX.
     * @param investmentTokenAmount The amount of oGMX to sell
     * @param toToken This must be the address of the GMX token
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee]
     */
    function exitQuote(
        uint256 investmentTokenAmount, 
        address toToken
    ) external override view returns (
        ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        if (investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (toToken != address(gmxToken)) revert CommonEventsAndErrors.InvalidToken(toToken);

        exitFeeBps = new uint256[](1);
        (exitFeeBps[0], quoteData.expectedToTokenAmount) = origamiGmxManager.sellOGmxQuote(investmentTokenAmount);

        quoteData.investmentTokenAmount = investmentTokenAmount;
        quoteData.toToken = toToken;
        // No extra underlyingInvestmentQuoteData
    }

    /** 
      * @notice Sell oGMX to receive GMX. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmountOut The number of `toToken` tokens received upon selling the Origami receipt token.
      */
    function exitToToken(
        ExitQuoteData calldata quoteData, 
        uint256 /*slippageBps*/, 
        address recipient
    ) external override whenNotPaused returns (
        uint256 toTokenAmountOut
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        _transfer(msg.sender, address(origamiGmxManager), quoteData.investmentTokenAmount);
        toTokenAmountOut = origamiGmxManager.sellOGmx(quoteData.investmentTokenAmount, recipient);
        emit Exited(msg.sender, quoteData.investmentTokenAmount, address(gmxToken), toTokenAmountOut, recipient);
    }

    /** 
      * @notice Unsupported - cannot exit oGMX to native chain ETH/AVAX
      */
    function exitToNative(
        ExitQuoteData calldata /*encodedQuote*/, uint256 /*slippageBps*/, address payable /*recipient*/
    ) external pure override returns (uint256 /*nativeAmount*/) {
        revert Unsupported();
    }
}
