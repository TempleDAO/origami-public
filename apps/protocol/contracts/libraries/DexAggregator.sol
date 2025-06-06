pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/DexAggregator.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @notice Execute a swap on a DEX Aggregator such as 1inch, 0x
 * and ensure token balances are updated
 */
library DexAggregator {
    using SafeERC20 for IERC20;
    using Address for address;

    /**
     * @notice Execute a swap using a 1inch/0x Dex aggregator
     * @dev 
     *   - Assumes this contract already has sellTokenAmount amount, but not yet given approval
     *     to the router.
     *   - The balance of sellToken after the swap can never be less than before the swap
     *   - If `revertOnSurplusSellToken` is true, then the balance of sellToken after the swap
     *     must exactly match the initial balance minus the `sellTokenAmount.
     *     This may be true if the internal swap either doesn't take as many tokens or the swap
     *     route has other side effects (eg auto compounding into more rewards being sent to the swapper)
     *   - If false, then the balance of sellToken may allowed to be greater than before the swap.
     *     This is only to be used when the calling contract has gated access only on this function,
     *     otherwise the residual amounts could be drained by other accounts.
     *   - The buyToken balance must increase with the swap
     */
    function swap(
        address router,
        IERC20 sellToken,
        uint256 sellTokenAmount, 
        IERC20 buyToken,
        bytes memory swapData,
        bool revertOnSurplusSellToken
    ) internal returns (uint256 buyTokenAmount) {
        if (sellTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        (uint256 _initialSellTokenBalance, uint256 _initialBuyTokenBalance) = (
            sellToken.balanceOf(address(this)),
            buyToken.balanceOf(address(this))
        );

        // Approve the router to pull the sellToken's
        sellToken.forceApprove(router, sellTokenAmount);

        // Execute via a low-level call on the router.
        router.functionCall(swapData);

        // Revert if it has less sellTokens than expected
        // or if there's a surplus of sellTokens and the caller choses not to allow that.
        uint256 _finalSellTokenBalance = sellToken.balanceOf(address(this));
        uint256 _expectedSellTokenBalance = _initialSellTokenBalance - sellTokenAmount;
        if (
            _finalSellTokenBalance < _expectedSellTokenBalance ||
            revertOnSurplusSellToken && _finalSellTokenBalance > _expectedSellTokenBalance
        ) revert IOrigamiSwapper.InvalidSwap();

        buyTokenAmount = buyToken.balanceOf(address(this)) - _initialBuyTokenBalance;

        // Must have a non-zero amount of buyToken's
        if (buyTokenAmount == 0) revert IOrigamiSwapper.InvalidSwap();
    }
}
