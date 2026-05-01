pragma solidity >=0.8.0 <0.9.0;
// SPDX-License-Identifier: MIT

// @note Used by watchtower: https://github.com/cowprotocol/watch-tower/blob/90ecbf5de87447657a36dfcd49a714b1b5105380/src/utils/contracts.ts#L93

/**
 * @title Watchtower Errors Interface
 * @dev Different error messages lead to different watchtower behaviors when creating
 * an order via `getTradeableOrderWithSignature()`
 * @dev The watchtower is a service that automatically posts orders to the CoW
 * Protocol orderbook at regular intervals.
 */
interface IWatchtowerErrors {
    /**
     * @notice No order is currently available for trading, but the watchtower should
     * try again at the specified block.
     */
    error PollTryAtBlock(uint256 blockNumber, string message);

    /**
     * @notice No order is currently available for trading, but the watchtower should
     * try again after the timestamp.
     */
    error PollTryAtEpoch(uint256 timestamp, string message);

    /**
     * @notice No order is currently available for trading, and do not retry this conditional order again.
     * A new ConditionalOrderCreated event will need to be emitted in order to
     * trigger watchtower to monitor this contract again.
     */
    error OrderNotValid(string reason);
}
