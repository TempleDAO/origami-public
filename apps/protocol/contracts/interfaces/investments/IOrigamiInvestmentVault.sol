pragma solidity ^0.8.17;
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
     * @notice Annual Percentage Rate (APR) in basis points for this investment,
     * based on the projected rewards per share
     * @dev APR == [the total USD value of rewards (less fees) for one per year at current rates] / [USD value of the total share supply]
     */
    function apr() external view returns (uint256 aprBps);
}
