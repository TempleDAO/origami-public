pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

contract DummyOracle is IAggregatorV3Interface {
    Answer public _answer;
    uint8 public _decimals;

    struct Answer {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAtLag;
        uint80 answeredInRound;
    }

    event AnswerSet(Answer answer);

    constructor(Answer memory __answer, uint8 __decimals) {
        _answer = __answer;
        _decimals = __decimals;
    }

    function setAnswer(Answer memory __answer) external {
        _answer = __answer;
        emit AnswerSet(__answer);
    }

    function latestRoundData() external override view returns (
        uint80 /*roundId*/,
        int256 /*answer*/,
        uint256 /*startedAt*/,
        uint256 /*updatedAt*/,
        uint80 /*answeredInRound*/
    ) {
        return (
            _answer.roundId, 
            _answer.answer, 
            _answer.startedAt, 
            block.timestamp - _answer.updatedAtLag,
            _answer.answeredInRound
        );
    }

    function decimals() external override view returns (uint8) {
        return _decimals;
    }
}
