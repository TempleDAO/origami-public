pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/oracle/OrigamiCrossRateOracle.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title OrigamiCrossRateOracle
 * @notice A derived cross rate oracle price, by dividing baseOracle / quotedOracle
 * @dev Both baseOracle and quotedOracle prices are checked against a valid range (eg a peg). 
 * If outside of that range, the latestPrice() function will revert.
 */
contract OrigamiCrossRateOracle is OrigamiOracleBase {
    using OrigamiMath for uint256;

    /**
     * @notice The oracle used for the base asset price
     * ie the LHS in a XXX/YYY quote
     * @dev For [DAI/USDC] = [DAI/USD]/[USDC/USD], baseOracle would point to the [DAI/USD] oracle
     */
    IOrigamiOracle public immutable baseAssetOracle;

    /**
     * @notice The oracle used for the quote asset price
     * ie the RHS in a XXX/YYY quote
     * @dev For [DAI/USDC] = [DAI/USD]/[USDC/USD], quotedOracle would point to the [USDC/USD] oracle
     */
    IOrigamiOracle public immutable quoteAssetOracle;

    constructor (
        string memory _description,
        address _baseAssetAddress,
        address _baseAssetOracle,
        uint8 _baseAssetDecimals,
        address _quoteTokenAddress,
        address _quoteAssetOracle,
        uint8 _quoteAssetDecimals
    )
        OrigamiOracleBase(
            _description, 
            _baseAssetAddress, 
            _baseAssetDecimals, 
            _quoteTokenAddress, 
            _quoteAssetDecimals
        )
    {
        baseAssetOracle = IOrigamiOracle(_baseAssetOracle);
        quoteAssetOracle = IOrigamiOracle(_quoteAssetOracle);
    }

    /**
     * @notice Return the latest oracle price, to `decimals` precision
     * @dev This may still revert - eg if deemed stale, div by 0, negative price
     * @param priceType What kind of price - Spot or Historic
     * @param roundingMode Round the price at each intermediate step such that the final price rounds in the specified direction.
     */
    function latestPrice(
        PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) public override view returns (uint256) {
        // baseOracle (the numerator) price follows the requested roundingMode
        // So if roundDown, then we want the nuemrator to be lower (round down)
        uint256 _numerator = baseAssetOracle.latestPrice(
            priceType, 
            roundingMode
        );

        // quotedOracle (the denominator) price follows the opposite roundingMode
        // So if roundDown, then we want the denominator to be higher (round up)
        uint256 _denominator = quoteAssetOracle.latestPrice(
            priceType, 
            roundingMode == OrigamiMath.Rounding.ROUND_DOWN ? OrigamiMath.Rounding.ROUND_UP : OrigamiMath.Rounding.ROUND_DOWN
        );

        if (_denominator == 0) revert InvalidPrice(address(quoteAssetOracle), int256(_denominator));

        // Final price follows the requested roundingMode
        return _numerator.mulDiv(precision, _denominator, roundingMode);
    }
}
