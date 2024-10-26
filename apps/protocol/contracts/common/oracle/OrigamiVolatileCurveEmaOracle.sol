pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiVolatileCurveEmaOracle.sol)

import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ICurveStableSwapNG } from "contracts/interfaces/external/curve/ICurveStableSwapNG.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/**
 * @title OrigamiVolatileCurveEmaOracle
 * @notice The Curve finance exponential moving average oracle for a given stableswap-ng pool
 * 
 * @dev Note: This assumes it's a newer implementation (or tokens are both 18dp tokens) 
 * and so not affected by the issue here:
 * https://docs.curve.fi/stableswap-exchange/stableswap-ng/pools/oracles/?h=oracle
 */
contract OrigamiVolatileCurveEmaOracle is OrigamiOracleBase, OrigamiElevatedAccess {
    using Range for Range.Data;

    /**
     * @notice The curve stableswap NG. The coins must match the nominated 
     * baseAsset & quoteAsset in any order
     */
    ICurveStableSwapNG public immutable stableSwapNg;

    /**
     * @notice Whether the curve oracle price needs reciprocating to get the expected order.
     */
    bool public immutable reciprocal;

    /**
     * @notice The valid price range for the spot price. Anything outside of this will revert when queried
     */
    Range.Data public validSpotPriceRange;

    constructor (
        address _initialOwner,
        BaseOracleParams memory baseParams,
        address _stableSwapNg,
        Range.Data memory _validSpotPriceRange
    )
        OrigamiOracleBase(baseParams)
        OrigamiElevatedAccess(_initialOwner)
    {
        stableSwapNg = ICurveStableSwapNG(_stableSwapNg);

        if (stableSwapNg.N_COINS() != 2) revert CommonEventsAndErrors.InvalidParam();
        
        address _a0 = stableSwapNg.coins(0);
        address _a1 = stableSwapNg.coins(1);
        if (!matchAssets(_a0, _a1)) revert CommonEventsAndErrors.InvalidParam();
        
        // price_oracle(0) returns the `coins(1)` in terms of `coins(0)`
        // So the price needs flipping if it's in the same baseAsset/quoteAsset order
        reciprocal = (_a0 == baseAsset && _a1 == quoteAsset);

        validSpotPriceRange.set(_validSpotPriceRange.floor, _validSpotPriceRange.ceiling);
    }

    /**
     * @notice Set the min/max price ranges which are counted as valid for the spot price lookup.
     * @dev Any price outside of this range for that oracle will revert when `latestPrice()` is called
     * with priceType=SPOT_PRICE
     */
    function setValidSpotPriceRange(
        uint128 _validSpotPriceFloor, 
        uint128 _validSpotPriceCeiling
    ) external onlyElevatedAccess {
        emit ValidPriceRangeSet(_validSpotPriceFloor, _validSpotPriceCeiling);
        validSpotPriceRange.set(_validSpotPriceFloor, _validSpotPriceCeiling);
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @dev This may still revert if the price is outside of the valid price range
     */
    function latestPrice(
        PriceType /*priceType*/,
        OrigamiMath.Rounding /*roundingMode*/
    ) public override view returns (uint256 price) {
        // Curve oracle always returns to 18dp
        price = stableSwapNg.price_oracle(0);
        if (reciprocal) {
            price = 1e36 / price;
        }

        Range.Data memory _validSpotPriceRange = validSpotPriceRange;
        if (price < _validSpotPriceRange.floor) revert BelowMinValidRange(address(stableSwapNg), price, _validSpotPriceRange.floor);
        if (price > _validSpotPriceRange.ceiling) revert AboveMaxValidRange(address(stableSwapNg), price, _validSpotPriceRange.ceiling);
    }

    /**
     * @notice Same as `latestPrice()` but for two separate prices from this oracle	
     */
    function latestPrices(
        PriceType priceType1, 
        OrigamiMath.Rounding roundingMode1,
        PriceType /*priceType2*/, 
        OrigamiMath.Rounding /*roundingMode2*/
    ) external override view returns (
        uint256 /*price1*/, 
        uint256 /*price2*/, 
        address /*oracleBaseAsset*/,
        address /*oracleQuoteAsset*/
    ) {
        // priceType and roundingMode are unused in this oracle
        uint256 price = latestPrice(priceType1, roundingMode1);

        return (
            price,
            price,
            baseAsset,
            quoteAsset
        );
    }
}
