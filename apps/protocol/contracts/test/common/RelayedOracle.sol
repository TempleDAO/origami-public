pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

/// @notice Answer's relayed from mainnet to testnet
contract RelayedOracle is IAggregatorV3Interface {
    Answer public _answer;
    uint8 public _decimals;

    string public description;

    struct Answer {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(string memory __description, Answer memory __answer, uint8 __decimals) {
        description = __description;
        _answer = __answer;
        _decimals = __decimals;
    }

    function setAnswer(Answer memory __answer) external {
        _answer = __answer;
        emit AnswerUpdated(__answer.answer, __answer.roundId, __answer.updatedAt);
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
            _answer.updatedAt,
            _answer.answeredInRound
        );
    }

    function decimals() external override view returns (uint8) {
        return _decimals;
    }

    function latestAnswer() external view returns (int256) {
        return _answer.answer;
    }
}
