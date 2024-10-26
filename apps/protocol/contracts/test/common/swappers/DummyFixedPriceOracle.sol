pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title DummyFixedPriceOracle
 * @notice A fixed price oracle only for both SPOT_PRICE and HISTORIC_PRICE
 */
contract DummyFixedPriceOracle is OrigamiOracleBase {
    /**
     * @notice The fixed price which this oracle returns.
     */
    uint256 private fixedPrice;

    constructor (
        BaseOracleParams memory baseParams,
        uint256 _fixedPrice
    )
        OrigamiOracleBase(baseParams)
    {
        fixedPrice = _fixedPrice;
    }

    function setFixedPrice(uint256 price) external {
        fixedPrice = price;
    }

    /**
     * @notice Return the fixed oracle price, to `decimals` precision
     */
    function latestPrice(
        PriceType /*priceType*/,
        OrigamiMath.Rounding /*roundingMode*/
    ) public override view returns (uint256 price) {
        return fixedPrice;
    }
}
