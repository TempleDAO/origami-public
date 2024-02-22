pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/swappers/OrigamiDexAggregatorSwapper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @notice An on chain swapper contract to integrate with the 1Inch router | 0x proxy, 
 * possibly others which obtain quote calldata offchain and then execute via a low level call
 * to perform the swap onchain
 */
contract OrigamiDexAggregatorSwapper is IOrigamiSwapper, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /**
     * @notice The address of the 1Inch/0x/etc router
     */
    address public immutable router;

    // Internal balance tracking
    struct Balances {
        uint256 sellTokenAmount;
        uint256 buyTokenAmount;
    }

    constructor(
        address _initialOwner,
        address _router
    ) OrigamiElevatedAccess(_initialOwner) {
        router = _router;
    }

    /**
     * @notice Recover any token -- this contract should not ordinarily hold any tokens.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Execute a DEX aggregator swap
     */
    function execute(
        IERC20 sellToken, 
        uint256 sellTokenAmount, 
        IERC20 buyToken, 
        bytes calldata swapData
    ) external override returns (uint256 buyTokenAmount) {
        Balances memory initial = Balances({
            sellTokenAmount: sellToken.balanceOf(address(this)),
            buyTokenAmount: buyToken.balanceOf(address(this))
        });

        sellToken.safeTransferFrom(msg.sender, address(this), sellTokenAmount);
        sellToken.forceApprove(router, sellTokenAmount);

        // Execute the swap
        (bool success, bytes memory returndata) = router.call(swapData);

        if (!success) {
            if (returndata.length != 0) {
                // Look for revert reason and bubble it up if present
                // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol#L232
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            }
            revert UnknownSwapError(returndata);
        }

        // Verify that we have spent the expected amount, and have received some proceeds
        Balances memory current = Balances({
            sellTokenAmount: sellToken.balanceOf(address(this)),
            buyTokenAmount: buyToken.balanceOf(address(this))
        });

        // Cannot have any remaining balance of sellToken
        if (current.sellTokenAmount != initial.sellTokenAmount) {
            revert InvalidSwap();
        }

        // Should have a new balance of buyToken
        // slither-disable-next-line incorrect-equality
        if (current.buyTokenAmount == initial.buyTokenAmount) {
            revert InvalidSwap();
        }

        unchecked {
            buyTokenAmount = current.buyTokenAmount - initial.buyTokenAmount;
        }

        // Transfer back to the caller
        buyToken.safeTransfer(msg.sender, buyTokenAmount);
        emit Swap(address(sellToken), sellTokenAmount, address(buyToken), buyTokenAmount);
    }
}
