pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/oracle/IOrigamiOracle.sol)

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @notice An oracle which returns prices for pairs of assets, where an asset
 * could refer to a token (eg DAI) or a currency (eg USD)
 * Convention is the same as the FX market. Given the DAI/USD pair:
 *   - DAI = Base Asset (LHS of pair)
 *   - USD = Quote Asset (RHS of pair)
 * This price defines how many USD you get if selling 1 DAI
 *
 * Further, an oracle can define two PriceType's:
 *   - SPOT_PRICE: The latest spot price, for example from a chainlink oracle
 *   - HISTORIC_PRICE: An expected (eg 1:1 peg) or calculated historic price (eg TWAP)
 *
 * For assets which do are not tokens (eg USD), an internal address reference will be used
 * since this is for internal purposes only
 */
interface IOrigamiOracle {
    error InvalidPrice(address oracle, int256 price);
    error StalePrice(address oracle, uint256 lastUpdatedAt, int256 price);
    error UnknownPriceType(uint8 priceType);
    error BelowMinValidRange(address oracle, uint256 price, uint128 floor);
    error AboveMaxValidRange(address oracle, uint256 price, uint128 ceiling);

    event ValidPriceRangeSet(uint128 validFloor, uint128 validCeiling);

    enum PriceType {
        /// @notice The current spot price of this Oracle
        SPOT_PRICE,

        /// @notice The historic price of this Oracle. 
        /// It may be a fixed expectation (eg DAI/USD would be fixed to 1)
        /// or use a TWAP or some other moving average, etc.
        HISTORIC_PRICE
    }

    /**
     * @notice The address used to reference the baseAsset for amount conversions
     */
    function baseAsset() external view returns (address);

    /**
     * @notice The address used to reference the quoteAsset for amount conversions
     */
    function quoteAsset() external view returns (address);

    /**
     * @notice The number of decimals of precision the price is returned as
     */
    function decimals() external view returns (uint8);

    /**
     * @notice The precision that the cross rate oracle price is returned as: `10^decimals`
     */
    function precision() external view returns (uint256);

    /**
     * @notice A human readable description for this oracle
     */
    function description() external view returns (string memory);

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @dev This may still revert - eg if deemed stale, div by 0, negative price
     * @param priceType What kind of price - Spot or Historic
     * @param roundingMode Round the price at each intermediate step such that the final price rounds in the specified direction.
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) external view returns (uint256 price);

    /**
     * @notice Same as `latestPrice()` but for two separate prices from this oracle
     */
    function latestPrices(
        PriceType priceType1, 
        OrigamiMath.Rounding roundingMode1,
        PriceType priceType2, 
        OrigamiMath.Rounding roundingMode2
    ) external view returns (
        uint256 price1, 
        uint256 price2, 
        address baseAsset,
        address quoteAsset
    );

    /**
     * @notice Convert either the baseAsset->quoteAsset or quoteAsset->baseAsset
     * @dev The `fromAssetAmount` needs to be in it's natural fixed point precision (eg USDC=6dp)
     * The `toAssetAmount` will also be returned in it's natural fixed point precision
     */
    function convertAmount(
        address fromAsset,
        uint256 fromAssetAmount,
        PriceType priceType,
        OrigamiMath.Rounding roundingMode
    ) external view returns (uint256 toAssetAmount);
}
