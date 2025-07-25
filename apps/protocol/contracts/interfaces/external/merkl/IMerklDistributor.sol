pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/merkl/IMerklDistributor.sol)

interface IMerklDistributor {
    /// @notice Toggles whitelisting for a given user and a given operator
    /// @dev When an operator is whitelisted for a user, the operator can claim rewards on behalf of the user
    function toggleOperator(address user, address operator) external;

    /// @notice Sets a recipient for a user claiming rewards for a token
    /// @dev This is an optional functionality and if the `recipient` is set to the zero address, then
    /// the user will still accrue all rewards to its address
    /// @dev Users may still specify a different recipient when they claim token rewards with the
    /// `claimWithRecipient` function
    function setClaimRecipient(address recipient, address token) external;

    /// @notice Claims rewards for a given set of users
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// who provides the proof and pays the gas: `msg.sender` is used only for addresses that require a trusted operator
    /// @param users Recipient of tokens
    /// @param tokens ERC20 claimed
    /// @param amounts Amount of tokens that will be sent to the corresponding users
    /// @param proofs Array of hashes bridging from a leaf `(hash of user | token | amount)` to the Merkle root
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;

    /// @notice Same as the function above except that for each token claimed, the caller may set different
    /// recipients for rewards and pass arbitrary data to the reward recipient on claim
    /// @dev Only a `msg.sender` calling for itself can set a different recipient for the token rewards
    /// within the context of a call to claim
    /// @dev Non-zero recipient addresses given by the `msg.sender` can override any previously set reward address
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes[] memory datas
    ) external;
}
