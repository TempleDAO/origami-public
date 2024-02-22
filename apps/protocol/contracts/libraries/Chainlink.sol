pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/Chainlink.sol)

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @notice A helper library to safely query prices from Chainlink oracles and scale them 
 */
library Chainlink {
    using OrigamiMath for uint256;

    struct Config {
        IAggregatorV3Interface oracle;
        bool scaleDown;
        uint128 scalar;
    }

    /**
     * @notice Query a price from a Chainlink oracle interface and perform sanity checks
     * The oracle price is scaled to the expected Origami precision (18dp)
     */
    function price(
        Config memory self,
        uint256 stalenessThreshold,
        OrigamiMath.Rounding roundingMode
    ) internal view returns (uint256) {
        (uint80 roundId, int256 feedValue, , uint256 lastUpdatedAt, uint80 answeredInRound) = self.oracle.latestRoundData();

        // Check for staleness
		if (
            answeredInRound <= roundId && 
            block.timestamp - lastUpdatedAt > stalenessThreshold
        ) {
            revert IOrigamiOracle.StalePrice(address(self.oracle), lastUpdatedAt, feedValue);
        }

        // Check for negative price
        if (feedValue < 0) revert IOrigamiOracle.InvalidPrice(address(self.oracle), feedValue);

        return self.scaleDown 
            ? uint256(feedValue).scaleDown(self.scalar, roundingMode)
            : uint256(feedValue).scaleUp(self.scalar);
    }

    /**
     * @notice Calculate the scaling factor to convert the chainlink oracle decimals to
     * our targetDecimals (18dp)
     */
    function scalingFactor(
        IAggregatorV3Interface oracle,
        uint8 targetDecimals
    ) internal view returns (uint128 scalar, bool scaleDown) {
        uint8 oracleDecimals = oracle.decimals();

        unchecked {
            if (oracleDecimals <= targetDecimals) {
                // Scale up (no-op if sourcePrecision == pricePrecision)
                scalar = uint128(10) ** (targetDecimals - oracleDecimals);
            } else {
                // scale down
                scalar = uint128(10) ** (oracleDecimals - targetDecimals);
                scaleDown = true;
            }
        }
    }
}