pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/swappers/IOrigamiSwapCallback.sol)

/**
 * @notice Interface to support callbacks when using the OrigamiSwapperWithCallback
 * contract
 */
interface IOrigamiSwapCallback {
    /// @notice Permisionless function which is called at the conclusion of a swap, 
    /// on the msg.sender of OrigamiSwapperWithCallback.execute()
    /// @dev The swap may be synchronous or asynchronous. The buyToken proceeds from 
    /// the swap are sent to the msg.sender prior to this callback being called.
    /// The buyToken amount may not be known as part of this callback (eg cowswap hooks)
    /// so it is not passed through. The implementation should rely on their current balance instead
    function swapCallback() external;
}
