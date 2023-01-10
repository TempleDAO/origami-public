pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiInvestmentVault.sol)

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IOrigamiInvestmentVault} from "../interfaces/investments/IOrigamiInvestmentVault.sol";
import {IOrigamiInvestmentManager} from "../interfaces/investments/IOrigamiInvestmentManager.sol";
import {IOrigamiInvestment} from "../interfaces/investments/IOrigamiInvestment.sol";
import {ITokenPrices} from "../interfaces/common/ITokenPrices.sol";
import {RepricingToken} from "../common/RepricingToken.sol";
import {CommonEventsAndErrors} from "../common/CommonEventsAndErrors.sol";

/**
 * @title Origami Investment Vault
 * @notice A repricing Origami Investment. Users invest in the underlying protocol and are allocated shares.
 * Origami will apply the supplied token into the underlying protocol in the most optimal way.
 * The pricePerShare() will increase over time as upstream rewards are claimed by the protocol added to the reserves.
 * This makes the Origami Investment Vault auto-compounding.
 */
contract OrigamiInvestmentVault is IOrigamiInvestmentVault, RepricingToken, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The quote data required to exit from the underlying Origami Investment reserve token
    struct UnderlyingExitQuoteData {
        uint256 expectedReserveAmount;
        ExitQuoteData underlyingExitQuoteData;
    }

    /// @notice The helper contract to retrieve Origami USD prices
    ITokenPrices public tokenPrices;

    /// @notice The Origami investment manager contract, which can give apr/apy based rates 
    IOrigamiInvestmentManager public investmentManager;

    event InvestmentManagerSet(address indexed _investmentManager);
    event TokenPricesSet(address indexed _tokenPrices);

    constructor(
        string memory _name,
        string memory _symbol,
        address _origamiInvestment,
        address _tokenPrices
    ) RepricingToken(_name, _symbol, _origamiInvestment) {
        tokenPrices = ITokenPrices(_tokenPrices);
    }
    
    /** 
     * @notice Protocol can pause the investment.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /** 
     * @notice Protocol can unpause the investment.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    function setInvestmentManager(address _investmentManager) external onlyOwner {
        if (_investmentManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        investmentManager = IOrigamiInvestmentManager(_investmentManager);
        emit InvestmentManagerSet(_investmentManager);
    }

    function setTokenPrices(address _tokenPrices) external onlyOwner {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        tokenPrices = ITokenPrices(_tokenPrices);
        emit TokenPricesSet(_tokenPrices);
    }
    
    /// @dev The reseve token is a valid invest/exit token, and needs to be appended.
    /// Unforunately needs to copy the input array as this is memory defined storage.
    function appendReserveToken(address[] memory items) private view returns (address[] memory newItems) {
        newItems = new address[](items.length+1);

        uint256 i;
        for (; i < items.length; ++i) {
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
    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        return appendReserveToken(IOrigamiInvestment(reserveToken).acceptedExitTokens());
    }

    /**
     * @notice Get a quote to invest into the Origami investment vault using one of the accepted tokens. 
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param fromTokenAmount How much of `fromToken` to invest with
     * @param fromToken What ERC20 token to purchase with. This must be one of `acceptedInvestTokens`
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return investFeeBps Any fees expected when investing with the given token, either from Origami or from the underlying investment.
     */
    function investQuote(
        uint256 fromTokenAmount, 
        address fromToken
    ) external override view returns (
        InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // If investing with the reserve token, it's based off the current pricePerShare()
        // Otherwise first get a quote for the number of underlying reserve tokens using the fromToken
        // and then calculate the number of shares based off the current pricePerShare
        if (fromToken == reserveToken) {
            quoteData.fromToken = fromToken;
            quoteData.fromTokenAmount = fromTokenAmount;
            quoteData.expectedInvestmentAmount = reservesToShares(fromTokenAmount);
            // quoteData.underlyingInvestmentQuoteData remains as bytes(0)
        } else {
            // Get the underlying quote and encode into underlyingInvestmentQuoteData
            (quoteData, investFeeBps) = IOrigamiInvestment(reserveToken).investQuote(fromTokenAmount, fromToken);
            quoteData.underlyingInvestmentQuoteData = abi.encode(quoteData);

            // Now calculate how many shares that translates to.
            quoteData.expectedInvestmentAmount = reservesToShares(quoteData.expectedInvestmentAmount);
        }
    }

    function applySlippage(uint256 quote, uint256 slippageBps) internal pure returns (uint256) {
        return quote * (10_000 - slippageBps) / 10_000;
    }

    /** 
      * @notice User invests into this Origami investment vault with an amount of one of the approved ERC20 tokens. 
      * @param quoteData The quote data received from investQuote()
      * @param slippageBps Acceptable slippage, applied to the `quoteData` params
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData,
        uint256 slippageBps
    ) external override whenNotPaused returns (
        uint256 investmentAmount
    ) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // If investing with the reserve token, pull them from the user
        // Otherwise pull the fromToken and use to invest in the underlying Origami Investment
        uint256 reservesAmount;
        if (quoteData.fromToken == reserveToken) {
            // Pull the `reserveToken` from the user
            reservesAmount = quoteData.fromTokenAmount;
            IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), reservesAmount);
        } else {
            // Pull the `fromToken` into this contract and approve the reserveToken to pull it.
            IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(this), quoteData.fromTokenAmount);
            IERC20(quoteData.fromToken).safeIncreaseAllowance(reserveToken, quoteData.fromTokenAmount);

            // Use the `fromToken` to invest in the underlying and receive `reserveToken`           
            InvestQuoteData memory underlyingQuoteData = abi.decode(
                quoteData.underlyingInvestmentQuoteData, (InvestQuoteData)
            );
            reservesAmount = IOrigamiInvestment(reserveToken).investWithToken(
                underlyingQuoteData,
                slippageBps
            );
        }

        // Now issue shares to the user based off the `reserveAmount`
        investmentAmount = _issueSharesFromReserves(
            reservesAmount,
            msg.sender,
            applySlippage(quoteData.expectedInvestmentAmount, slippageBps)
        );
        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);
    }

    /** 
      * @notice User invests into this Origami investment vault with an amount of native chain token (ETH/AVAX)
      * @param quoteData The quote data received from investQuote()
      * @param slippageBps Acceptable slippage, applied to the `quoteData` params
      * @return investmentAmount The actual number of this Origami investment tokens received.
      */
    function investWithNative(
        InvestQuoteData calldata quoteData,
        uint256 slippageBps
    ) external override whenNotPaused nonReentrant payable returns (
        uint256 investmentAmount
    ) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.fromTokenAmount != msg.value) revert CommonEventsAndErrors.InvalidAmount(address(0), msg.value);
        if (quoteData.fromToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);

        // Invest in the underlying first using the user supplied native ETH/AVAX
        InvestQuoteData memory underlyingQuoteData = abi.decode(
            quoteData.underlyingInvestmentQuoteData, (InvestQuoteData)
        );
        uint256 reservesAmount = IOrigamiInvestment(reserveToken).investWithNative{value: msg.value}(
            underlyingQuoteData,
            slippageBps
        );

        // Now issue shares to the user based off the `reserveAmount`
        investmentAmount = _issueSharesFromReserves(
            reservesAmount,
            msg.sender,
            applySlippage(quoteData.expectedInvestmentAmount, slippageBps)
        );
        emit Invested(msg.sender, quoteData.fromTokenAmount, address(0), investmentAmount);
    }

    /**
     * @notice Get a quote to exit out of this Origami investment vault to receive one of the accepted tokens.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param investmentAmount The number of Origami investment tokens to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return exitFeeBps Any fees expected when exiting the investment to the nominated token, either from Origami or from the underlying investment.
     */
    function exitQuote(
        uint256 investmentAmount, 
        address toToken
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
            quoteData.expectedToTokenAmount = sharesToReserves(investmentAmount);
            // quoteData.underlyingInvestmentQuoteData remains as bytes(0)
        } else {
            uint256 expectedReserveAmount = sharesToReserves(investmentAmount);
            (quoteData, exitFeeBps) = IOrigamiInvestment(reserveToken).exitQuote(
                expectedReserveAmount, toToken
            );

            // The underlyingInvestmentQuoteData also contains the expected amount of reserves such that
            // the intermediate slippage can be checked
            quoteData = ExitQuoteData({
                investmentTokenAmount: investmentAmount,
                toToken: toToken,
                expectedToTokenAmount: quoteData.expectedToTokenAmount,
                underlyingInvestmentQuoteData: abi.encode(
                    UnderlyingExitQuoteData({
                        expectedReserveAmount: expectedReserveAmount, 
                        underlyingExitQuoteData: quoteData
                    })
                )
            });
        }
    }

    /** 
      * @notice Exit out of this Origami investment vault to receive one of the accepted tokens.
      * @param quoteData The quote data received from exitQuote()
      * @param slippageBps Acceptable slippage, applied to the `quoteData` params
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the Origami investment tokens.
      */
    function exitToToken(
        ExitQuoteData calldata quoteData, 
        uint256 slippageBps, 
        address recipient
    ) external override whenNotPaused returns (
        uint256 toTokenAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // If exiting to the reserve token, redeem and send them to the user
        // Otherwise first redeem the reserve tokens and then exit the underlying Origami investment
        if (quoteData.toToken == reserveToken) {
            toTokenAmount = _redeemReservesFromShares(
                quoteData.investmentTokenAmount,
                msg.sender,
                applySlippage(quoteData.expectedToTokenAmount, slippageBps)
            );
            IERC20(reserveToken).safeTransfer(msg.sender, toTokenAmount);
        } else {
            UnderlyingExitQuoteData memory underlyingQuoteData = abi.decode(
                quoteData.underlyingInvestmentQuoteData, (UnderlyingExitQuoteData)
            );
            uint256 reserveAmount = _redeemReservesFromShares(
                quoteData.investmentTokenAmount,
                msg.sender,
                applySlippage(underlyingQuoteData.expectedReserveAmount, slippageBps)
            );

            // Update the underlying quote data with the actual amount of reserves we received.
            underlyingQuoteData.underlyingExitQuoteData.investmentTokenAmount = reserveAmount;

            // Now exchange the reserve token to the actual token the user requested.
            toTokenAmount = IOrigamiInvestment(reserveToken).exitToToken(
                underlyingQuoteData.underlyingExitQuoteData,
                slippageBps,
                recipient
            );
        }
        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);
    }

    /** 
      * @notice Sell this Origami investment to native ETH/AVAX.
      * @param quoteData The quote data received from exitQuote()
      * @param slippageBps Acceptable slippage, applied to the `quoteData` params
      * @param recipient The receiving address of the native chain token.
      * @return nativeAmount The number of native chain ETH/AVAX/etc tokens received upon selling the Origami investment tokens.
      */
    function exitToNative(
        ExitQuoteData calldata quoteData, 
        uint256 slippageBps, 
        address payable recipient
    ) external override whenNotPaused nonReentrant returns (uint256 nativeAmount) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.toToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        // Otherwise first redeem the reserve tokens and then exit the underlying Origami investment
        UnderlyingExitQuoteData memory underlyingQuoteData = abi.decode(
            quoteData.underlyingInvestmentQuoteData, (UnderlyingExitQuoteData)
        );
        uint256 reserveAmount = _redeemReservesFromShares(
            quoteData.investmentTokenAmount,
            msg.sender,
            applySlippage(underlyingQuoteData.expectedReserveAmount, slippageBps)
        );

        // Update the underlying quote data with the actual amount of reserves we received.
        underlyingQuoteData.underlyingExitQuoteData.investmentTokenAmount = reserveAmount;

        // Now exchange the reserve token to the actual token the user requested.
        nativeAmount = IOrigamiInvestment(reserveToken).exitToNative(
            underlyingQuoteData.underlyingExitQuoteData,
            slippageBps, 
            recipient
        );
        emit Exited(msg.sender, quoteData.investmentTokenAmount, address(0), nativeAmount, recipient);
    }

    /**
     * @notice Annual Percentage Rate (APR) in basis points for this investment,
     * based on the projected reward rates as of now.
     * @dev APR == [the total USD value of rewards (less fees) for one per year at current rates] / [USD value of the total shares supply]
     */
    function apr() public override view returns (uint256 aprBps) {
        uint256[] memory projectedRewardRates = investmentManager.projectedRewardRates();  // 1e18 precision
        uint256[] memory rewardTokenPricesUsd = tokenPrices.tokenPrices(investmentManager.rewardTokensList()); // 1e30 precision

        // Accumulate the USD value of rewards for the year, based on the current projected reward rates per second.
        uint256 projectedRewardsUsdPerSec;
        for (uint256 i; i < projectedRewardRates.length; ++i) {
            projectedRewardsUsdPerSec += projectedRewardRates[i] * rewardTokenPricesUsd[i];
        }
        uint256 projectedRewardsUsdPerYear = projectedRewardsUsdPerSec * 365 days; // 1e48 precision

        // Calculate the USD value of all shares
        // 1e48 precision (18 + 30)
        uint256 totalSharesUsd = 
            totalSupply() *
            tokenPrices.tokenPrice(address(this));

        aprBps = (totalSharesUsd == 0) ? 0 : 10_000 * projectedRewardsUsdPerYear / totalSharesUsd;
    }
}
