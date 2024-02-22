pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

contract DummyLovTokenSwapper is IOrigamiSwapper {
    using SafeERC20 for IERC20;

    /// @dev for dummy swapper, caller decides the rate :-)
    struct SwapData {
        uint256 buyTokenAmount;
    }

    /**
     * @notice Assumes this dummy swapper is pre-funded
     */
    function execute(
        IERC20 sellToken, 
        uint256 sellTokenAmount, 
        IERC20 buyToken, 
        bytes memory swapData
    ) external returns (uint256 buyTokenAmount) {
        SwapData memory data = abi.decode(
            swapData, (SwapData)
        );

        buyTokenAmount = data.buyTokenAmount;
        sellToken.safeTransferFrom(msg.sender, address(this), sellTokenAmount);
        buyToken.safeTransfer(msg.sender, data.buyTokenAmount);
    }
}
