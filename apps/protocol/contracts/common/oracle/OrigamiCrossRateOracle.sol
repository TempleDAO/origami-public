pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiCrossRateOracle.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title OrigamiCrossRateOracle
 * @notice A derived cross rate oracle price, by dividing baseOracle / quotedOracle
 * @dev Both baseOracle and quotedOracle prices are checked against a valid range (eg a peg). 
 * If outside of that range, the latestPrice() function will revert.
 */
contract OrigamiCrossRateOracle is OrigamiOracleBase {
    using OrigamiMath for uint256;

    /**
     * @notice The oracle used for the base asset price
     * ie the LHS in a XXX/YYY quote
     * @dev For [DAI/USDC] = [DAI/USD]/[USDC/USD], baseOracle would point to the [DAI/USD] oracle
     */
    IOrigamiOracle public immutable baseAssetOracle;

    /**
     * @notice The oracle used for the quote asset price
     * ie the RHS in a XXX/YYY quote
     * @dev For [DAI/USDC] = [DAI/USD]/[USDC/USD], quotedOracle would point to the [USDC/USD] oracle
     */
    IOrigamiOracle public immutable quoteAssetOracle;

    /**
     * @notice An oracle to lookup, used to ensure this reference price is valid and does not revert.
     * @dev Can be set to address(0) to disable the check
     */
    IOrigamiOracle public immutable priceCheckOracle;

    /**
     * @notice Whether to multiply or to divide the two rates.
     */
    bool public immutable multiply;

    constructor (
        BaseOracleParams memory baseParams,
        address _baseAssetOracle,
        address _quoteAssetOracle,
        address _priceCheckOracle
    )
        OrigamiOracleBase(baseParams)
    {
        baseAssetOracle = IOrigamiOracle(_baseAssetOracle);
        quoteAssetOracle = IOrigamiOracle(_quoteAssetOracle);
        priceCheckOracle = IOrigamiOracle(_priceCheckOracle);

        // This oracle handles either:
        //   baseAsset/quoteAsset = baseAsset/crossAsset * crossAsset/quoteAsset
        //   baseAsset/quoteAsset = baseAsset/crossAsset / quoteAsset/crossAsset
        // So apply checks that it all matches:
        // 1. The base asset must match the baseAssetOracle's base asset
        if (baseAssetOracle.baseAsset() != baseParams.baseAssetAddress) revert CommonEventsAndErrors.InvalidParam();

        // 2. The quote asset and the cross asset must match the quoteAssetOracle, in either order.
        address _crossAsset = baseAssetOracle.quoteAsset();
        if (!quoteAssetOracle.matchAssets(_crossAsset, baseParams.quoteAssetAddress)) revert CommonEventsAndErrors.InvalidParam();

        multiply = quoteAsset == quoteAssetOracle.quoteAsset();
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
    ) public override view returns (uint256) {
        // check reference price is valid and does not revert
        if (address(priceCheckOracle) != address(0))
            priceCheckOracle.latestPrice(priceType, roundingMode);

        // baseOracle (the numerator) price follows the requested roundingMode
        // So if roundDown, then we want the numerator to be lower (round down)
        uint256 _basePrice = baseAssetOracle.latestPrice(
            priceType, 
            roundingMode
        );

        if (multiply) {
            // Also the numerator - so follow the requested roundingMode
            uint256 _quotePrice = quoteAssetOracle.latestPrice(
                priceType, 
                roundingMode
            );

            return _basePrice.mulDiv(_quotePrice, precision, roundingMode);
        } else {
            // quotedOracle (the denominator) price follows the opposite roundingMode
            // So if roundDown, then we want the denominator to be higher (round up)
            uint256 _quotePrice = quoteAssetOracle.latestPrice(
                priceType, 
                roundingMode == OrigamiMath.Rounding.ROUND_DOWN ? OrigamiMath.Rounding.ROUND_UP : OrigamiMath.Rounding.ROUND_DOWN
            );
            if (_quotePrice == 0) revert InvalidPrice(address(quoteAssetOracle), int256(_quotePrice));

            // Final price follows the requested roundingMode
            return _basePrice.mulDiv(precision, _quotePrice, roundingMode);
        }
    }
}
