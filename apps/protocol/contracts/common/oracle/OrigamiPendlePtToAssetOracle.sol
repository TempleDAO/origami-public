pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiPendlePtToAssetOracle.sol)

import { PendlePYOracleLib } from "@pendle/core-v2/contracts/oracles/PendlePYOracleLib.sol";
import { PendlePYLpOracle } from "@pendle/core-v2/contracts/oracles/PendlePYLpOracle.sol";
import { IPMarket } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";

import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title OrigamiPendlePtToAssetOracle
 * @notice A Pendle PT to Asset oracle price, for a given market and twap duration
 * @dev Pendle oracle price definition example: 1 <PT sUSDe> is equal to 1 <USDe> deposited on Ethena at maturity.
 */
contract OrigamiPendlePtToAssetOracle is OrigamiOracleBase {
    using PendlePYOracleLib for IPMarket;

    error UninitializedPendleOracle();

    /**
     * @notice The pendle market to observe
     */
    IPMarket public immutable pendleMarket;

    /**
     * @notice The twap duration to observe over.
     * @dev If an update is required here, the oracle can be redeployed.
     */
    uint32 public immutable twapDuration;

    constructor (
        BaseOracleParams memory baseParams,
        address _pendleOracle,
        address _pendleMarket,
        uint32 _twapDuration
    ) 
        OrigamiOracleBase(baseParams)
    {
        pendleMarket = IPMarket(_pendleMarket);
        twapDuration = _twapDuration;

        // Check that the pendle oracle is initialized properly.
        // It's the deployer's responsibility to do so prior.
        (
            bool increaseCardinalityRequired, 
            , 
            bool oldestObservationSatisfied
        ) = PendlePYLpOracle(_pendleOracle).getOracleState(
            _pendleMarket, 
            _twapDuration
        );
        if (increaseCardinalityRequired || !oldestObservationSatisfied) revert UninitializedPendleOracle();
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     */
    function latestPrice(
        PriceType /*priceType*/, 
        OrigamiMath.Rounding /*roundingMode*/
    ) public override view returns (uint256 price) {
        // There isn't a separate historic reference price, so return the same price for both SPOT and HISTORIC
        // There isn't any extra rounding required here either.

        // The pendle returns a rate such that `1 PT * rate / 1e18 = amount of underlying`
        // It is ok to assume that the PT and underlying have the same decimals, and so the rate is 18dp.
        // Since this matches our origami oracle, no scaling is required.
        // If in future for a new oracle the PT does not have the same decimals as the underlying (would be strange),
        // a change can be made here to scale it.
        return pendleMarket.getPtToAssetRate(twapDuration);
    }
}
