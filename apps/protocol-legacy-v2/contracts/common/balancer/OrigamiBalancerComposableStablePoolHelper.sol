pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/balancer/OrigamiBalancerComposableStablePoolHelper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";
import { IOrigamiBalancerPoolHelper } from "contracts/interfaces/common/balancer/IOrigamiBalancerPoolHelper.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/**
 * @title Balancer Composable Stable Pool Helper
 * @notice A contract to aid adding/removing liquidity into a Balancer Composable Stable Pool
 * using a single join/exit token.
 * If the assets in the pool change over time (very unlikely), this contract will require a redeployment.
 */
contract OrigamiBalancerComposableStablePoolHelper is OrigamiElevatedAccess, IOrigamiBalancerPoolHelper {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBalancerBptToken;
    using OrigamiMath for uint256;
    
    /// @inheritdoc IOrigamiBalancerPoolHelper
    IBalancerVault public override immutable balancerVault;

    /// @inheritdoc IOrigamiBalancerPoolHelper
    IBalancerQueries public override immutable balancerQueries;

    /// @inheritdoc IOrigamiBalancerPoolHelper
    bytes32 public override immutable poolId;

    /// @inheritdoc IOrigamiBalancerPoolHelper
    IBalancerBptToken public override immutable lpToken;

    /// @notice The index of the BPT token in the pool
    uint256 public immutable bptIndex;

    /// @dev Join providing one token https://github.com/balancer/balancer-v2-monorepo/blob/36d282374b457dddea828be7884ee0d185db06ba/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L18
    uint8 private constant _EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

    /// @dev Exit to one token https://github.com/balancer/balancer-v2-monorepo/blob/36d282374b457dddea828be7884ee0d185db06ba/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L19
    uint8 private constant _EXACT_BPT_IN_FOR_ONE_TOKEN_OUT = 0;

    constructor(
        address initialOwner_,
        address balancerVault_,
        address balancerQueries_,
        bytes32 poolId_
    ) 
        OrigamiElevatedAccess(initialOwner_)
    {
        balancerVault = IBalancerVault(balancerVault_);
        balancerQueries = IBalancerQueries(balancerQueries_);
        poolId = poolId_;

        (address lpTokenAddr,) = balancerVault.getPool(poolId);
        lpToken = IBalancerBptToken(lpTokenAddr);
        bptIndex = lpToken.getBptIndex();
    }

    /// @inheritdoc IOrigamiBalancerPoolHelper
    function poolTokens() public override view returns (address[] memory addresses) {
        (addresses,,) = balancerVault.getPoolTokens(poolId);
    }

    /// @inheritdoc IOrigamiBalancerPoolHelper
    function poolBalances() public override view returns (uint256[] memory balances) {
        (,balances,) = balancerVault.getPoolTokens(poolId);
    }

    /// @inheritdoc IOrigamiBalancerPoolHelper
    function tokenAmountsForLpTokens(uint256 bptAmount) external override view returns (
        uint256[] memory tokenAmounts
    ) {
        uint256[] memory tokenBalances = poolBalances();
        tokenAmounts = new uint256[](tokenBalances.length);

        // Use `bpt.getActualSupply()` instead of `bpt.totalSupply()`
        // https://docs-v2.balancer.fi/reference/lp-tokens/underlying.html#overview
        // https://docs-v2.balancer.fi/concepts/advanced/valuing-bpt/valuing-bpt.html#on-chain
        uint256 bptTotalSupply = lpToken.getActualSupply();
        if (bptTotalSupply != 0) {
            // Populate the proportional output tokenAmounts
            for (uint256 i; i < tokenBalances.length; ++i) {
                tokenAmounts[i] = bptAmount.mulDiv(tokenBalances[i], bptTotalSupply, OrigamiMath.Rounding.ROUND_DOWN);
            }
        }
    }

    /// Get a quote to join the pool by adding single-sided liquidity of the token specified by `joinAndExitTokenIndex`
    /// @inheritdoc IOrigamiBalancerPoolHelper
    function addLiquidityQuote(
        uint256 joinTokenIndex,
        uint256 joinTokenAmount,
        uint256 slippageBps
    ) external override returns (
        uint256[] memory tokenAmounts,
        uint256 expectedLpTokenAmount,
        uint256 minLpTokenAmount,
        IBalancerVault.JoinPoolRequest memory requestData
    ) {
        if (joinTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        address[] memory tokenAddresses = poolTokens();
        if (joinTokenIndex == bptIndex) revert CommonEventsAndErrors.InvalidToken(tokenAddresses[joinTokenIndex]);

        // Always use external balances
        requestData.fromInternalBalance = false;

        // Populate the assets
        uint256 _numTokens = tokenAddresses.length;
        requestData.assets = new address[](_numTokens);
        for (uint256 i; i < tokenAddresses.length; ++i) {
            requestData.assets[i] = tokenAddresses[i];
        }

        // Populate the the token to be added
        tokenAmounts = new uint256[](_numTokens);
        tokenAmounts[joinTokenIndex] = joinTokenAmount;
        requestData.maxAmountsIn = new uint256[](_numTokens);
        requestData.maxAmountsIn[joinTokenIndex] = joinTokenAmount;

        // User data specific to ExactTokensInForBptOut
        {
            // userData amounts do not include the BPT token
            uint256[] memory udAmountsIn = new uint256[](_numTokens-1);
            for (uint256 i; i < _numTokens; ++i) {
                if (i == bptIndex) continue;
                udAmountsIn[_skipBptIndex(i)] = tokenAmounts[i];
            }

            // Encoded as: JoinKind, amountsIn, minBPTAmountOut
            requestData.userData = abi.encode(_EXACT_TOKENS_IN_FOR_BPT_OUT, udAmountsIn, 0);

            // Query the expected BPT given the inputs. 
            (expectedLpTokenAmount, ) = balancerQueries.queryJoin({
                poolId: poolId, 
                sender: address(0), // No effect on quote
                recipient: address(0), // No effect on quote
                request: requestData
            });

            // Apply slippage
            minLpTokenAmount = expectedLpTokenAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_DOWN);

            // Now update `requestData` with the `minLpTokenAmount` (with slippage applied)
            requestData.userData = abi.encode(_EXACT_TOKENS_IN_FOR_BPT_OUT, udAmountsIn, minLpTokenAmount);
        }
    }

    /// @inheritdoc IOrigamiBalancerPoolHelper
    function addLiquidity(
        address recipient,
        IBalancerVault.JoinPoolRequest calldata requestData
    ) external override {
        if (requestData.fromInternalBalance) revert CommonEventsAndErrors.InvalidParam();

        // Ensure it's of the right join kind (which leaves no surplus tokens at the end)
        uint8 joinKind = abi.decode(requestData.userData, (uint8));
        if (joinKind != _EXACT_TOKENS_IN_FOR_BPT_OUT) revert InvalidJoinKind();

        if (requestData.maxAmountsIn[bptIndex] != 0) {
            revert CommonEventsAndErrors.InvalidParam();
        }

        uint256 _numAssets = requestData.assets.length;
        for (uint256 i; i < _numAssets; ++i) {
            pullAndApproveToBalancer(IERC20(requestData.assets[i]), requestData.maxAmountsIn[i]);
        }

        // Join the pool
        balancerVault.joinPool(poolId, address(this), recipient, requestData);
    }

    /**
     * @dev Pull in the tokens and approve the balancer vault. Skips the BPT where amount will be 0.
     */
    function pullAndApproveToBalancer(IERC20 token, uint256 amount) private {
        if (amount > 0) {
            token.safeTransferFrom(msg.sender, address(this), amount);
            token.forceApprove(address(balancerVault), amount);
        }
    }

    /// @inheritdoc IOrigamiBalancerPoolHelper
    function removeLiquidityQuote(
        uint256 exitTokenIndex,
        uint256 bptAmount,
        uint256 slippageBps
    ) external override returns (
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts,
        IBalancerVault.ExitPoolRequest memory requestData
    ) {
        if (bptAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        address[] memory tokenAddresses = poolTokens();
        if (exitTokenIndex == bptIndex) revert CommonEventsAndErrors.InvalidToken(tokenAddresses[exitTokenIndex]);

        // Always use external balances
        requestData.toInternalBalance = false;

        // Populate the assets
        uint256 _numTokens = tokenAddresses.length;
        requestData.assets = new address[](_numTokens);
        uint256 i;
        for (; i < _numTokens; ++i) {
            requestData.assets[i] = tokenAddresses[i];
        }

        // User data specific to ExactBptInForOneTokenOut
        // https://github.com/balancer/balancer-v2-monorepo/blob/e16fad44b29199778b0104f3bf6d402b16cc1ea9/pkg/pool-stable/contracts/ComposableStablePool.sol#L862
        // Encoded as: ExitKind, bptAmountIn, exitTokenIndex
        bytes memory encodedUserdata = abi.encode(_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmount, exitTokenIndex);
        requestData.userData = encodedUserdata;

        // Query the expected amounts out given the inputs.
        (, expectedTokenAmounts) = balancerQueries.queryExit(
            poolId,
            address(0),  // No effect on quote
            address(0),  // No effect on quote
            requestData
        );

        // Apply slippage
        minTokenAmounts = new uint256[](_numTokens);
        for (i = 0; i < _numTokens; ++i) {
            minTokenAmounts[i] = expectedTokenAmounts[i] == 0 
                ? 0 
                : expectedTokenAmounts[i].subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_DOWN);
        }

        // update `requestData` with the `minAmountsOut` (with slippage applied)
        requestData.minAmountsOut = minTokenAmounts;
    }

    /// @inheritdoc IOrigamiBalancerPoolHelper
    function removeLiquidity(
        uint256 bptAmount,
        address recipient,
        IBalancerVault.ExitPoolRequest calldata requestData
    ) external override {
        if (requestData.toInternalBalance) revert CommonEventsAndErrors.InvalidParam();

        // Ensure it's of the right exit kind
        (uint8 exitKind, uint256 encodedBptAmount) = abi.decode(requestData.userData, (uint8, uint256));
        if (exitKind != _EXACT_BPT_IN_FOR_ONE_TOKEN_OUT) revert InvalidExitKind();
        if (encodedBptAmount != bptAmount) revert CommonEventsAndErrors.InvalidAmount(address(lpToken), bptAmount);

        // Pull in LP token then exit
        // NB: BPT token doesn't need an allowance set within the Balancer vault.
        lpToken.safeTransferFrom(msg.sender, address(this), bptAmount);
        balancerVault.exitPool(poolId, address(this), recipient, requestData);
    }

    /// @notice Recover ERC20 tokens.
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    function _skipBptIndex(uint256 index) private view returns (uint256) {
        return index < bptIndex ? index : index - 1;
    }
}
