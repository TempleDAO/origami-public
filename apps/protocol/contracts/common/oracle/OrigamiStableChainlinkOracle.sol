pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiStableChainlinkOracle.sol)

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Chainlink } from "contracts/libraries/Chainlink.sol";

/**
 * @title OrigamiStableChainlinkOracle
 * @notice The historic price is fixed to an expected value (eg 1 for DAI/USD).
 * The spot price references a Chainlink Oracle
 * If the spot price falls outside of a policy-expected price range, then the price lookup will revert.
 * 
 * @dev Note the Chainlink lib is only suitable for mainnet. If a Chainlink Oracle is required on
 * an L2, then it should also take the sequencer staleness into consideration.
 * eg: https://docs.chain.link/data-feeds/l2-sequencer-feeds#example-code
 */
contract OrigamiStableChainlinkOracle is OrigamiOracleBase, OrigamiElevatedAccess {
    using Range for Range.Data;
    using OrigamiMath for uint256;

    /**
     * @notice The stable historic price expected. Eg for pegged assets this would be 1e18
     */
    uint256 public immutable stableHistoricPrice;

    /**
     * @notice The Chainlink oracle for spot price
     */
    IAggregatorV3Interface public immutable spotPriceOracle;

    /**
     * @notice True if the `spotPriceOracle` price should be scaled down by `spotPricePrecisionScalar` to match `decimals`
     */
    bool public immutable spotPricePrecisionScaleDown;

    /**
     * @notice How much to scale up/down the `spotPriceOracle` price to match cross rate oracle `decimals`
     */
    uint128 public immutable spotPricePrecisionScalar;

    /**
     * @notice How many seconds are allowed to pass before the Chainlink `spotPriceOracle` price is determined as stale.
     * @dev eg https://data.chain.link/ethereum/mainnet/stablecoins/usdc-usd is guaranteed to update at least daily
     * So can be set to something like 86_400+300
     */
    uint128 public immutable spotPriceStalenessThreshold;

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

    /**
     * @notice The lowest valid price range for the spot price. Anything outside of this will revert when queried
     */
    Range.Data public validSpotPriceRange;

    constructor (
        address _initialOwner,
        BaseOracleParams memory baseParams,
        uint256 _stableHistoricPrice,
        address _spotPriceOracle,
        uint128 _spotPriceStalenessThreshold,
        Range.Data memory _validSpotPriceRange,
        bool _validateRoundId,
        bool _validateLastUpdatedAt
    )
        OrigamiOracleBase(baseParams)
        OrigamiElevatedAccess(_initialOwner)
    {
        stableHistoricPrice = _stableHistoricPrice;
        spotPriceOracle = IAggregatorV3Interface(_spotPriceOracle);
        spotPriceStalenessThreshold = _spotPriceStalenessThreshold;
        (spotPricePrecisionScalar, spotPricePrecisionScaleDown) = Chainlink.scalingFactor(
            spotPriceOracle, 
            decimals
        );
        validateRoundId = _validateRoundId;
        validateLastUpdatedAt = _validateLastUpdatedAt;
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
     * @dev This may still revert - eg if deemed stale, div by 0, negative price
     * @param priceType What kind of price - Spot or Historic
     * @param roundingMode Round the price at each intermediate step such that the final price rounds in the specified direction.
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256 price) {
        if (priceType == PriceType.SPOT_PRICE) {
            price = Chainlink.price(
                Chainlink.Config(
                    spotPriceOracle, 
                    spotPricePrecisionScaleDown, 
                    spotPricePrecisionScalar,
                    spotPriceStalenessThreshold, 
                    validateRoundId,
                    validateLastUpdatedAt
                ),
                roundingMode
            );
            Range.Data memory _validSpotPriceRange = validSpotPriceRange;
            if (price < _validSpotPriceRange.floor) revert BelowMinValidRange(address(spotPriceOracle), price, _validSpotPriceRange.floor);
            if (price > _validSpotPriceRange.ceiling) revert AboveMaxValidRange(address(spotPriceOracle), price, _validSpotPriceRange.ceiling);
        } else if (priceType == PriceType.HISTORIC_PRICE) {
            return stableHistoricPrice;
        } else {
            // @dev Ensure priceType cases are explicitly listed above, even if this error isn't reachable
            revert UnknownPriceType(uint8(priceType));
        }
    }
}
