pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/curve/ICurveStableSwapNG.sol)

interface ICurveStableSwapNG {
    /**
     * @notice Return the number of tokens in this stable swap
     */
    function N_COINS() external view returns (uint256);

    /**
     * @notice Return the address of token at position i
     */
    function coins(uint256 i) external view returns (address);

    /**
     * @notice Function to calculate the exponential moving average (EMA) price for the coin at index
     * i+1 with regard to the coin at index 0. The calculation is based on the last spot 
     * value (last_price), the last ma value (ema_price), the moving average time 
     * window (ma_exp_time), and on the difference between the current timestamp (block.timestamp) 
     * and the timestamp when the ma oracle was last updated (unpacks from the first value of ma_last_time).
     * i = 0 will return the price oracle of coin[1], i = 1 the price oracle of coin[2], and so on.
     * @param i Index value of the coin to calculate the EMA price for. i = 0 returns the price oracle for coin(1).
     * @return price EMA price of coin i.
     */
    function price_oracle(uint256 i) external view returns (uint256 price);
}
