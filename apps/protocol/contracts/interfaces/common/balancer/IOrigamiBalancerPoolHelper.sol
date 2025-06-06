pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/balancer/IOrigamiBalancerPoolHelper.sol)

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

/**
 * @title Balancer Pool Helper
 * @notice A contract to aid adding/removing liquidity into a Balancer Pool
 */
interface IOrigamiBalancerPoolHelper {
    error QueryFailed(bytes revertData);
    error InvalidPool();
    error InvalidJoinKind();
    error InvalidExitKind();
    error InvalidTokenIndex();

    /// @notice The Balancer vault singleton
    function balancerVault() external view returns (IBalancerVault);

    /// @notice The Balancer 'Queries' peripheral contract
    function balancerQueries() external view returns (IBalancerQueries);

    /// @notice The Balancer pool ID
    function poolId() external view returns (bytes32);

    /// @notice The Balancer BPT token representing this pool
    function lpToken() external view returns (IBalancerBptToken);

    /// @notice Retrieve the tokens in the pool.
    /// Tokens are returned in the order that they should be provided to the methods on this helper
    /// (i.e. sorted numerically by address)
    function poolTokens() external view returns (address[] memory);

    /// @notice Retrieve the current balance of tokens in the pool (sorted numerically by address)
    function poolBalances() external view returns (uint256[] memory balances);

    /**
     * @notice Given an amount of LP (aka BPT), calculate the proportional balances of each token.
     * @dev The token amounts are returned in the order of tokens in the pool (i.e. sorted numerically by address)
     * and includes the BPT balance.
     * Calculated by pulling the total balances of each token in the pool and applying the lpTokenBalance 
     * proportion vs the total supply
     */
    function tokenAmountsForLpTokens(uint256 bptAmount) external view returns (
        uint256[] memory tokenAmounts
    );

    /**
     * @notice Get a quote to add liquidity to the Balancer pool. `requestData` can be passed to `addLiquidity` to execute the join.
     * @dev Required to be a non-view function for BalancerQueries integration. Clients should ensure to use "callStatic"
     */
    function addLiquidityQuote(
        uint256 joinTokenIndex,
        uint256 joinTokenAmount,
        uint256 slippageBps
    ) external returns (
        uint256[] memory tokenAmounts,
        uint256 expectedLpTokenAmount,
        uint256 minLpTokenAmount,
        IBalancerVault.JoinPoolRequest memory requestData
    );

    /**
     * @notice Add liquidity to the Balancer pool given an amount of the asset token(s) to deposit
     * Uses the join mode specified by requestData populated from `proportionalAddLiquidityQuote`.
     * @dev The token(s) are pulled from the caller and must be pre-approved to this contract. Clients should use `tokenAmounts`
     * returned from `proportionalAddLiquidityQuote` to determine the minimum amounts to approve.
     */
    function addLiquidity(
        address recipient,
        IBalancerVault.JoinPoolRequest calldata requestData
    ) external;

    /**
     * @notice Get a quote to remove liquidity from the Balancer pool given an amount of LP token (BPT) to remove. `requestData` can be passed to `removeLiquidity` to execute the exit.
     * @dev Required to be a non-view function for BalancerQueries integration. Clients should ensure to use "callStatic"
     * Token amounts will be returned for all tokens in the pool (in sorted order), including the BPT.
     */
    function removeLiquidityQuote(
        uint256 exitTokenIndex,
        uint256 bptAmount,
        uint256 slippageBps
    ) external returns (
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts,
        IBalancerVault.ExitPoolRequest memory requestData
    );

    /**
     * @notice Remove liquidity from the Balancer pool given an amount of LP token (BPT) to exit
     * using the mode specified by requestData from `proportionalRemoveLiquidityQuote`.
     */
    function removeLiquidity(
        uint256 bptAmount,
        address recipient,
        IBalancerVault.ExitPoolRequest calldata requestData
    ) external;
}
