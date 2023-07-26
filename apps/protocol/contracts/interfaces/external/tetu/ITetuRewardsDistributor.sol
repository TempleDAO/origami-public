pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/tetu/ITetuRewardsDistributor.sol)

interface ITetuRewardsDistributor {
    function claim(uint256 _tokenId) external returns (uint256);  
    function claimable(uint256 _tokenId) external view returns (uint256);
    function claimMany(uint256[] memory _tokenIds) external returns (bool);

    function checkpoint() external;
    function checkpointTotalSupply() external;

    /// @dev Tokens per week stored on checkpoint call. Predefined array size = max weeks size
    function tokensPerWeek(uint256 week) external view returns (uint256);

    /// @dev Last checkpoint time
    function lastTokenTime() external view returns (uint256);

    /// @dev Ve supply checkpoint time cursor
    function timeCursor() external view returns (uint256);

    /// @dev Timestamp when this contract was inited
    function startTime() external view returns (uint256);

    /// @dev veID => week cursor stored on the claim action
    function timeCursorOf(uint256 id) external view returns (uint256);

    /// @dev veID => epoch stored on the claim action
    function userEpochOf(uint256 id) external view returns (uint256);

    /// @dev Search in the loop given timestamp through ve user points history.
    ///      Return minimal possible epoch.
    function findTimestampUserEpoch(
        address _ve,
        uint256 tokenId,
        uint256 _timestamp,
        uint256 maxUserEpoch
    ) external view returns (uint256);
}