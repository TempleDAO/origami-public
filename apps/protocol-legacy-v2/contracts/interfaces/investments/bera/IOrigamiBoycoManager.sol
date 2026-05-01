pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/bera/IOrigamiBoycoManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiBalancerPoolHelper } from "contracts/interfaces/common/balancer/IOrigamiBalancerPoolHelper.sol";

import { IOrigamiBeraRewardsVaultProxy } from "contracts/interfaces/common/bera/IOrigamiBeraRewardsVaultProxy.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";

/**
 * @title Origami Boyco Manager
 * @notice Handles USDC deposits and orchestrating the farming of (i)BGT
 */
interface IOrigamiBoycoManager is IOrigamiDelegated4626VaultManager {
    error NotEnoughUsdc(uint256 available, uint256 requested);

    event BexPoolHelperSet(address bexPoolHelper);
    event BeraRewardsVaultProxySet(address beraRewardsVaultProxy);
    event LiquidityDeployed(uint256 vaultAssetAmount, address depositToken, uint256 depositTokenAmount, uint256 lpAmount);
    event LiquidityRecalled(uint256 vaultAssetAmount, address exitToken, uint256 exitTokenAmount, uint256 lpAmount);

    /**
     * @notice Set Origami contract responsible for staking and claiming (i)BGT
     */
    function setBeraRewardsVaultProxy(address _beraRewardsVaultProxy) external;

    /**
     * @notice Set the Bera BEX contract to aid in adding/removing liquidity
     */
    function setBexPoolHelper(address _bexPoolHelper) external;

    /**
     * @notice Deploy an asset into a Rewards Vault by:
     *   - Converting USDC to the asset token
     *   - Joining the BEX pool and receiving LP tokens
     *   - Staking the received LP into the RewardsVault
     */
    function deployLiquidity(
        address depositToken,
        uint256 depositAmount,
        IBalancerVault.JoinPoolRequest calldata requestData
    ) external;

    /**
     * @notice Recall an asset from an LP Rewards Vault by:
     *   - Unstaking that LP from the RewardsVault
     *   - Redeeming the LP for the exit token
     *   - Consolidating the exit token back to USDC
     */
    function recallLiquidity(
        uint256 lpTokenAmount,
        address exitToken,
        IBalancerVault.ExitPoolRequest calldata requestData
    ) external;

    /**
     * @notice The USDC ERC20 token
     */
    function usdcToken() external view returns (IERC20);

    /**
     * @notice The Bera BEX contract to aid in adding/removing liquidity
     */
    function bexPoolHelper() external view returns (IOrigamiBalancerPoolHelper);

    /**
     * @notice The Bera BEX receipt token for liquidity
     */
    function bexLpToken() external view returns (IERC20);

    /**
     * @notice The Origami contract responsible for staking and claiming (i)BGT
     */
    function beraRewardsVaultProxy() external view returns (IOrigamiBeraRewardsVaultProxy);

    /**
     * @notice The amount of LP tokens currently staked earning (i)BGT rewards
     */
    function lpBalanceStaked() external view returns (uint256);

    /**
     * @notice The current balances of tokens deposited in the BEX pool
     */
    function bexTokenBalances() external view returns (uint256[] memory);

    /**
     * @notice The amount of USDC currently available (unallocated) for redemptions
     */
    function unallocatedAssets() external view returns (uint256);

    /**
     * @notice Get a quote and request data for deploying an amount of the specified deposit token into BEX
     * @dev Required to be a non-view function for BalancerQueries integration. Clients should ensure to use "callStatic"
     */
    function deployLiquidityQuote(
        address depositToken,
        uint256 depositAmount,
        uint256 slippageBps
    ) external returns (
        uint256 expectedLpTokenAmount,
        uint256 minLpTokenAmount,
        IBalancerVault.JoinPoolRequest memory requestData
    );

    /**
     * @notice Get a quote and request data for recalling an amount of BEX LP tokens to the specified exit token
     * @dev Required to be a non-view function for BalancerQueries integration. Clients should ensure to use "callStatic"
     */
    function recallLiquidityQuote(
        uint256 bexLpAmount,
        address exitToken,
        uint256 slippageBps
    ) external returns (
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts,
        IBalancerVault.ExitPoolRequest memory requestData
    );
}
