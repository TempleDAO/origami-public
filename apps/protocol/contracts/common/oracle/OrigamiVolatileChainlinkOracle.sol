pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiVolatileChainlinkOracle.sol)

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Chainlink } from "contracts/libraries/Chainlink.sol";

/**
 * @title OrigamiVolatileChainlinkOracle
 * @notice A vanilla proxy to the chainlink price with no extra validation except for oracle staleness.
 * Both the spot price and historic reference price uses the Chainlink Oracle price
 * 
 * @dev Note the Chainlink lib is only suitable for mainnet. If a Chainlink Oracle is required on
 * an L2, then it should also take the sequencer staleness into consideration.
 * eg: https://docs.chain.link/data-feeds/l2-sequencer-feeds#example-code
 */
contract OrigamiVolatileChainlinkOracle is OrigamiOracleBase {
    using Range for Range.Data;
    using OrigamiMath for uint256;

    /**
     * @notice The Chainlink oracle for spot and the historic reference price
     */
    IAggregatorV3Interface public immutable priceOracle;

    /**
     * @notice True if the `priceOracle` price should be scaled down by `pricePrecisionScalar` to match `decimals`
     */
    bool public immutable pricePrecisionScaleDown;

    /**
     * @notice How much to scale up/down the `priceOracle` price to match cross rate oracle `decimals`
     */
    uint128 public immutable pricePrecisionScalar;

    /**
     * @notice How many seconds are allowed to pass before the Chainlink `priceOracle` price is determined as stale.
     * @dev eg https://data.chain.link/ethereum/mainnet/stablecoins/usdc-usd is guaranteed to update at least daily
     * So can be set to something like 86_400+300
     */
    uint128 public immutable priceStalenessThreshold;

    /**
     * @notice When using Redstone 'chainlink-like' oracle interfaces, the roundId
     * returned may be unused, and so validation isn't required in that case.
     */
    bool public immutable validateRoundId;

    /**
     * @notice When using Origami 'chainlink-like' oracle interfaces, the lastUpdatedAt
     * returned may be unused, and so validation isn't required in that case.
     */
    bool public immutable validateLastUpdatedAt;

    constructor (
        BaseOracleParams memory baseParams,
        address _priceOracle,
        uint128 _priceStalenessThreshold,
        bool _validateRoundId,
        bool _validateLastUpdatedAt
    )
        OrigamiOracleBase(baseParams)
    {
        priceOracle = IAggregatorV3Interface(_priceOracle);
        priceStalenessThreshold = _priceStalenessThreshold;
        (pricePrecisionScalar, pricePrecisionScaleDown) = Chainlink.scalingFactor(
            priceOracle, 
            decimals
        );
        validateRoundId = _validateRoundId;
        validateLastUpdatedAt = _validateLastUpdatedAt;
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @dev This may still revert if deemed stale or it returns a negative price
     */
    function latestPrice(
        PriceType /*priceType*/, 
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256 price) {
        // There isn't a separate historic reference price, so return the same price for both SPOT and HISTORIC
        price = Chainlink.price(
            Chainlink.Config(
                priceOracle, 
                pricePrecisionScaleDown, 
                pricePrecisionScalar,
                priceStalenessThreshold, 
                validateRoundId,
                validateLastUpdatedAt
            ),
            roundingMode
        );
    }

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
        address /*oracleBaseAsset*/,
        address /*oracleQuoteAsset*/
    ) {
        uint256 price1 = latestPrice(priceType1, roundingMode1);

        // Save a second oracle lookup if the rounding modes are the same.
        uint256 price2 = roundingMode1 == roundingMode2
            ? price1
            : latestPrice(priceType2, roundingMode2);

        return (
            price1,
            price2,
            baseAsset,
            quoteAsset
        );
    }
}
