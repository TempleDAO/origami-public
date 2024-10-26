pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiFixedPriceOracle.sol)

import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

/**
 * @title OrigamiFixedPriceOracle
 * @notice A fixed price oracle only for both SPOT_PRICE and HISTORIC_PRICE, 
 * but with an optional 'price check' which may
 * revert depending on it's implementation.
 */
contract OrigamiFixedPriceOracle is OrigamiOracleBase {
    /**
     * @notice The fixed price which this oracle returns.
     */
    uint256 private immutable FIXED_PRICE;

    /**
     * @notice An oracle to lookup, used to ensure this reference price is valid and does not revert.
     * @dev Can be set to address(0) to disable the check
     */
    IOrigamiOracle public immutable priceCheckOracle;
    
    constructor (
        BaseOracleParams memory baseParams,
        uint256 _fixedPrice,
        address _priceCheckOracle
    )
        OrigamiOracleBase(baseParams)
    {
        FIXED_PRICE = _fixedPrice;
        priceCheckOracle = IOrigamiOracle(_priceCheckOracle);
    }

    /**
     * @notice Return the fixed oracle price, to `decimals` precision
     * @dev The `priceCheckOracle` lookup may revert.
     */
    function latestPrice(
        PriceType priceType,
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256 price) {
        // check reference price is valid and does not revert
        if (address(priceCheckOracle) != address(0))
            priceCheckOracle.latestPrice(priceType, roundingMode);

        return FIXED_PRICE;
    }
}
