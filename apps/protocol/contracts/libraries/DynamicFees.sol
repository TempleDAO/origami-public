pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/DynamicFees.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @notice A helper to calculate dynamic entry and exit fees based off the difference
 * between an oracle historic vs spot price
 */
library DynamicFees {
    using OrigamiMath for uint256;

    enum FeeType {
        DEPOSIT_FEE,
        EXIT_FEE
    }

    /**
     * @notice The current deposit or exit fee based on market conditions.
     * Fees are applied to the portion of lovToken shares the depositor 
     * would have received. Instead that fee portion isn't minted (benefiting remaining users)
     * Ignoring the minFeeBps, deposit vs exit fees are symmetric:
     *   - A 0.004 cent increase in price (away from expected historic) should result a deposit fee of X bps
     *   - A 0.004 cent decrease in price (away from expected historic) should result an exit fee, also of X bps
     * ie X is the same in both cases.
     * @dev feeLeverageFactor has 4dp precision
     */
    function dynamicFeeBps(
        FeeType feeType,
        IOrigamiOracle oracle,
        address expectedBaseAsset,
        uint64 minFeeBps,
        uint256 feeLeverageFactor
    ) internal view returns (uint256) {
        // Pull the spot and expected historic price from the oracle.
        // Round up for both to be consistent no matter if the oracle is in expected quoted order or not.
        (uint256 _spotPrice, uint256 _histPrice, address _baseAsset, address _quoteAsset) = oracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE,
            OrigamiMath.Rounding.ROUND_UP
        );
        
        // Whether the expected 'base' asset of the oracle is indeed the base asset.
        // If not, then the delta and denominator is switched
        bool _inQuotedOrder;
        if (_baseAsset == expectedBaseAsset) {
            _inQuotedOrder = true;
        } else if (_quoteAsset != expectedBaseAsset) {
            revert CommonEventsAndErrors.InvalidToken(expectedBaseAsset);
        }

        uint256 _delta;
        uint256 _denominator;
        if (feeType == FeeType.DEPOSIT_FEE) {
            // If spot price is > than the expected historic, then they are exiting
            // at a price better than expected. The exit fee is based off the relative
            // difference of the expected spotPrice - historicPrice.
            // Or opposite if the oracle order is inverted
            unchecked {
                if (_inQuotedOrder) {
                    if (_spotPrice < _histPrice) {
                        (_delta, _denominator) = (_histPrice - _spotPrice, _histPrice);
                    }
                } else {
                    if (_spotPrice > _histPrice) {
                        (_delta, _denominator) = (_spotPrice - _histPrice, _spotPrice);
                    }
                }
            }
        } else {
            // If spot price is > than the expected historic, then they are exiting
            // at a price better than expected. The exit fee is based off the relative
            // difference of the expected spotPrice - historicPrice.
            // Or opposite if the oracle order is inverted
            unchecked {
                if (_inQuotedOrder) {
                    if (_spotPrice > _histPrice) {
                        (_delta, _denominator) = (_spotPrice - _histPrice, _histPrice);
                    }
                } else {
                    if (_spotPrice < _histPrice) {
                        (_delta, _denominator) = (_histPrice - _spotPrice, _spotPrice);
                    }
                }
            }
        }

        // If no delta, just return the min fee
        if (_delta == 0) {
            return minFeeBps;
        }

        // Relative diff multiply by a leverage factor to match the worst case lovToken
        // effective exposure
        // Result is in basis points, since `feeLeverageFactor` has 4dp precision
        uint256 _fee = _delta.mulDiv(
            feeLeverageFactor,
            _denominator,
            OrigamiMath.Rounding.ROUND_UP
        );

        // Use the maximum of the calculated fee and a pre-set minimum.
        return minFeeBps > _fee ? minFeeBps : _fee;
    }
}
