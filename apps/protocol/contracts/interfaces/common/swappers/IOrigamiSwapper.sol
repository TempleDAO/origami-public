pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/swappers/IOrigamiSwapper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice An on chain swapper contract to integrate with the 1Inch router | 0x proxy, 
 * possibly others which obtain quote calldata offchain and then execute via a low level call
 * to perform the swap onchain
 */
interface IOrigamiSwapper {
    error InvalidSwap();
    error InvalidRouter(address router);

    event Swap(address indexed sellToken, uint256 sellTokenAmount, address indexed buyToken, uint256 buyTokenAmount);
    event RouterWhitelisted(address indexed router, bool allowed);

    struct RouteDataWithCallback {
        address router;
        uint256 minBuyAmount;
        address receiver;
        bytes data;
    }

    /**
     * @notice Execute the swap per the instructions in `swapData`
     * @dev Implementations MAY require `sellToken` to be transferred to the swapper contract prior to execution
     */
    function execute(
        IERC20 sellToken, 
        uint256 sellTokenAmount, 
        IERC20 buyToken,
        bytes memory swapData
    ) external returns (uint256 buyTokenAmount);
}
