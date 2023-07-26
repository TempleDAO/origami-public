pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiInvestmentVault.sol)

import {IOrigamiInvestment} from "./IOrigamiInvestment.sol";
import {IRepricingToken} from "../common/IRepricingToken.sol";

/**
 * @title Origami Investment Vault
 * @notice A repricing Origami Investment. Users invest in the underlying protocol and are allocated shares.
 * Origami will apply the supplied token into the underlying protocol in the most optimal way.
 * The pricePerShare() will increase over time as upstream rewards are claimed by the protocol added to the reserves.
 * This makes the Origami Investment Vault auto-compounding.
 */
interface IOrigamiInvestmentVault is IOrigamiInvestment, IRepricingToken {
    /**
     * @notice The performance fee which Origami takes from harvested rewards before compounding into reserves.
     */
    function performanceFee() external view returns (uint128 numerator, uint128 denominator);
}
