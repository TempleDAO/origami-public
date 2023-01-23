pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/gmx/IOrigamiGmxManager.sol)

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintableToken} from "../../common/IMintableToken.sol";
import {IOrigamiGmxEarnAccount} from "./IOrigamiGmxEarnAccount.sol";
import {IOrigamiInvestment} from "../IOrigamiInvestment.sol";

interface IOrigamiGmxManager {
    function harvestableRewards(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts);
    function projectedRewardRates(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts);
    function harvestRewards() external;
    function harvestSecondaryRewards() external;
    function rewardTokensList() external view returns (address[] memory tokens);
    function gmxToken() external view returns (IERC20);
    function glpToken() external view returns (IERC20);
    function oGmxToken() external view returns (IMintableToken);
    function oGlpToken() external view returns (IMintableToken);

    function acceptedOGmxTokens() external view returns (address[] memory);
    function investOGmxQuote(
        uint256 fromTokenAmount,
        address fromToken
    ) external view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    );
    function investOGmx(
        IOrigamiInvestment.InvestQuoteData calldata quoteData, 
        uint256 slippageBps
    ) external returns (
        uint256 investmentAmount
    );
    function exitOGmxQuote(
        uint256 investmentTokenAmount, 
        address toToken
    ) external view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    );
    function exitOGmx(
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256 slippageBps, 
        address recipient
    ) external returns (uint256 toTokenAmount, uint256 toBurnAmount);

    function acceptedGlpTokens() external view returns (address[] memory);
    function investOGlpQuote(
        uint256 fromTokenAmount, 
        address fromToken
    ) external view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    );
    function investOGlp(
        address fromToken,
        IOrigamiInvestment.InvestQuoteData calldata quoteData, 
        uint256 slippageBps
    ) external returns (
        uint256 investmentAmount
    );
    function exitOGlpQuote(
        uint256 investmentTokenAmount, 
        address toToken
    ) external view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    );
    function exitOGlp(
        address toToken,
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256 slippageBps, 
        address recipient
    ) external returns (uint256 toTokenAmount, uint256 toBurnAmount);

    struct Paused {
        bool glpInvestmentsPaused;
        bool gmxInvestmentsPaused;

        bool glpExitsPaused;
        bool gmxExitsPaused;
    }
    function paused() external view returns (Paused memory);
}