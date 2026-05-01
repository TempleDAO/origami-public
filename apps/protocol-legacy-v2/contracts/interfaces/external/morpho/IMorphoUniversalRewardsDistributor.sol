pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/morpho/IMorphoUniversalRewardsDistributor.sol)

interface IMorphoUniversalRewardsDistributor {
    /// @notice Claims rewards.
    /// @param account The address to claim rewards for.
    /// @param reward The address of the reward token.
    /// @param claimable The overall claimable amount of token rewards.
    /// @param proof The merkle proof that validates this claim.
    /// @return amount The amount of reward token claimed.
    /// @dev Anyone can claim rewards on behalf of an account.
    function claim(address account, address reward, uint256 claimable, bytes32[] calldata proof)
        external
        returns (uint256 amount);
}