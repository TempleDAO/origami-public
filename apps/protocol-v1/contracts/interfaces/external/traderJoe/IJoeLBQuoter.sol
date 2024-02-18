
pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/traderJoe/IJoeLBQuoter.sol)

interface IJoeLBQuoter {
    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint256[] amounts;
        uint256[] virtualAmountsWithoutSlippage;
        uint256[] fees;
    }

    /// @notice Finds the best path given a list of tokens and the input amount wanted from the swap
    /// @param _route List of the tokens to go through
    /// @param _amountIn Swap amount in
    /// @return quote The Quote structure containing the necessary element to perform the swap
    function findBestPathFromAmountIn(address[] calldata _route, uint256 _amountIn)
        external
        view
        returns (Quote memory quote);

    /// @notice Finds the best path given a list of tokens and the output amount wanted from the swap
    /// @param _route List of the tokens to go through
    /// @param _amountOut Swap amount out
    /// @return quote The Quote structure containing the necessary element to perform the swap
    function findBestPathFromAmountOut(address[] calldata _route, uint256 _amountOut)
        external
        view
        returns (Quote memory quote);
}