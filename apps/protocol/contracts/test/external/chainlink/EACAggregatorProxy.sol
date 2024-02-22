// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

contract EACAggregatorProxy {
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
    }

    function changeGasAnswer(int256 _gasWei) external {
        answer = _gasWei;
    }

    function latestRoundData()
        public
        view
        returns (
            uint80 _roundId,
            int256 _answer,
            uint256 _startedAt,
            uint256 _updatedAt,
            uint80 _answeredInRound
        )
    {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
