pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/swappers/IOrigamiSwapperWithLiquidityManagement.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

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
interface IOrigamiSwapperWithLiquidityManagement is IOrigamiSwapper {
    /**
     * @notice The parameters used to execute a DEX aggregator swap
     * @dev swapData is passed to the router and is an abi-encoded function call dependent on the router implementation
     */
    struct SwapParams {
        address router;
        uint256 minBuyAmount;
        bytes swapData;
    }

    /**
     * @notice The parameters used to add liquidity to a liquidity pool
     * @dev callData is passed to the liquidity router and is an abi-encoded function call dependent on the router
     * implementation
     */
    struct AddLiquidityParams {
        address liquidityRouter;
        address receiver;
        uint256 minLpOutputAmount;
        bytes callData;
    }

    /**
     * @notice The LP token that this swapper integrates with
     */
    function lpToken() external view returns (IERC20);

    /**
     * @notice Approved routers for swaps and adding liquidity
     */
    function whitelistedRouters(address router) external view returns (bool);

    /**
     * @notice Set whether a router is whitelisted for swaps and adding liquidity
     * @param router The router address to whitelist
     * @param allowed Whether the router is allowed
     */
    function whitelistRouter(address router, bool allowed) external;

    /**
     * @notice Recover any token
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external;

    struct TokenAmount {
        address token;
        uint256 amount;
    }

    /**
     * @notice Add liquidity to a liquidity pool using instructions encoded in `addLiquidityParams`
     * @param tokenAmounts Array of token addresses and amounts to add as liquidity
     * @param addLiquidityParams Deposit parameters encoded as a `DepositParams` struct
     * @return receivedLpAmount The amount of LP tokens received
     */
    function addLiquidity(
        TokenAmount[] calldata tokenAmounts,
        bytes calldata addLiquidityParams
    )
        external
        returns (uint256 receivedLpAmount);

    /**
     * @notice Execute a batch of function calls on this contract
     * @param data Array of encoded function calls to execute
     * @return results Array of results from the swaps
     * @dev Calls are made using DELEGATECALL
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
