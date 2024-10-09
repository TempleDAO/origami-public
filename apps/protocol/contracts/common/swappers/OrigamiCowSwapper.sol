pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/swappers/OrigamiCowSwapper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { IConditionalOrder } from "contracts/interfaces/external/cowprotocol/IConditionalOrder.sol";
import { GPv2Order } from "contracts/external/cowprotocol/GPv2Order.sol";

import { IOrigamiCowSwapper } from "contracts/interfaces/common/swappers/IOrigamiCowSwapper.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Cow Swapper
 * @notice A contract to emit events and implement the correct flow for CoW swap conditional orders.
 * @dev Either LIMIT or MARKET orders can be placed by setting the relevant config
 */
contract OrigamiCowSwapper is IOrigamiCowSwapper, OrigamiElevatedAccess {
    using SafeERC20 for IERC20; 
    using GPv2Order for GPv2Order.Data;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiCowSwapper
    address public override immutable cowSwapRelayer;

    /// @inheritdoc IOrigamiCowSwapper
    bool public override isPaused;

    /// @notice The order configuration details used to create any new discrete orders for a given sellToken
    mapping(IERC20 sellToken => OrderConfig config) private _orderConfig;

    /// @notice For certain issues with the conditional orders, then a hint can be given
    /// to the CoW swap Watchtower so it can delay querying for more orders for this period.
    uint256 private constant ORDER_DELAY_SECONDS = 300;

    constructor(
        address _initialOwner,
        address _cowSwapRelayer
    ) OrigamiElevatedAccess(_initialOwner) {
        cowSwapRelayer = _cowSwapRelayer;
    }
    
    /// @inheritdoc IOrigamiCowSwapper
    function setPaused(bool paused) external override onlyElevatedAccess {
        isPaused = paused;
        emit PausedSet(paused);
    }

    /// @inheritdoc IOrigamiCowSwapper
    function setCowApproval(address sellToken, uint256 amount) external override onlyElevatedAccess {
        // No need to check if this sellToken is configured or not - this function may
        // be called after the order config has been removed already (or before it is configured in the first place)
        IERC20(sellToken).forceApprove(cowSwapRelayer, amount);
    }

    /// @inheritdoc IOrigamiCowSwapper
    function setOrderConfig(
        address sellToken, 
        OrderConfig calldata config
    ) external override onlyElevatedAccess {
        if (sellToken == address(0)) revert CommonEventsAndErrors.InvalidAddress(sellToken);
        if (address(config.buyToken) == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(config.buyToken));
        if (sellToken == address(config.buyToken)) revert CommonEventsAndErrors.InvalidAddress(address(config.buyToken));

        if (config.maxSellAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (config.minBuyAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        if (address(config.limitPriceOracle) != address(0)) {
            // If the price oracle is set, then the assets must match
            if (!config.limitPriceOracle.matchAssets(sellToken, address(config.buyToken)))
                revert CommonEventsAndErrors.InvalidParam();
        } else {
            // If the price oracle is not set, then there should not be a limitPricePremiumBps
            if (config.limitPricePremiumBps > 0) revert CommonEventsAndErrors.InvalidParam();
        }

        if (config.recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(config.recipient);
        if (config.verifySlippageBps > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        if (config.expiryPeriodSecs == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (config.expiryPeriodSecs > 7 days) revert CommonEventsAndErrors.InvalidParam();

        _orderConfig[IERC20(sellToken)] = config;
        emit OrderConfigSet(sellToken);
    }

    /// @inheritdoc IOrigamiCowSwapper
    function removeOrderConfig(address sellToken) external override onlyElevatedAccess {
        // Checking if it exists in the mapping already isn't necessary.
        delete _orderConfig[IERC20(sellToken)];
        emit OrderConfigRemoved(sellToken);
    }

    /// @inheritdoc IOrigamiCowSwapper
    function updateAmountsAndPremiumBps(
        address sellToken, 
        uint96 maxSellAmount,
        uint96 minBuyAmount,
        uint16 limitPricePremiumBps
    ) external override onlyElevatedAccess { 
        if (maxSellAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (minBuyAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Ensure it's configured first.
        OrderConfig storage config = _getOrderConfig(IERC20(sellToken));

        // If the price oracle is not set, then there should not be a limitPricePremiumBps
        if (address(config.limitPriceOracle) == address(0)) {
            if (limitPricePremiumBps > 0) revert CommonEventsAndErrors.InvalidParam();
        }

        config.maxSellAmount = maxSellAmount;
        config.minBuyAmount = minBuyAmount;
        config.limitPricePremiumBps = limitPricePremiumBps;

        emit OrderConfigSet(sellToken);
    }

    /**
     * @notice Recover any token
     * @dev The default implementaiton allows elevated access to recover any token. This may need
     * to be restricted for specific implementations (eg restricted from pulling vault reserve tokens)
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external virtual onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice IOrigamiCowSwapper
     */
    function createConditionalOrder(address sellToken) external override onlyElevatedAccess {
        if (isPaused) revert CommonEventsAndErrors.IsPaused();

        // Ensure it's configured first.
        _getOrderConfig(IERC20(sellToken));

        // Owner is the key of a hashmap in Watchtower - an owner may emit multiple ConditionalOrderParams events
        // It is also passed into getTradeableOrderWithSignature() when creating discrete orders.
        address orderOwner = address(this);

        // The 'handler' isn't in this contract or watchtower. 
        // It's intended for use with the more complex ComposableCow framework they provide
        address handler = address(0);

        // The salt is unused - there will only be one valid conditional order per sellToken
        // at a time.
        // If the ConditionalOrderCreated event is emitted with the same parameters, 
        // there's no issue - Watchtower skips adding into it's registry again if the params
        // are the same
        // https://github.com/cowprotocol/watch-tower/blob/90ecbf5de87447657a36dfcd49a714b1b5105380/src/domain/events/index.ts#L206
        bytes32 conditionalOrderSalt = bytes32(0);

        // Encode the sellToken as the static input - it's the unique key used
        // for order creation and validation.
        bytes memory staticInput = abi.encode(sellToken);

        // The following event will be pickd up by the watchtower offchain
        // service, which is responsible for automatically posting CoW AMM
        // orders on the CoW Protocol orderbook.
        // See: https://github.com/cowprotocol/watch-tower/blob/90ecbf5de87447657a36dfcd49a714b1b5105380/src/domain/events/index.ts#L105
        emit IConditionalOrder.ConditionalOrderCreated(
            orderOwner,
            IConditionalOrder.ConditionalOrderParams(
                handler,
                conditionalOrderSalt,
                staticInput
            )
        );
    }

    /**
     * @inheritdoc IConditionalOrder
     */
    function getTradeableOrderWithSignature(
        address orderOwner,
        IConditionalOrder.ConditionalOrderParams calldata params,
        // Unused by watchtower
        // https://github.com/cowprotocol/watch-tower/blob/90ecbf5de87447657a36dfcd49a714b1b5105380/src/domain/polling/index.ts#L309
        bytes calldata /*offchainInput*/, 
        // Unused when using conditional orders directly (as opposed to via Safe)
        bytes32[] calldata /*proof*/
    ) external override view returns (
        GPv2Order.Data memory order, 
        bytes memory signature
    ) {
        // If the contract is paused, then give a hint to Watchtower to try again in 
        // ORDER_DELAY_SECONDS
        if (isPaused) revert PollTryAtEpoch(block.timestamp + ORDER_DELAY_SECONDS, "Paused");

        // Should match the orderOwner set in createConditionalOrder()
        if (orderOwner != address(this)) {
            revert OrderNotValid("order owner must be self");
        }

        // Should match the handler set in createConditionalOrder()
        // The order creation isn't delegated.
        if (address(params.handler) != address(0)) {
            revert OrderNotValid("handler must be unset");
        }

        // Should match the salt set in createConditionalOrder()
        if (params.salt != bytes32(0)) {
            revert OrderNotValid("salt must be unset");
        }

        // Ensure we have setup this sellToken
        IERC20 sellToken = abi.decode(params.staticInput, (IERC20));
        OrderConfig storage config = _orderConfig[sellToken];
        if (address(config.buyToken) == address(0)) {
            revert OrderNotValid("sellToken not configured");
        }

        // If no balance at all, then give a hint to Watchtower to try again in
        // ORDER_DELAY_SECONDS
        uint256 sellTokenBalance = sellToken.balanceOf(address(this));
        if (sellTokenBalance == 0) {
            revert PollTryAtEpoch(block.timestamp + ORDER_DELAY_SECONDS, "ZeroBalance");
        }

        uint256 sellAmount = _getSellAmount(
            config.maxSellAmount, 
            config.useCurrentBalanceForSellAmount, 
            sellTokenBalance
        );

        (, uint256 roundedBuyAmount) = _getBuyAmount(sellToken, sellAmount, config);
        order = _getDiscreteOrder(sellToken, sellAmount, config, roundedBuyAmount);
        signature = abi.encode(order);
    }

    /**
     * @notice Returns whether the signature provided is for a valid order as of the block it's called
     * @param signature Signature byte array, encoding the submitted GPv2Order.Data
     * @dev This function is called by the CoW swap settlement contract.
     *
     * This verify step needs to protect against unintentional/malicious orders being placed.
     * However if using a price oracle for limit orders, the buyAmount may have changed between when the (legitimate) 
     * order was placed versus this function being called by the CoW swap solvers during settlement to verify the 
     * order signature.
     *
     * - If the latest calculated buyAmount is LESS THAN the buyAmount of the originally placed order, that's ok.
     *   That original order is simply unlikely to be filled but if it does, that's an ok result.
     *   That out of the money order will expire and be replaced in the next validTo (aka expiry) period anyway.
     * - If the latest calculated buyAmount is MORE THAN the buyAmount of the originally placed order, 
     *   that is ok but ONLY WITHIN A `verifySlippageBps` TOLERANCE. It will revert if outside of this tolerance
     *   If the original order is priced a lot lower, we will get a fill for less that what we are truly looking for, 
     *   potentially at a loss (depending on the application)
     * 
     * No need to verify the `hash`, as this is constructed by the Settlement contract before this function is called.
     * https://github.com/cowprotocol/contracts/blob/5957d67d69df231c6a879ec7b64806181c86ebb6/src/contracts/mixins/GPv2Signing.sol#L156
     * It's also ignored in Curve's CowSwapBurner
     */
    function isValidSignature(bytes32 /*hash*/, bytes memory signature) external override view returns (bytes4) {
        // A revert here simply means the swap cannot be executed by a solver. The actual behaviour of that
        // order is then not defined. Best case it's picked up again in the next auction, worst case is that
        // the order is dropped by solvers. That's ok as we submit a new order in the next expiry window anyway.
        if (isPaused) revert CommonEventsAndErrors.IsPaused();

        (GPv2Order.Data memory order) = abi.decode(signature, (GPv2Order.Data));
        OrderConfig storage config = _getOrderConfig(order.sellToken);

        // Can use any sellAmount (from the decoded order) as long as it's under the
        // configured maxSellAmount
        // This does mean it's possible for a smaller order to be placed by anyone outside of getTradeableOrderWithSignature(),
        // but the minBuyAmount puts a floor on what is eligable to be filled. CoW Solvers will fill at the best price anyway since
        // it's a competitive auction.
        uint256 maxSellAmount = config.maxSellAmount;
        uint256 sellAmount = order.sellAmount < maxSellAmount ? order.sellAmount : maxSellAmount;

        // Calculate the latest buyAmount as of now, using that sellAmount
        (, uint256 latestRoundedBuyAmount) = _getBuyAmount(order.sellToken, sellAmount, config);

        // If the latest rounded buyAmount is greater than when the order is placed plus some slippage tolerance
        // then revert.
        //
        // Note: Because this (rounded) buyAmount will be in discrete steps, when the order is verified it might have moved to the next
        // divisor, which may cause it to be outside the slippage tolerance suddenly. This is ok and as expected; The 
        // order configuration just needs to take this into consideration:
        //   a/ The `verifySlippageBps` can be set a little larger than the effect of `roundDownDivisor` on that notional; or
        //   b/ The `roundDownDivisor` can be reduced; or
        //   c/ That particular order is now just deemed invalid, so will attempt again at the next expiry window.
        uint256 verifySlippageBps = config.verifySlippageBps;
        uint256 orderBuyAmountWithSlippage = (verifySlippageBps > 0)
            ? order.buyAmount.addBps(verifySlippageBps, OrigamiMath.Rounding.ROUND_DOWN)
            : order.buyAmount;

        if (latestRoundedBuyAmount > orderBuyAmountWithSlippage) {
            revert CommonEventsAndErrors.Slippage(orderBuyAmountWithSlippage, latestRoundedBuyAmount);
        }

        // Re-generate the order for the original amount and compare the hash.
        GPv2Order.Data memory generatedOrder = _getDiscreteOrder(order.sellToken, sellAmount, config, order.buyAmount);

        // All other fields in the generated order should be the same as in the signature.
        if (keccak256(abi.encode(generatedOrder)) != keccak256(signature)) {
            revert OrderDoesNotMatchTradeableOrder();
        }
        
        return this.isValidSignature.selector;
    }

    /**
     * @notice IOrigamiCowSwapper
     */
    function orderConfig(address sellToken) external override view returns (OrderConfig memory config) {
        return _orderConfig[IERC20(sellToken)];
    }

    /**
     * @notice IOrigamiCowSwapper
     */
    function getSellAmount(address sellToken) external override view returns (uint256) {
        IERC20 _sellToken = IERC20(sellToken);
        OrderConfig storage config = _getOrderConfig(_sellToken);
        return _getSellAmount(
            config.maxSellAmount, 
            config.useCurrentBalanceForSellAmount, 
            _sellToken.balanceOf(address(this))
        );
    }

    /**
     * @notice IOrigamiCowSwapper
     */
    function getBuyAmount(address sellToken) external override view returns (uint256 unroundedBuyAmount, uint256 roundedBuyAmount) {
        IERC20 _sellToken = IERC20(sellToken);
        OrderConfig storage config = _getOrderConfig(_sellToken);
        return _getBuyAmount(_sellToken, config.maxSellAmount, config);
    }

    /*
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) external override pure returns (bool) {
        return interfaceId == type(IOrigamiCowSwapper).interfaceId
            || interfaceId == type(IConditionalOrder).interfaceId 
            || interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC1271).interfaceId;
    }

    function _getSellAmount(
        uint256 maxSellAmount,
        bool useCurrentBalanceForSellAmount,
        uint256 sellTokenBalance
    ) internal pure returns (uint256 sellAmount) {
        // Capped by the maxSellAmount
        return useCurrentBalanceForSellAmount
            ? (sellTokenBalance < maxSellAmount ? sellTokenBalance : maxSellAmount)
            : maxSellAmount;
    }

    /**
     * @dev Calculate the buyAmount for a CoW swap order as of now, for a given sellToken
     * If applyRoundingDown, then the final amount will be rounded down to the 
     * configured power of 10.
     * This ensures that small changes in price block to block don't end up
     * in a lot of new orders being placed.
     */
    function _getBuyAmount(
        IERC20 sellToken,
        uint256 sellAmount,
        OrderConfig storage config
    ) internal view returns (uint256 unroundedBuyAmount, uint256 roundedBuyAmount) {
        IOrigamiOracle limitPriceOracle = config.limitPriceOracle;
        // ROUND_DOWN is fine in all cases as this is just the limit order price
        if (address(limitPriceOracle) != address(0)) {
            // Similarly minor precision loss from transient divisions in these calcs are also
            // acceptable.
            unroundedBuyAmount = config.limitPriceOracle.convertAmount(
                address(sellToken),
                sellAmount,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_DOWN
            );

            // Add the premium to the buyToken amount
            uint256 limitPricePremiumBps = config.limitPricePremiumBps;
            if (limitPricePremiumBps > 0) {
                unroundedBuyAmount = unroundedBuyAmount.addBps(config.limitPricePremiumBps, OrigamiMath.Rounding.ROUND_DOWN);
            }
        }

        // Use the maximum of the two minimums (the one oracle derived buyAmount and the min set in config).  
        uint256 minBuyAmount = config.minBuyAmount;
        unroundedBuyAmount = (minBuyAmount > unroundedBuyAmount) ? minBuyAmount : unroundedBuyAmount;

        // Intentionally lose precision when rounding down to the nearest divisor.
        uint256 divisor = config.roundDownDivisor;
        roundedBuyAmount = (divisor > 0)
            ? (unroundedBuyAmount / divisor) * divisor
            : unroundedBuyAmount;

        if (roundedBuyAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
    }
    
    function _getOrderConfig(IERC20 sellToken) internal view returns (OrderConfig storage config) {
        config = _orderConfig[sellToken];
        if (address(config.buyToken) == address(0)) revert InvalidSellToken(address(sellToken));
    }

    function _getDiscreteOrder(
        IERC20 sellToken, 
        uint256 sellAmount,
        OrderConfig storage config, 
        uint256 buyAmount
    ) internal view returns (GPv2Order.Data memory) {
        return GPv2Order.Data({
            sellToken: sellToken,
            buyToken: config.buyToken,
            receiver: config.recipient,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: _calcOrderExpiry(config.expiryPeriodSecs),
            appData: config.appData,
            feeAmount:0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: config.partiallyFillable,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    /**
     * @notice Calculate the expiry time (unix) given an expiryPeriodSecs time window.
     * `expiryPeriodSecs=300 seconds` means that an order as of 13:45:15 UTC will have an expiry
     * of the nearest 5 minute boundary, so 13:50:00 UTC
     * @dev There is a minimun of 90 seconds until the next order expiry, so with the example above
     * 13:48:45 order time will have an expiry of 13:55:00 UTC
     */
    function _calcOrderExpiry(uint32 expiryPeriodSecs) internal view returns (uint32) {
        // slither-disable-next-line divide-before-multiply
        return (
            (uint32(block.timestamp) / expiryPeriodSecs) * expiryPeriodSecs
        ) + expiryPeriodSecs;
    }
}
