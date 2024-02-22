pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/swappers/IOrigamiSwapper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice An on chain swapper contract to integrate with the 1Inch router | 0x proxy, 
 * possibly others which obtain quote calldata offchain and then execute via a low level call
 * to perform the swap onchain
 */
interface IOrigamiSwapper {
    error UnknownSwapError(bytes result);
    error InvalidSwap();

    event Swap(address indexed sellToken, uint256 sellTokenAmount, address indexed buyToken, uint256 buyTokenAmount);

    /**
     * @notice Pull tokens from sender then execute the swap
     */
    function execute(
        IERC20 sellToken, 
        uint256 sellTokenAmount, 
        IERC20 buyToken,
        bytes memory swapData
    ) external returns (uint256 buyTokenAmount);
}
