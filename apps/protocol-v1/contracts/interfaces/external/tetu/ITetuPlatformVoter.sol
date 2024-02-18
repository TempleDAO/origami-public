// SPDX-License-Identifier: MIT
// Origami (interfaces/external/tetu/IPlatformVoter.sol)

pragma solidity 0.8.17;

interface ITetuPlatformVoter {

    enum AttributeType {
        UNKNOWN,
        INVEST_FUND_RATIO,
        GAUGE_RATIO,
        STRATEGY_COMPOUND
    }

    struct Vote {
        AttributeType _type;
        address target;
        uint weight;
        uint weightedValue;
        uint timestamp;
    }

    function poke(uint tokenId) external;
    function voteBatch(
        uint tokenId,
        AttributeType[] memory types,
        uint[] memory values,
        address[] memory targets
    ) external; 
    function vote(uint tokenId, AttributeType _type, uint value, address target) external;
    function reset(uint tokenId, uint[] memory types, address[] memory targets) external;
    
    // Views
    function veVotes(uint veId) external view returns (Vote[] memory);
    function veVotesLength(uint veId) external view returns (uint);
}
