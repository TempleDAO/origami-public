pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/sky/OrigamiSuperSkyRewardsHarvester.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiSuperSkyManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSkyManager.sol";

interface IOrigamiSwapper {
    /// @notice The rewards harvester is granted access to recover reward tokens from
    /// the current swapper
    function recoverToken(address token, address to, uint256 amount) external;
}

/// @title Origami SKY+ Rewards Harvester
/// @notice Harvest SKY token rewards and reinvest in the Sky+ manager
contract OrigamiSuperSkyRewardsHarvester {
    /// @notice The SKY+ Manager
    IOrigamiSuperSkyManager public immutable MANAGER;

    /// @notice The SKY token
    IERC20 public immutable SKY;

    constructor(address _skyManager) {
        MANAGER = IOrigamiSuperSkyManager(_skyManager);
        SKY = MANAGER.SKY();
    }

    /// @notice Harvest any balance of SKY tokens in the swapper and reinvest
    /// As part of the claim
    function claimFarmRewards(uint32[] calldata farmIndexes, address incentivesReceiver) external {
        MANAGER.claimFarmRewards(farmIndexes, incentivesReceiver);

        address swapper = MANAGER.swapper();
        uint256 balance = SKY.balanceOf(swapper);
        if (balance > 0) {
            IOrigamiSwapper(swapper).recoverToken(address(SKY), address(MANAGER), balance);
            MANAGER.reinvest();
        }
    }
}
