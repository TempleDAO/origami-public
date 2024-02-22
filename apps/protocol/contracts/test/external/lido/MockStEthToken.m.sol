pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";
import { MintableToken } from "contracts/common/MintableToken.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CompoundedInterest } from "contracts/libraries/CompoundedInterest.sol";

// A very basic stETH implementation where the pooled assets per share (stETH/ETH)
// rate increases by a compound interest every second
// NB: Might be slightly off with rounding in this approach
contract MockStEthToken is IStETH, MintableToken {
    using OrigamiMath for uint256;
    using Address for address payable;

    struct AccumulatorData {
        uint256 accumulatorUpdatedAt;
        uint256 accumulator;
        uint256 checkpoint;
        uint96 interestRate;
        uint256 totalSubmitted;
    }

    AccumulatorData public accumulatorData;

    constructor(
        address _initialOwner,
        uint96 _interestRate
    ) MintableToken("Liquid staked Ether 2.0", "stETH", _initialOwner) {
        accumulatorData = AccumulatorData(block.timestamp, 1e27, 0, _interestRate, 0);
    }

    /**
     * @notice Send funds to the pool with optional _referral parameter
     * @dev This function is alternative way to submit funds. Supports optional referral address.
     * @return sharesAmount Amount of StETH shares generated
     */
    function submit(address /*_referral*/) external payable returns (uint256 sharesAmount) {
        require(msg.value != 0, "ZERO_DEPOSIT");

        AccumulatorData memory cache = _checkpoint(accumulatorData);
        sharesAmount = _getSharesByPooledEth(msg.value, cache);
        accumulatorData.checkpoint += msg.value;
        accumulatorData.totalSubmitted += sharesAmount;

        // Mint shares to the user and add to the total reserves
        _mint(msg.sender, sharesAmount);
    }

    function recoverNative(uint256 amount, address payable recipient) external onlyElevatedAccess {
        recipient.sendValue(amount);
    }

    function balanceOf(address user) public override(ERC20,IERC20)  view returns (uint256) {
        (AccumulatorData memory cache,) = _getCache(accumulatorData);
        return _getPooledEthByShares(super.balanceOf(user), cache);
    }

    /**
     * @return the amount of shares that corresponds to `_ethAmount` protocol-controlled Ether.
     */
    function getSharesByPooledEth(uint256 _ethAmount) public override view returns (uint256) {
        (AccumulatorData memory cache,) = _getCache(accumulatorData);
        return _getSharesByPooledEth(_ethAmount, cache);
    }

    /**
     * @return the amount of Ether that corresponds to `_sharesAmount` token shares.
     */
    function getPooledEthByShares(uint256 _sharesAmount) external override view returns (uint256) {
        (AccumulatorData memory cache,) = _getCache(accumulatorData);
        return _getPooledEthByShares(_sharesAmount, cache);
    }

    function _getSharesByPooledEth(
        uint256 _ethAmount,
        AccumulatorData memory cache
    ) internal pure returns (uint256) {
        return cache.checkpoint == 0
            ? _ethAmount
            : _ethAmount.mulDiv(cache.totalSubmitted, cache.checkpoint, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function _getPooledEthByShares(
        uint256 _sharesAmount,
        AccumulatorData memory cache
    ) internal pure returns (uint256) {
    return cache.totalSubmitted == 0
        ? _sharesAmount
        : _sharesAmount.mulDiv(cache.checkpoint, cache.totalSubmitted, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function _getCache(AccumulatorData storage data) internal view returns (AccumulatorData memory cache, bool dirty) {
        cache.accumulatorUpdatedAt = data.accumulatorUpdatedAt;
        cache.accumulator = data.accumulator;
        cache.checkpoint = data.checkpoint;
        cache.interestRate = data.interestRate;
        cache.totalSubmitted = data.totalSubmitted;

        // Only compound if we're on a new block
        uint256 _timeElapsed;
        unchecked {
            _timeElapsed = block.timestamp - cache.accumulatorUpdatedAt;
        }

        if (_timeElapsed > 0) {
            dirty = true;

            // Compound the accumulator
            uint256 newAccumulator = CompoundedInterest.continuouslyCompounded(
                cache.accumulator,
                _timeElapsed,
                cache.interestRate
            );

            cache.checkpoint = newAccumulator.mulDiv(
                cache.checkpoint,
                cache.accumulator,
                OrigamiMath.Rounding.ROUND_UP
            );

            cache.accumulator = newAccumulator;
        }
    }

    function _updatedBalance(AccumulatorData storage data) internal view returns (uint256 newBalance) {
        (AccumulatorData memory cache,) = _getCache(data);
        return cache.checkpoint;
    }

    function _checkpoint(AccumulatorData storage data) internal returns (AccumulatorData memory cache) {
        bool dirty;
        (cache, dirty) = _getCache(data);
        if (dirty) {
            data.accumulatorUpdatedAt = block.timestamp;
            data.accumulator = cache.accumulator;
            data.checkpoint = cache.checkpoint;
        }
    }
}
