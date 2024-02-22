pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiOracleBase.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title OrigamiOracleBase
 * @notice Common base logic for Origami Oracle's
 */
abstract contract OrigamiOracleBase is IOrigamiOracle {
    using OrigamiMath for uint256;

    /**
     * @notice The address used to reference the baseAsset for amount conversions
     */
    address public immutable override baseAsset;

    /**
     * @notice The address used to reference the quoteAsset for amount conversions
     */
    address public immutable override quoteAsset;

    /**
     * @notice The number of decimals of precision the oracle price is returned as
     */
    uint8 public constant override decimals = 18;

    /**
     * @notice The precision that the cross rate oracle price is returned as: `10^decimals`
     */
    uint256 public constant override precision = 1e18;

    /**
     * @notice When converting from baseAsset<->quoteAsset, the fixed point amounts
     * need to be scaled by this amount.
     */
    uint256 public immutable assetScalingFactor;

    /**
     * @notice A human readable description for this origami oracle
     */
    string public override description;

    constructor(
        string memory _description,
        address _baseAssetAddress,
        uint8 _baseAssetDecimals,
        address _quoteAssetAddress,
        uint8 _quoteAssetDecimals
    ) {
        description = _description;
        baseAsset = _baseAssetAddress;
        quoteAsset = _quoteAssetAddress;
        if (_quoteAssetDecimals > decimals + _baseAssetDecimals) revert CommonEventsAndErrors.InvalidParam();
        assetScalingFactor = 10 ** (decimals + _baseAssetDecimals - _quoteAssetDecimals);
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @dev This may still revert - eg if deemed stale, div by 0, negative price
     * @param priceType What kind of price - Spot or Historic
     * @param roundingMode Round the price at each intermediate step such that the final price rounds in the specified direction.
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) public virtual override view returns (uint256 price);

    /**
     * @notice Same as `latestPrice()` but for two separate prices from this oracle
     */
    function latestPrices(
        PriceType priceType1, 
        OrigamiMath.Rounding roundingMode1,
        PriceType priceType2, 
        OrigamiMath.Rounding roundingMode2
    ) external override view returns (
        uint256 /*price1*/, 
        uint256 /*price2*/, 
        address /*baseAsset*/,
        address /*quoteAsset*/
    ) {
        return (
            latestPrice(priceType1, roundingMode1),
            latestPrice(priceType2, roundingMode2),
            baseAsset,
            quoteAsset
        );
    }

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
    ) external override view returns (uint256 toAssetAmount) {
        if (fromAsset == baseAsset) {
            // The numerator needs to round in the same way to be conservative
            uint256 _price = latestPrice(
                priceType, 
                roundingMode
            );

            return fromAssetAmount.mulDiv(
                _price,
                assetScalingFactor,
                roundingMode
            );
        } else if (fromAsset == quoteAsset) {
            // The denominator needs to round in the opposite way to be conservative
            uint256 _price = latestPrice(
                priceType, 
                roundingMode == OrigamiMath.Rounding.ROUND_UP ? OrigamiMath.Rounding.ROUND_DOWN : OrigamiMath.Rounding.ROUND_UP
            );

            return fromAssetAmount.mulDiv(
                assetScalingFactor,
                _price,
                roundingMode
            );
        }

        revert CommonEventsAndErrors.InvalidToken(fromAsset);
    }
}
