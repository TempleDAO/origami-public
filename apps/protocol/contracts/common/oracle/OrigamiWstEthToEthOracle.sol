pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiWstEthToEthOracle.sol)

import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title OrigamiWstEthToEthOracle
 * @notice The Lido wstETH/ETH oracle price, derived from the wstETH/stETH * stETH/ETH
 * where stETH/ETH ratio is pulled from the stETH contract's `getPooledEthByShares()`
 */
contract OrigamiWstEthToEthOracle is OrigamiOracleBase {
    using OrigamiMath for uint256;

    /**
     * @notice The (rebasing) Lido staked ETH contract (stETH)
     */
    IStETH public immutable stEth;

    /**
     * @notice The stETH/ETH oracle
     */
    IOrigamiOracle public immutable stEthToEthOracle;

    constructor (
        string memory _description,
        address _wstEthAddress,
        uint8 _wstEthDecimals,
        address _ethAddress,
        uint8 _ethDecimals,
        address _stEth,
        address _stEthToEthOracle
    ) 
        OrigamiOracleBase(
            _description, 
            _wstEthAddress, 
            _wstEthDecimals, 
            _ethAddress, 
            _ethDecimals
        )
    {
        stEth = IStETH(_stEth);
        stEthToEthOracle = IOrigamiOracle(_stEthToEthOracle);
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
        // 1 wstETH to stETH
        price = stEth.getPooledEthByShares(precision);

        // Convert wstETH to ETH using the stEth/ETH oracle price
        price = price.mulDiv(
            stEthToEthOracle.latestPrice(priceType, roundingMode),
            precision,
            roundingMode
        );
    }
}
