pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/kyberswap/IKyberScalingHelper.sol)

interface IKyberScalingHelper {
    /// @dev Update the kyberswap input calldata to scale it to the new
    /// amount of input tokens to sell
    function getScaledInputData(bytes calldata inputData, uint256 newAmount)
        external
        view
        returns (bool isSuccess, bytes memory data);
}
