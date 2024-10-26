pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/aave/aave-v3-periphery/IAaveV3RewardsController.sol)

interface IAaveV3RewardsController {
  /**
   * @dev Claims all rewards for a user to the desired address, on all the assets of the pool, accumulating the pending rewards
   * @param assets The list of assets to check eligible distributions before claiming rewards
   * @param to The address that will be receiving the rewards
   * @return rewardsList List of addresses of the reward tokens
   * @return claimedAmounts List that contains the claimed amount per reward, following same order as "rewardList"
   **/
  function claimAllRewards(
    address[] calldata assets,
    address to
  ) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
