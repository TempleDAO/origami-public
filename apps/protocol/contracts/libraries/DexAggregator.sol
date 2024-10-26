pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/DexAggregator.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @notice Execute a swap on a DEX Aggregator such as 1inch, 0x
 * and ensure token balances are updated
 */
library DexAggregator {
    using SafeERC20 for IERC20;

    error UnknownSwapError(bytes result);

    /**
     * @notice Execute a swap using a 1inch/0x Dex aggregator
     * @dev There must be no sellToken's remaining after the swap
     * @dev The buyToken must have a non-zero balance after the swap
     */
    function swap(
        address router,
        IERC20 sellToken,
        uint256 sellTokenAmount, 
        IERC20 buyToken,
        bytes memory swapData
    ) internal returns (uint256 buyTokenAmount) {
        if (sellTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        (uint256 _initialSellTokenBalance, uint256 _initialBuyTokenBalance) = (
            sellToken.balanceOf(address(this)),
            buyToken.balanceOf(address(this))
        );

        // Approve the router to pull the sellToken's
        sellToken.forceApprove(router, sellTokenAmount);

        // Execute via a low-level call on the dex aggregator router.
        (bool _success, bytes memory _returndata) = router.call(swapData);
        if (!_success) {
            if (_returndata.length != 0) {
                // Look for revert reason and bubble it up if present
                // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol#L232
                assembly {
                    let returndata_size := mload(_returndata)
                    revert(add(32, _returndata), returndata_size)
                }
            }
            revert IOrigamiSwapper.UnknownSwapError(_returndata);
        }

        unchecked {
            // Safe unchecked because the swap would have pulled the sellTokenAmount tokens
            _initialSellTokenBalance = _initialSellTokenBalance - sellTokenAmount;
        }

        // The caller's balance of sellToken must end up at the same value as before the swap
        if (sellToken.balanceOf(address(this)) != _initialSellTokenBalance) revert IOrigamiSwapper.InvalidSwap();

        buyTokenAmount = buyToken.balanceOf(address(this)) - _initialBuyTokenBalance;

        // Must have a non-zero amount of buyToken's
        if (buyTokenAmount == 0) revert IOrigamiSwapper.InvalidSwap();
    }
}
