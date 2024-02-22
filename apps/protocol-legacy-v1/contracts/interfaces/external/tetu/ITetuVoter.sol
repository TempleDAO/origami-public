pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/tetu/ITetuVoter.sol)

interface ITetuVoter {
    /// @dev Remove all votes for given tokenId.
    ///      Ve token should be able to remove votes on transfer/withdraw
    function reset(uint256 tokenId) external;

    /// @dev Vote for given pools using a vote power of given tokenId. Reset previous votes.
    function vote(uint256 tokenId, address[] calldata _vaultVotes, int256[] calldata _weights) external;

    function validVaultsLength() external view returns (uint256);
    function validVaults(uint256 id) external view returns (address);

    /// @dev veID => Last vote timestamp
    function lastVote(uint256 id) external view returns (uint256);

    /// @dev nft => vault => votes
    function votes(uint256 id, address vault) external view returns (int256);
}