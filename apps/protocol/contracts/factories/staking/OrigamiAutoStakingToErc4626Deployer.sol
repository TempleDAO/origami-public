pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/factories/staking/OrigamiAutoStakingToErc4626Deployer.sol)

import { OrigamiAutoStakingToErc4626 } from "contracts/investments/staking/OrigamiAutoStakingToErc4626.sol";
import { OrigamiAutoStaking } from "contracts/investments/staking/OrigamiAutoStaking.sol";

/**
 * @title Origami AutoStaking (to ERC4626) Deployer
 * @notice Responsible for deploying an instance of OrigamiAutoStakingToErc4626 for registration in a factory
 */
contract OrigamiAutoStakingToErc4626Deployer {
    /// @notice The primary ERC20 which is claimed from the underlying reward vault
    /// @dev eg iBGT in the case of Infrared reward vaults
    address public immutable underlyingPrimaryRewardToken;

    /// @notice The primary ERC4626 vault which is rewarded to the users of the Origami reward vault
    /// @dev eg oriBGT in the case of Infrared reward vaults
    address public immutable primaryRewardToken4626;

    constructor(address underlyingPrimaryRewardToken_, address primaryRewardToken4626_) {
        underlyingPrimaryRewardToken = underlyingPrimaryRewardToken_;
        primaryRewardToken4626 = primaryRewardToken4626_;
    }

    /// @notice Deploys a new `OrigamiAutoStakingToErc4626` contract.
    function deploy(
        address owner,
        address stakingToken,
        address rewardsVault,
        uint256 performanceFeeBps,
        address feeCollector,
        uint256 rewardsDuration,
        address swapper
    ) external returns (OrigamiAutoStakingToErc4626 deployedAddress) {
        return new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: owner,
                stakingToken: stakingToken,
                primaryRewardToken: primaryRewardToken4626,
                rewardsVault: rewardsVault,
                primaryPerformanceFeeBps: performanceFeeBps,
                feeCollector: feeCollector,
                rewardsDuration: rewardsDuration,
                swapper: swapper
            }),
            underlyingPrimaryRewardToken
        );
    }
}
