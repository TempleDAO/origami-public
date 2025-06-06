pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol)

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

/* solhint-disable not-rely-on-time */

/**
 * @title Origami Circuit Breaker -- total volumes (across all users) in a rolling period window
 *
 * @dev Forked from https://github.com/TempleDAO/temple/tree/76da0e528f441d7999bb42092727aaad193506df/protocol/contracts/v2/circuitBreaker
 * 
 * @notice No more than the cap can be borrowed within a `periodDuration` window. 
 * A slight nuance is that it will be slightly less than `periodDuration`, it also takes into account
 * how many internal buckets are used - this is a tradeoff for gas efficiency.
 * 
 * -- The tracking is split up into hourly buckets, so for a 24 hour window, we define 24 hourly buckets.
 * -- When a new transaction is checked, it will roll forward by the required buckets (when it gets to 23 it will circle back from 0), cleaning up the buckets which are now > 24hrs in the past.
        If it's in the same hr as last time, then nothing to clean up
 * -- Then adds the new volume into the bucket
 * -- Then sums the buckets up and checks vs the cap, reverting if over.

 * This means that we only have to sum up 24 items.

 * The compromise is that the window we check for is going to be somewhere between 23hrs and 24hrs.
 */
contract OrigamiCircuitBreakerAllUsersPerPeriod is IOrigamiCircuitBreaker, OrigamiElevatedAccess {

    /**
     * @notice The circuit breaker proxy which is allowed to call preCheck()
     */
    address public immutable proxy;

    /**
     * @notice The duration of the rolling period window
     */
    uint32 public periodDuration;

    /**
     * @notice The maximum allowed amount to be transacted within each period
     */
    uint128 private _cap;

    /**
     * @notice How many buckets to split the periodDuration into. 
     * @dev A lower number of buckets means less gas will be used, however the rolling
     * window will change at the *start* of the bucket time.
     *   eg for a 24 hour `periodDuration`, with 24 (hourly) buckets, there could be a transaction
     *   for the cap at the 13:45:00, and again the next day 24 hours later at 13:05:00
     *   and this would be allowed.
     * A higher number of buckets means this wait time is less, however this will use more gas.
     * `nBuckets` must not be greater than `MAX_BUCKETS`, and must be a divisor of `periodDuration`
     */
    uint32 public nBuckets;

    /**
     * @notice The derived length of time in each bucket
     */
    uint32 public secondsPerBucket;

    /**
     * @notice The current bucket index.
     * @dev The first bucket starts at 1-1-1970
     */
    uint32 public bucketIndex;

    /**
     * @notice The maxiumum number of buckets that can be used
     */
    uint32 public constant MAX_BUCKETS = 4000;

    /**
     * @notice The total amount of volume tracked within each bucket
     */
    uint256[MAX_BUCKETS] public buckets;

    event ConfigSet(uint32 periodDuration, uint32 nBuckets, uint128 cap);
    event CapSet(uint128 cap);
    error CapBreached(uint256 totalRequested, uint128 cap);

    constructor(
        address _initialOwner,
        address _proxy,
        uint32 _periodDuration,
        uint32 _nBuckets,
        uint128 __cap
    ) OrigamiElevatedAccess(_initialOwner) {
        proxy = _proxy;
        _setConfig(_periodDuration, _nBuckets, __cap);
    }

    /**
     * @notice Verify the new amount requested does not breach the cap in this rolling period.
     */
    function preCheck(uint256 amount) external override onlyProxy {
        uint32 _nextBucketIndex;
        unchecked {
            _nextBucketIndex = uint32(block.timestamp / secondsPerBucket);
        }
        uint32 _currentBucketIndex = bucketIndex;
        uint32 _nBuckets = nBuckets;
        
        // If this time bucket is different to the last one
        // then delete any buckets in between first - since that is old data
        if (_nextBucketIndex != _currentBucketIndex) {
            uint256 _minBucketResetIndex = _getMinBucketResetIndex(_nBuckets, _currentBucketIndex, _nextBucketIndex);

            unchecked {
                for (; _minBucketResetIndex < _nextBucketIndex; ++_minBucketResetIndex) {
                    // Set to dust
                    buckets[(_minBucketResetIndex+1) % _nBuckets] = 1;
                }
            }

            bucketIndex = _nextBucketIndex;
        }

        uint256 _newUtilisation = _currentUtilisation(_nBuckets) + amount;
        if (_newUtilisation > _cap) revert CapBreached(_newUtilisation, _cap);

        // Unchecked is safe since we know the total new utilisation is under the cap.
        unchecked {
            // slither-disable-next-line weak-prng
            buckets[_nextBucketIndex % _nBuckets] += amount;
        }
    }

    /**
     * @notice Set the duration, buckets and cap. This will reset the clock for any totals
     * added since in the new periodDuration.
     * @dev Since this resets the buckets, it should be executed via flashbots protect
     * such that it can't be frontrun (where the caps could be filled twice)
     */
    function setConfig(uint32 _periodDuration, uint32 _nBuckets, uint128 __cap) external onlyElevatedAccess {
        _setConfig(_periodDuration, _nBuckets, __cap);
    }

    /**
     * @notice Update the cap for this circuit breaker
     */
    function updateCap(uint128 newCap) external onlyElevatedAccess {
        _cap = newCap;
        emit CapSet(newCap);
    }

    /**
     * @dev Find the earliest time bucket which needs to be reset, based on the number of buckets per duration.
     */
    function _getMinBucketResetIndex(uint32 _nBuckets, uint32 _currentBucketIndex, uint32 _nextBucketIndex) internal pure returns (uint256 minBucketResetIndex) {
        unchecked {
            uint32 _oneperiodDurationAgoIndex = _nextBucketIndex - _nBuckets;
            minBucketResetIndex = _currentBucketIndex < _oneperiodDurationAgoIndex ? _oneperiodDurationAgoIndex : _currentBucketIndex;
        }
    }

    /**
     * @notice The maximum allowed amount to be transacted within each period
     */
    function cap() external override view returns (uint256) {
        return _cap;
    }

    /**
     * @notice What is the total utilisation so far in this `periodDuration`
     */
    function currentUtilisation() public override view returns (uint256 amount) {
        uint32 _nextBucketIndex;
        unchecked {
            _nextBucketIndex = uint32(block.timestamp / secondsPerBucket);
        }
        uint32 _currentBucketIndex = bucketIndex;
        uint32 _nBuckets = nBuckets;
        
        uint256 utilisation = _currentUtilisation(_nBuckets);

        // If the bucket index has moved forward since the last `preCheck()`, 
        // remove any amounts from buckets which would be otherwise reset
        if (_nextBucketIndex != _currentBucketIndex) {
            uint256 _minBucketResetIndex = _getMinBucketResetIndex(_nBuckets, _currentBucketIndex, _nextBucketIndex);
            unchecked {
                for (; _minBucketResetIndex < _nextBucketIndex; ++_minBucketResetIndex) {
                    utilisation -= buckets[(_minBucketResetIndex+1) % _nBuckets] - 1;
                }
            }
        }

        amount = utilisation;
    }

    /**
     * @notice Return the available amount which can be utilised in the circuit breaker
     */
    function available() external override view returns (uint256) {
        return uint256(_cap) - currentUtilisation();
    }

    function _currentUtilisation(uint32 _nBuckets) internal view returns (uint256 amount) {
        // Unchecked is safe here because we know previous entries are under the cap.
        unchecked {
            for (uint256 i; i < _nBuckets; ++i) {
                amount = amount + buckets[i];
            }

            // Remove the dust
            amount = amount - _nBuckets;
        }
    }

    function _setConfig(uint32 _periodDuration, uint32 _nBuckets, uint128 __cap) internal {
        if (_periodDuration == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (_periodDuration % _nBuckets != 0) revert CommonEventsAndErrors.InvalidParam();
        if (_nBuckets > MAX_BUCKETS) revert CommonEventsAndErrors.InvalidParam();

        nBuckets = _nBuckets;
        periodDuration = _periodDuration;
        secondsPerBucket = _periodDuration / _nBuckets;
        _cap = __cap;
        bucketIndex = 0;

        // No need to clear all buckets - they won't be used until they're required
        // at which point they'll too be cleared.
        unchecked {
            for (uint256 i = 0; i < _nBuckets; ++i) {
                // Set to a non-zero dust amount
                buckets[i] = 1;
            }
        }

        emit ConfigSet(_periodDuration, _nBuckets, _cap);
    }

    modifier onlyProxy() {
        if (msg.sender != address(proxy)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
