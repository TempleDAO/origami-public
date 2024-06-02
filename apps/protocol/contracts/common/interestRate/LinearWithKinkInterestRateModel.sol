pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/interestRate/LinearWithKinkInterestRateModel.sol)

import { BaseInterestRateModel } from "contracts/common/interestRate/BaseInterestRateModel.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title 'Linear With Kink' Interest Rate Model
 * @notice An interest rate curve derived from the current utilization ratio (UR) of debt.
 * This is represented as two seperate linear slopes, joined at a 'kink' - a particular UR.
 */
contract LinearWithKinkInterestRateModel is BaseInterestRateModel, OrigamiElevatedAccess {
    struct RateParams {
        /// @notice The base interest rate which is the y-intercept when utilization rate is 0
        uint80 baseInterestRate;

        /// @notice Interest rate at 100 percent utilization
        uint80 maxInterestRate;

        /// @notice Interest rate at kink
        uint80 kinkInterestRate;

        /// @notice The utilization ratio point at which slope changes
        uint256 kinkUtilizationRatio;
    }

    /**
     * @notice The interest rate parameters to derive the two curves with a kink.
     */
    RateParams public rateParams;

    event InterestRateParamsSet(
        uint80 _baseInterestRate, 
        uint80 _maxInterestRate, 
        uint256 _kinkUtilizationRatio, 
        uint80 _kinkInterestRate
    );

    /**
     * @notice Construct an interest rate model
     * @param _baseInterestRate base interest rate which is the y-intercept when utilization rate is 0
     * @param _maxInterestRate Interest rate at 100 percent utilization
     * @param _kinkUtilizationRatio The utilization point at which slope changes
     * @param _kinkInterestRate Interest rate at the `kinkUtiliszation`;
     */
    constructor(
        address _initialOwner,
        uint80 _baseInterestRate, 
        uint80 _maxInterestRate, 
        uint256 _kinkUtilizationRatio, 
        uint80 _kinkInterestRate
    ) OrigamiElevatedAccess(_initialOwner)
    {
        _setRateParams(
            _baseInterestRate, 
            _maxInterestRate, 
            _kinkUtilizationRatio, 
            _kinkInterestRate
        );
    }
    
    /**
     * @notice Update the interest rate parameters.
     */
    function setRateParams(
        uint80 _baseInterestRate, 
        uint80 _maxInterestRate, 
        uint256 _kinkUtilizationRatio, 
        uint80 _kinkInterestRate
    ) external onlyElevatedAccess {
        _setRateParams(
            _baseInterestRate, 
            _maxInterestRate, 
            _kinkUtilizationRatio, 
            _kinkInterestRate
        );
    }

    function _setRateParams(
        uint80 _baseInterestRate, 
        uint80 _maxInterestRate, 
        uint256 _kinkUtilizationRatio, 
        uint80 _kinkInterestRate
    ) internal {
        if (_kinkUtilizationRatio == 0) revert CommonEventsAndErrors.InvalidParam();
        if (_kinkUtilizationRatio >= PRECISION) revert CommonEventsAndErrors.InvalidParam();
        if (_baseInterestRate > _kinkInterestRate) revert CommonEventsAndErrors.InvalidParam();
        if (_kinkInterestRate > _maxInterestRate) revert CommonEventsAndErrors.InvalidParam();

        // The slope between base->kink should be lte the slope between kink->max:
        if (
            OrigamiMath.mulDiv(
                _kinkInterestRate - _baseInterestRate,
                PRECISION - _kinkUtilizationRatio,
                1e18,
                OrigamiMath.Rounding.ROUND_DOWN
            ) > 
            OrigamiMath.mulDiv(
                _maxInterestRate - _kinkInterestRate,
                _kinkUtilizationRatio,
                1e18,
                OrigamiMath.Rounding.ROUND_DOWN
            )
        ) revert CommonEventsAndErrors.InvalidParam();

        rateParams.baseInterestRate = _baseInterestRate;
        rateParams.maxInterestRate = _maxInterestRate;
        rateParams.kinkInterestRate = _kinkInterestRate;
        rateParams.kinkUtilizationRatio = _kinkUtilizationRatio;
        emit InterestRateParamsSet(
            _baseInterestRate, 
            _maxInterestRate, 
            _kinkUtilizationRatio, 
            _kinkInterestRate
        );
    }

    /**
     * @notice Calculates the current interest rate based on a utilization ratio
     * @param utilizationRatio The utilization ratio scaled to `PRECISION`
     */
    function computeInterestRateImpl(uint256 utilizationRatio) internal override view returns (uint96) {
        RateParams storage _rateParams = rateParams;

        uint256 interestRate;
        uint256 kinkUtilizationRatio = _rateParams.kinkUtilizationRatio;
        if (utilizationRatio > kinkUtilizationRatio) {
            uint256 kinkInterestRate = _rateParams.kinkInterestRate;
            uint256 urDownDelta;
            uint256 irDelta;
            uint256 urUpDelta;
            unchecked {
                urDownDelta = utilizationRatio - kinkUtilizationRatio;
                irDelta = _rateParams.maxInterestRate - kinkInterestRate;
                urUpDelta = PRECISION - kinkUtilizationRatio;
            }
            
            // linearly interpolated point between kink IR and max IR
            // y = y1 + (x-x1) * (y2-y1) / (x2-x1)
            interestRate = OrigamiMath.mulDiv(
                urDownDelta,
                irDelta,
                urUpDelta,
                OrigamiMath.Rounding.ROUND_UP
            );
            unchecked {
                interestRate = interestRate + kinkInterestRate;
            }
        } else {
            uint256 baseInterestRate = _rateParams.baseInterestRate;
            uint256 irDelta;
            unchecked {
                irDelta = _rateParams.kinkInterestRate - baseInterestRate;
            }

            // linearly interpolated point between base IR and kink IR
            // y = y1 + (x-x1) * (y2-y1) / (x2-x1)
            // where x1 = zero
            interestRate = OrigamiMath.mulDiv(
                utilizationRatio,
                irDelta,
                kinkUtilizationRatio,
                OrigamiMath.Rounding.ROUND_UP
            );
            unchecked {
                interestRate = interestRate + baseInterestRate;
            }
        }

        // Downcast safe because IR is always lte the maxInterestRate (uint80)
        return uint96(interestRate);
    }
}
