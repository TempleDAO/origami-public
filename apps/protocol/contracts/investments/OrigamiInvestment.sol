pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiInvestment.sol)

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IOrigamiInvestment} from "../interfaces/investments/IOrigamiInvestment.sol";
import {MintableToken} from "../common/MintableToken.sol";

/**
 * @title Origami Investment
 * @notice Users invest in the underlying protocol and receive a number of this Origami investment in return.
 * Origami will apply the accepted investment token into the underlying protocol in the most optimal way.
 */
abstract contract OrigamiInvestment is IOrigamiInvestment, MintableToken, Pausable {
    constructor(
        string memory _name,
        string memory _symbol
    ) MintableToken(_name, _symbol) {
    }

    /** 
     * @notice Protocol can pause the investment.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /** 
     * @notice Protocol can unpause the investment.
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}
