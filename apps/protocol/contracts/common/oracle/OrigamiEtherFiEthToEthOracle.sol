pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiEtherFiEthToEthOracle.sol)

import { IEtherFiLiquidityPool } from "contracts/interfaces/external/etherfi/IEtherFiLiquidityPool.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Chainlink } from "contracts/libraries/Chainlink.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";

/**
 * @title OrigamiEtherfiEthToEthOracle
 * @notice The Ether.fi weETH/ETH oracle price, using the Redstone/Chainlink oracle
 * and the price range is verified against the onchain Ether.fi redemption price
 */
contract OrigamiEtherFiEthToEthOracle is OrigamiOracleBase, OrigamiElevatedAccess {
    using Range for Range.Data;
    using OrigamiMath for uint256;

    event MaxRelativeToleranceBpsSet(uint256 bps);

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
     * @notice The Ether.fi liquidity pool used to calculate the current weETH share price
     */
    IEtherFiLiquidityPool public immutable etherfiLiquidityPool;

    /**
     * @notice The maximum difference between the `spotPriceOracle` and the onchain redemption price.
     * Any price difference greater than this of this will revert when the spot price is queried.
     */
    uint256 public maxRelativeToleranceBps;

    constructor (
        address _initialOwner,
        BaseOracleParams memory baseParams,
        address _spotPriceOracle,
        uint128 _spotPriceStalenessThreshold,
        uint256 _maxRelativeToleranceBps,
        address _etherfiLiquidityPool
    ) 
        OrigamiOracleBase(baseParams)
        OrigamiElevatedAccess(_initialOwner)
    {
        spotPriceOracle = IAggregatorV3Interface(_spotPriceOracle);
        spotPriceStalenessThreshold = _spotPriceStalenessThreshold;
        (spotPricePrecisionScalar, spotPricePrecisionScaleDown) = Chainlink.scalingFactor(
            spotPriceOracle, 
            decimals
        );

        maxRelativeToleranceBps = _maxRelativeToleranceBps;
        etherfiLiquidityPool = IEtherFiLiquidityPool(_etherfiLiquidityPool);
    }

    /**
     * @notice Set the maximum difference allowed between the `spotPriceOracle` and the renzo onchain redemption price.
     */
    function setMaxRelativeToleranceBps(uint256 _maxRelativeToleranceBps) external onlyElevatedAccess {
        if (_maxRelativeToleranceBps > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit MaxRelativeToleranceBpsSet(_maxRelativeToleranceBps);
        maxRelativeToleranceBps = _maxRelativeToleranceBps;
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @param priceType What kind of price - Spot or Historic
     * @param roundingMode Round the price at each intermediate step such that the final price rounds in the 
     * specified direction.
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256 price) {
        // Calculate how much ETH will be received when redeeming 1e18 ezETH
        uint256 onChainPrice = _calculateRedeemAmount(1e18);

        if (priceType == PriceType.SPOT_PRICE) {
            price = Chainlink.price(
                Chainlink.Config(
                    spotPriceOracle,
                    spotPricePrecisionScaleDown,
                    spotPricePrecisionScalar,
                    spotPriceStalenessThreshold,
                    false, // Redstone 'chainlink lookalike contracts' don't use the roundId
                    true   // It does use the lastUpdatedAt though
                ),
                roundingMode
            );

            // validate the oracle price is sufficiently close to the on chain redemption price
            // Round up to get the worst case
            uint256 relDiffBps = price.relativeDifferenceBps(onChainPrice, OrigamiMath.Rounding.ROUND_UP);
            if (relDiffBps > maxRelativeToleranceBps) revert AboveMaxValidRange(
                address(spotPriceOracle), 
                price, 
                SafeCast.encodeUInt128(onChainPrice)
            );
        } else if (priceType == PriceType.HISTORIC_PRICE) {
            // Use the on chain weETH conversion
            price = onChainPrice;
        } else {
            // @dev Ensure priceType cases are explicitly listed above, even if this error isn't reachable
            revert UnknownPriceType(uint8(priceType));
        }
    }

    function _calculateRedeemAmount(uint256 shares) private view returns (uint256) {
        return etherfiLiquidityPool.amountForShare(shares);
    }
}
