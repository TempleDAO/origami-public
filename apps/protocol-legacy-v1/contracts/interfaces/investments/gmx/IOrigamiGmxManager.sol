pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/gmx/IOrigamiGmxManager.sol)

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintableToken} from "../../common/IMintableToken.sol";
import {IOrigamiGmxEarnAccount} from "./IOrigamiGmxEarnAccount.sol";
import {IOrigamiInvestment} from "../IOrigamiInvestment.sol";

interface IOrigamiGmxManager {
    /// @notice The amount of rewards up to this block that Origami is due to distribute to users.
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX, get the reward rates for combined GMX/esGMX/mult points
    /// ie the net amount after Origami has deducted it's fees.
    function harvestableRewards(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts);

    /// @notice The current native token and oGMX reward rates per second
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX, get the reward rates for combined GMX/esGMX/mult points
    /// @dev Based on the current total Origami rewards, minus any portion of fees which we will take
    function projectedRewardRates(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts);

    /** 
     * @notice Harvest any claimable rewards up to this block from GMX.io, from the primary earn account.
     * 1/ Claimed esGMX:
     *     Vest a portion, and stake the rest -- according to `esGmxVestingRate` ratio
     *     Mint oGMX 1:1 for any esGMX that has been claimed.
     * 2/ Claimed GMX (from vested esGMX):
     *     Stake the GMX at GMX.io
     * 3/ Claimed ETH/AVAX
     *     Collect a portion as protocol fees and send the rest to the reward aggregators
     * 4/ Minted oGMX (from esGMX 1:1)
     *     Collect a portion as protocol fees and send the rest to the reward aggregators
     */
    function harvestRewards() external;

    /** 
     * @notice Claim any ETH/AVAX rewards from the secondary earn account,
     * and perpetually stake any esGMX/multiplier points.
     */
    function harvestSecondaryRewards() external;

    /// @notice The set of reward tokens we give to the rewards aggregator
    function rewardTokensList() external view returns (address[] memory tokens);

    /// @notice $GMX (GMX.io)
    function gmxToken() external view returns (IERC20);

    /// @notice $GLP (GMX.io)
    function glpToken() external view returns (IERC20);

    /// @notice $oGMX - The Origami ERC20 receipt token over $GMX
    /// Users get oGMX for initial $GMX deposits, and for each esGMX which Origami is rewarded,
    /// minus a fee.
    function oGmxToken() external view returns (IMintableToken);

    /// @notice $oGLP - The Origami ECR20 receipt token over $GLP
    /// Users get oGLP for initial $GLP deposits.
    function oGlpToken() external view returns (IMintableToken);

    /// @notice The set of accepted tokens which can be used to invest/exit into oGMX.
    function acceptedOGmxTokens() external view returns (address[] memory);

    /**
     * @notice Get a quote to buy the oGMX using GMX.
     * @param fromTokenAmount How much of GMX to invest with
     * @param fromToken This must be the address of the GMX token
     * @param maxSlippageBps The maximum acceptable slippage of the received investment amount
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return investFeeBps [GMX.io's fee when depositing with `fromToken`]
     */
    function investOGmxQuote(
        uint256 fromTokenAmount,
        address fromToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    );

    /** 
      * @notice User buys oGMX with an amount GMX.
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investOGmx(
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external returns (
        uint256 investmentAmount
    );

    /**
     * @notice Get a quote to sell oGMX to GMX.
     * @param investmentTokenAmount The amount of oGMX to sell
     * @param toToken This must be the address of the GMX token
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee]
     */
    function exitOGmxQuote(
        uint256 investmentTokenAmount, 
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    );

    /** 
      * @notice Sell oGMX to receive GMX. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the GMX
      * @return toTokenAmount The number of GMX tokens received upon selling the oGMX.
      * @return toBurnAmount The number of oGMX to be burnt after exiting this position
      */
    function exitOGmx(
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        address recipient
    ) external returns (uint256 toTokenAmount, uint256 toBurnAmount);

    /// @notice The set of whitelisted GMX.io tokens which can be used to buy GLP (and hence oGLP)
    /// @dev Native tokens (ETH/AVAX) and using staked GLP can also be used.
    function acceptedGlpTokens() external view returns (address[] memory);

    /**
     * @notice Get a quote to buy the oGLP using one of the approved tokens, inclusive of GMX.io fees.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param fromTokenAmount How much of `fromToken` to invest with
     * @param fromToken What ERC20 token to purchase with. This must be one of `acceptedInvestTokens`
     * @return quoteData The quote data, including any other quote params required for the underlying investment type. To be passed through when executing the quote.
     * @return investFeeBps [GMX.io's fee when depositing with `fromToken`]
     */
    function investOGlpQuote(
        uint256 fromTokenAmount, 
        address fromToken,
        uint256 slippageBps,
        uint256 deadline
    ) external view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    );

    /** 
      * @notice User buys oGLP with an amount of one of the approved ERC20 tokens. 
      * @param fromToken The token override to invest with. May be different from the `quoteData.fromToken`
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investOGlp(
        address fromToken,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external returns (
        uint256 investmentAmount
    );

    /**
     * @notice Get a quote to sell oGLP to receive one of the accepted tokens.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param investmentTokenAmount The amount of oGLP to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee, GMX.io's fee when selling to `toToken`]
     */
    function exitOGlpQuote(
        uint256 investmentTokenAmount, 
        address toToken,
        uint256 slippageBps,
        uint256 deadline
    ) external view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    );

    /** 
      * @notice Sell oGLP to receive one of the accepted tokens. 
      * @param toToken The token override to invest with. May be different from the `quoteData.toToken`
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the oGLP
      * @return toBurnAmount The number of oGLP to be burnt after exiting this position
      */
    function exitOGlp(
        address toToken,
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        address recipient
    ) external returns (uint256 toTokenAmount, uint256 toBurnAmount);

    struct Paused {
        bool glpInvestmentsPaused;
        bool gmxInvestmentsPaused;

        bool glpExitsPaused;
        bool gmxExitsPaused;
    }

    /// @notice Current status of whether investments/exits are paused
    function paused() external view returns (Paused memory);
}