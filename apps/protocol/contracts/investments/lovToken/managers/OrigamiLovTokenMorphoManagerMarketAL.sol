pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lovToken/managers/OrigamiLovTokenMorphoManagerMarketAL.sol)

import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami LovToken Manager, for use with Morpho markets (with A/L conversion)
 * @notice The same as `OrigamiLovTokenMorphoManager`, however the `userALRange` and `rebalanceALRange`
 * are converted to a 'market priced A/L' when validation is performed.
 * @dev 
 *  - The `userALRange`, `rebalanceALRange` MUST be specified in the Morpho terms
 *  - When rebalancing, the `minNewAL` and `maxNewAL` MUST be specified in the Morpho terms
 *  - The liabilities function will price the debt tokens using the `debtTokenToReserveTokenOracle` - so it will be market priced.
 *  - The `assetToLiabilityRatio()` and `assetsAndLiabilities()` functions will also be market priced.
 *  - So over time, the reported A/L and EE will fluctuate as the market price shifts.
 */
contract OrigamiLovTokenMorphoManagerMarketAL is OrigamiLovTokenMorphoManager {
    using SafeCast for uint256;

    event MorphoALToMarketALOracleSet(address indexed morphoALToMarketALOracle);

    /**
     * @notice An Origami oracle to convert a 'Morpho' priced A/L into 'market' priced A/L terms
     * @dev For example Pendle PT tokens may be valued at maturity (1:1 to underlying) in Morpho
     * but within origami we want to use the market price.
     */
    address public morphoALToMarketALOracle;

    /// @dev The Origami oracle precision is a fixed 18dp
    uint256 private constant ORIGAMI_ORACLE_PRECISION = 1e18;

    constructor(
        address _initialOwner,
        address _reserveToken_,
        address _debtToken_,
        address _dynamicFeeOracleBaseToken,
        address _lovToken,
        address _borrowLend,
        address _morphoALToMarketALOracle
    ) OrigamiLovTokenMorphoManager(
        _initialOwner,
        _reserveToken_,
        _debtToken_,
        _dynamicFeeOracleBaseToken,
        _lovToken,
        _borrowLend
    ) {
        morphoALToMarketALOracle = _morphoALToMarketALOracle;
    }

    /**
     * @notice Set an Origami oracle to convert a 'Morpho' priced A/L into 'market' priced A/L terms
     */
    function setMorphoALToMarketALOracle(address _morphoALToMarketALOracle) external onlyElevatedAccess {
        if (_morphoALToMarketALOracle == address(0)) revert CommonEventsAndErrors.InvalidAddress(_morphoALToMarketALOracle);
        morphoALToMarketALOracle = _morphoALToMarketALOracle;
        emit MorphoALToMarketALOracleSet(_morphoALToMarketALOracle);
    }
    
    /**
     * @dev Convert the 'borrow lend' A/L (specified in `userALRange`, `rebalanceALRange`) into a 'market priced' A/L
     */
    function convertedAL(uint128 al, Cache memory cache) internal override view returns (uint128) {
        if (al == type(uint128).max) return al;

        // Use the cache's `implData` slot to cache the Oracle price to convert the A/L, as it may be expensive to call
        // and won't change intra-transaction.
        if (cache.implData == 0) {
            cache.implData = IOrigamiOracle(morphoALToMarketALOracle).latestPrice(
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            );
        }

        return cache.implData == ORIGAMI_ORACLE_PRECISION
            ? al
            : (cache.implData * al / ORIGAMI_ORACLE_PRECISION).encodeUInt128();
    }
}
