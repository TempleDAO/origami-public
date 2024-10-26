pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/swappers/IOrigamiCowSwapper.sol)

import { IConditionalOrder } from "contracts/interfaces/external/cowprotocol/IConditionalOrder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

/**
 * @title Origami Cow Swapper
 * @notice A contract to emit events and implement the correct flow for CoW swap conditional orders
 */
interface IOrigamiCowSwapper is IConditionalOrder {
    event OrderConfigSet(address indexed sellToken);
    event OrderConfigRemoved(address indexed sellToken);
    event PausedSet(bool paused);

    /**
     * @notice On signature verification, the order within the signature does not match
     * the current tradeable order
     */
    error OrderDoesNotMatchTradeableOrder();

    /**
     * @notice This sellToken does not have an order configured.
     */
    error InvalidSellToken(address sellToken);

    /**
     * @notice The order configuration details used to create any new discrete orders for a given sellToken
     * @dev byte packed into 5x slots
     * NB: There's an opportunity for gas golfing here by packing into custom types - may revisit in future
     * iterations (adds extra complexity around encoding/decoding)
     */
    struct OrderConfig {
        /// @dev The amount of sellToken to place an order for
        /// MUST be > 0
        /// This can be set to a higher amount than the current balance the contract holds.
        /// CoW swap will still work and sell as much as it can, up until the order expiry.
        uint96 maxSellAmount;

        /// @dev The IERC20 token to buy.
        /// MUST NOT be address(0)
        /// MUST NOT be the same as `sellToken`
        IERC20 buyToken;

        // ---- END SLOT 1

        /// @dev The minimum amount of buyToken to purchase in the order
        /// Note this is total order size, not each individual fill
        /// MUST be > 0
        uint96 minBuyAmount;

        /// @dev The origami oracle to lookup the limit order price.
        /// Not used if set to address(0)
        IOrigamiOracle limitPriceOracle;

        // ---- END SLOT 2

        /// @dev The receiver of buyToken's on each fill.
        address recipient;

        /// @dev When specifying the order for watchtower, the buyAmount is rounded down to
        /// the nearest specified divisor.
        /// This is to ensure we have discrete unique orders, rather than spamming CoW swap with slightly
        /// different orders (which may get us on the deny list)
        /// Specified in full precision in the buyToken decimals
        /// Eg if buyToken is 18dp, to round down to the nearest 50 tokens, set this to 50e18
        /// Not used if set to zero
        uint96 roundDownDivisor;

        // ---- END SLOT 3

        /// @dev True if partial fills are ok, false for a 'fill or kill'
        bool partiallyFillable;

        /// @dev Set to true to use the current contract balance of sellToken for the
        /// sell amount, with a cap of maxSellAmount
        bool useCurrentBalanceForSellAmount;

        /// @dev How many basis points premium above the `limitPriceOracle` is the limit order set.
        /// Not used if set to zero
        uint16 limitPricePremiumBps;

        /// @dev The acceptable slippage (in basis points) to the unrounded buyAmount between
        /// T1. The order being picked up by watchtower. 
        /// T2. It being verified and added to the cow swap order book.
        /// Not used if set to zero
        uint16 verifySlippageBps;

        /// @dev The expiryPeriodSecs time window, used to set the expiry time of any new discrete order.
        /// `expiryPeriodSecs=300 seconds` means that an order as of 13:45:15 UTC will have an expiry
        /// of the nearest 5 minute boundary, so 13:50:00 UTC
        uint24 expiryPeriodSecs;

        // ---- END SLOT 4 (NB: there is padded space here which could be used for future use if needed)

        /// @dev The appData for any new discrete orders.
        /// It refers to an IPFS blob containing metadata, but also controls the pre and post hooks to run upon settlement.
        /// This is set on the contract in advance to avoid incorrect setting.
        /// NOTE: There are constraints around hooks - study the docs
        bytes32 appData;

        // ---- END SLOT 5
    }

    /**
     * @notice Set whether the contract is paused.
     * This will revert within getTradeableOrderWithSignature()
     * and isValidSignature()
     * Any already placed orders are not cancelled -- however
     * token approval can be set to zero.
     */
    function setPaused(bool paused) external;

    /**
     * @notice Set the token allowance of a pre-configured sellToken to the cow swap relayer
     */
    function setCowApproval(address sellToken, uint256 amount) external;

    /**
     * @notice Sets or updates the order configuration for a particular sellToken
     * @dev Registering the conditional order with CowSwap's Watchtower is done separately 
     * via createConditionalOrder()
     * It is up to elevated access to ensure there is no circular loops that may cause infinite swaps
     * back and forth (bleeding fees in the process). There may be valid situations where there is a loop
     * but with different limit prices, for example.
     */
    function setOrderConfig(
        address sellToken, 
        OrderConfig calldata config
    ) external;

    /**
     * @notice Remove the order configuration for a given sellToken
     * @dev Note the next time Watchtower polls getTradeableOrderWithSignature() for an order, 
     * it will revert with OrderNotValid. This will drop the order from Watchtower.
     */
    function removeOrderConfig(address sellToken) external;

    /**
     * @notice A convenience function to update the maxSellAmount, minBuyAmount and price premium on future discrete orders.
     */
    function updateAmountsAndPremiumBps(
        address sellToken, 
        uint96 maxSellAmount,
        uint96 minBuyAmount,
        uint16 limitPricePremiumBps
    ) external;

    /**
     * @notice Register the conditional order with Watchtower
     * @dev This is safe to call for the same sellToken multiple times as Watchtower will ignore
     * duplicates.
     * If Watchtower drops the conditional order for some reason, this is safe to be called again.
     */
    function createConditionalOrder(address sellToken) external;

    /**
     * @notice The CoW swap vault relayer - tokens need to be approved to this contract.
     */
    function cowSwapRelayer() external view returns (address);

    /**
     * @notice Whether the swapper contract is paused for all
     * orders
     */
    function isPaused() external view returns (bool);

    /**
     * @notice The order configuration details used to create any new discrete orders for a given sellToken
     */
    function orderConfig(address sellToken) external view returns (OrderConfig memory);

    /**
     * @notice Calculate the sellAmount as of now for a given token
     */
    function getSellAmount(address sellToken) external view returns (
        uint256 sellAmount
    );

    /**
     * @notice Calculate the buyAmount as of now for a given sellToken. 
     * @dev If it's a MARKET order, this is set to the `minBuyAmount`
     * If it's a LIMIT order it is derived from the `limitPriceOracle` + `limitPricePremiumBps`
     * (floored by the `minBuyAmount`)
     * `roundedBuyAmount` is the `unroundedBuyAmount` rounded down to the nearest `roundDownDivisor`
     */
    function getBuyAmount(address sellToken) external view returns (
        uint256 unroundedBuyAmount, 
        uint256 roundedBuyAmount
    );
}
