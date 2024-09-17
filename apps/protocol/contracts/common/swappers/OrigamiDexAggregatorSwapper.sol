pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/swappers/OrigamiDexAggregatorSwapper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DexAggregator } from "contracts/libraries/DexAggregator.sol";

/**
 * @notice An on chain swapper contract to integrate with the 1Inch router | 0x proxy, 
 * possibly others which obtain quote calldata offchain and then execute via a low level call
 * to perform the swap onchain.
 * @dev The amount of tokens bought is expected to be checked for slippage in the calling contract
 */
contract OrigamiDexAggregatorSwapper is IOrigamiSwapper, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using DexAggregator for address;

    struct RouteData {
        address router;
        bytes data;
    }

    /// @notice Approved router contracts for swaps
    mapping(address router => bool allowed) public whitelistedRouters;

    constructor(
        address _initialOwner
    ) OrigamiElevatedAccess(_initialOwner) {
    }

    function whitelistRouter(address router, bool allowed) external onlyElevatedAccess {
        whitelistedRouters[router] = allowed;
        emit RouterWhitelisted(router, allowed);
    }

    /**
     * @notice Recover any token -- this contract should not ordinarily hold any tokens.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Execute a DEX aggregator swap
     */
    function execute(
        IERC20 sellToken, 
        uint256 sellTokenAmount, 
        IERC20 buyToken, 
        bytes calldata swapData
    ) external override returns (uint256 buyTokenAmount) {
        sellToken.safeTransferFrom(msg.sender, address(this), sellTokenAmount);

        RouteData memory routeData = abi.decode(
            swapData, (RouteData)
        );

        if (!whitelistedRouters[routeData.router]) revert InvalidRouter(routeData.router);

        buyTokenAmount = routeData.router.swap(sellToken, sellTokenAmount, buyToken, routeData.data);

        // Transfer back to the caller
        buyToken.safeTransfer(msg.sender, buyTokenAmount);
        emit Swap(address(sellToken), sellTokenAmount, address(buyToken), buyTokenAmount);
    }
}
