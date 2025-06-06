pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/swappers/OrigamiSwapperWithLiquidityManagement.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";
import { IOrigamiSwapperWithLiquidityManagement } from
    "contracts/interfaces/common/swappers/IOrigamiSwapperWithLiquidityManagement.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DexAggregator } from "contracts/libraries/DexAggregator.sol";

/**
 * @title Origami Swapper with Liquidity Management
 * @notice A contract that can execute DEX aggregator swaps as well as add liquidity to arbitrary pools
 * @dev Tokens are transferred to this contract in advance of swaps being executed. Swap outputs are
 * retained in this contract until they are deposited into an LP, at which point the output tokens are
 * transferred to the designated receiver.
 * 
 * Intended to be used asynchronously:
 *  - Each deployed instance should be used by only one client contract.
 *  - onlyElevatedAccess to call execute()
 *  - The client contract sends sellToken's to this contract as it wants.
 *  - The client contract or a separate caller (elevated access) can then periodically
 *    execute the swap.
 *  - Allowed to have new residual sellToken's after the swap, the residual can be used in
 *    future swaps.
 *  - Slippage checks are performed within this execute call - slippage tolerance is encoded
 *    within the swap data.
 */
contract OrigamiSwapperWithLiquidityManagement is IOrigamiSwapperWithLiquidityManagement, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using DexAggregator for address;
    using Address for address;

    /// @inheritdoc IOrigamiSwapperWithLiquidityManagement
    mapping(address router => bool allowed) public whitelistedRouters;

    /// @inheritdoc IOrigamiSwapperWithLiquidityManagement
    IERC20 public immutable lpToken;

    constructor(address _initialOwner, address _lpToken) OrigamiElevatedAccess(_initialOwner) {
        lpToken = IERC20(_lpToken);
    }

    /// @inheritdoc IOrigamiSwapperWithLiquidityManagement
    function whitelistRouter(address router, bool allowed) external onlyElevatedAccess {
        whitelistedRouters[router] = allowed;
        emit RouterWhitelisted(router, allowed);
    }

    /// @inheritdoc IOrigamiSwapperWithLiquidityManagement
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiSwapper
    function execute(
        IERC20 sellToken,
        uint256 sellTokenAmount,
        IERC20 buyToken,
        bytes calldata swapData
    )
        external
        override
        onlyElevatedAccess
        returns (uint256 buyTokenAmount)
    {
        SwapParams memory params = abi.decode(swapData, (SwapParams));

        if (!whitelistedRouters[params.router]) revert InvalidRouter(params.router);
        
        // revertOnSurplusSellToken=false, since this function is elevated access only.
        // The internal swap route may add more sellTokens to the swapper within the swap route
        // (eg compounding rewards on mint/redeem)
        buyTokenAmount = params.router.swap(sellToken, sellTokenAmount, buyToken, params.swapData, false);

        uint256 minBuyAmount = params.minBuyAmount;
        if (buyTokenAmount < minBuyAmount) revert CommonEventsAndErrors.Slippage(minBuyAmount, buyTokenAmount);

        emit Swap(address(sellToken), sellTokenAmount, address(buyToken), buyTokenAmount);
    }

    /// @inheritdoc IOrigamiSwapperWithLiquidityManagement
    function addLiquidity(
        TokenAmount[] calldata tokenAmounts,
        bytes calldata addLiquidityParams
    )
        external
        override
        onlyElevatedAccess
        returns (uint256 receivedLpAmount)
    {
        AddLiquidityParams memory params = abi.decode(addLiquidityParams, (AddLiquidityParams));
        address liquidityRouter = params.liquidityRouter;

        if (!whitelistedRouters[liquidityRouter]) revert InvalidRouter(liquidityRouter);

        uint256 initialLpBalance = lpToken.balanceOf(address(this));

        // Approve tokens to the liquidityRouter
        for (uint256 i; i < tokenAmounts.length; ++i) {
            if (tokenAmounts[i].amount > 0) {
                IERC20(tokenAmounts[i].token).forceApprove(liquidityRouter, tokenAmounts[i].amount);
            }
        }

        liquidityRouter.functionCall(params.callData);

        // Check minimum LP amount received
        receivedLpAmount = lpToken.balanceOf(address(this)) - initialLpBalance;
        if (receivedLpAmount < params.minLpOutputAmount) {
            revert CommonEventsAndErrors.Slippage(params.minLpOutputAmount, receivedLpAmount);
        }

        // Transfer LP tokens to the receiver
        lpToken.safeTransfer(params.receiver, receivedLpAmount);
        IOrigamiSwapCallback(params.receiver).swapCallback();
    }

    /// @inheritdoc IOrigamiSwapperWithLiquidityManagement
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
    }
}
