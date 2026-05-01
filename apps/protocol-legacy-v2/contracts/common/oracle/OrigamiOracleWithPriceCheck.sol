pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiOracleWithPriceCheck.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title OrigamiOracleWithPriceCheck
 * @notice An Origami Oracle wrapper which reverts if the underlying oracle price falls outside
 * of an expected range.
 */
contract OrigamiOracleWithPriceCheck is OrigamiElevatedAccess, IOrigamiOracle {
    using Range for Range.Data;
    using OrigamiMath for uint256;

    /// @notice The underlying origami oracle
    IOrigamiOracle public immutable underlyingOracle;

    /// @notice The valid price range for the spot and historic prices.
    /// @dev Anything outside of this will revert when queried
    Range.Data public validPriceRange;

    constructor (
        address _initialOwner,
        address _underlyingOracle,
        Range.Data memory _validPriceRange
    )
        OrigamiElevatedAccess(_initialOwner)
    {
        underlyingOracle = IOrigamiOracle(_underlyingOracle);
        validPriceRange.set(_validPriceRange.floor, _validPriceRange.ceiling);
    }

    /**
     * @notice Set the min/max price ranges which are counted as valid for the spot or historic price lookup.
     * @dev Any price outside of this range for that oracle will revert when `latestPrice()` is called
     */
    function setValidPriceRange(
        uint128 _validPriceFloor, 
        uint128 _validPriceCeiling
    ) external onlyElevatedAccess {
        emit ValidPriceRangeSet(_validPriceFloor, _validPriceCeiling);
        validPriceRange.set(_validPriceFloor, _validPriceCeiling);
    }

    /// @inheritdoc IOrigamiOracle
    function baseAsset() external view returns (address) {
        return underlyingOracle.baseAsset();
    }

    /// @inheritdoc IOrigamiOracle
    function quoteAsset() external view returns (address) {
        return underlyingOracle.quoteAsset();
    }

    /// @inheritdoc IOrigamiOracle
    function decimals() external view returns (uint8) {
        return underlyingOracle.decimals();
    }

    /// @inheritdoc IOrigamiOracle
    function precision() external view returns (uint256) {
        return underlyingOracle.precision();
    }

    /// @inheritdoc IOrigamiOracle
    function assetScalingFactor() external view returns (uint256) {
        return underlyingOracle.assetScalingFactor();
    }

    /// @inheritdoc IOrigamiOracle
    function description() external view returns (string memory) {
        return underlyingOracle.description();
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @dev This may still revert if deemed stale or it returns a negative price
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256 price) {
        price = underlyingOracle.latestPrice(priceType, roundingMode);

        Range.Data memory _validPriceRange = validPriceRange;
        if (price < _validPriceRange.floor) revert BelowMinValidRange(address(underlyingOracle), price, _validPriceRange.floor);
        if (price > _validPriceRange.ceiling) revert AboveMaxValidRange(address(underlyingOracle), price, _validPriceRange.ceiling);
    }

    /// @inheritdoc IOrigamiOracle
    function latestPrices(
        PriceType priceType1, 
        OrigamiMath.Rounding roundingMode1,
        PriceType priceType2, 
        OrigamiMath.Rounding roundingMode2
    ) external virtual override view returns (
        uint256 /*price1*/, 
        uint256 /*price2*/, 
        address /*oracleBaseAsset*/,
        address /*oracleQuoteAsset*/
    ) {
        return (
            latestPrice(priceType1, roundingMode1),
            latestPrice(priceType2, roundingMode2),
            underlyingOracle.baseAsset(),
            underlyingOracle.quoteAsset()
        );
    }

    /// @inheritdoc IOrigamiOracle
    function convertAmount(
        address fromAsset,
        uint256 fromAssetAmount,
        PriceType priceType,
        OrigamiMath.Rounding roundingMode 
    ) external override view returns (uint256 toAssetAmount) {
        if (fromAsset == underlyingOracle.baseAsset()) {
            // The numerator needs to round in the same way to be conservative
            uint256 _price = latestPrice(
                priceType, 
                roundingMode
            );

            return fromAssetAmount.mulDiv(
                _price,
                underlyingOracle.assetScalingFactor(),
                roundingMode
            );
        } else if (fromAsset == underlyingOracle.quoteAsset()) {
            // The denominator needs to round in the opposite way to be conservative
            uint256 _price = latestPrice(
                priceType, 
                roundingMode == OrigamiMath.Rounding.ROUND_UP ? OrigamiMath.Rounding.ROUND_DOWN : OrigamiMath.Rounding.ROUND_UP
            );

            if (_price == 0) revert InvalidPrice(address(this), int256(_price));
            return fromAssetAmount.mulDiv(
                underlyingOracle.assetScalingFactor(),
                _price,
                roundingMode
            );
        }

        revert CommonEventsAndErrors.InvalidToken(fromAsset);
    }

    /// @inheritdoc IOrigamiOracle
    function matchAssets(address asset1, address asset2) public view returns (bool) {
        return underlyingOracle.matchAssets(asset1, asset2);
    }
}
