pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiErc4626Oracle.sol)

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title OrigamiErc4626Oracle
 * @notice The price is represented by an ERC-4626 vault, optionally multiplied
 * by another Origami oracle price
 */
contract OrigamiErc4626Oracle is OrigamiOracleBase {
    using OrigamiMath for uint256;

    /**
     * @notice The origami oracle for the quoteToken
     */
    IOrigamiOracle public immutable quoteAssetOracle;

    constructor (
        BaseOracleParams memory baseParams,
        address _quoteAssetOracle
    ) 
        OrigamiOracleBase(baseParams)
    {
        quoteAssetOracle = IOrigamiOracle(_quoteAssetOracle);
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @param priceType What kind of price - Spot or Historic
     * @param roundingMode Round the price at each intermediate step such that the final price rounds in the specified direction.
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256 price) {
        // How many assets for 1e18 shares
        price = IERC4626(baseAsset).convertToAssets(precision);

        // Convert to the quote asset if required
        if (address(quoteAssetOracle) != address(0)) {
            price = price.mulDiv(
                quoteAssetOracle.latestPrice(priceType, roundingMode),
                precision,
                roundingMode
            );
        }
    }
}
