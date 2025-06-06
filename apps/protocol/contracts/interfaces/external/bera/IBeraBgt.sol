pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/bera/IBeraBgt.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IBeraBgt is IERC20, IERC20Metadata, IVotes {
    /**
     * @notice Queues a new boost of the validator with an amount of BGT from `msg.sender`.
     * @dev Reverts if `msg.sender` does not have enough unboosted balance to cover amount.
     * @param pubkey The pubkey of the validator to be boosted.
     * @param amount The amount of BGT to use for the queued boost.
     */
    function queueBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Cancels a queued boost of the validator removing an amount of BGT for `msg.sender`.
     * @dev Reverts if `msg.sender` does not have enough queued balance to cover amount.
     * @param pubkey The pubkey of the validator to cancel boost for.
     * @param amount The amount of BGT to remove from the queued boost.
     */
    function cancelBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Boost the validator with an amount of BGT from `user`.
     * @param user The address of the user boosting.
     * @param pubkey The pubkey of the validator to be boosted.
     * @return bool False if amount is zero or if enough time has not passed, otherwise true.
     */
    function activateBoost(address user, bytes calldata pubkey) external returns (bool);

    /**
     * @notice Queues a drop boost of the validator removing an amount of BGT for sender.
     * @dev Reverts if `user` does not have enough boosted balance to cover amount.
     * @param pubkey The pubkey of the validator to remove boost from.
     * @param amount The amount of BGT to remove from the boost.
     */
    function queueDropBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Cancels a queued drop boost of the validator removing an amount of BGT for sender.
     * @param pubkey The pubkey of the validator to cancel drop boost for.
     * @param amount The amount of BGT to remove from the queued drop boost.
     */
    function cancelDropBoost(bytes calldata pubkey, uint128 amount) external;

    /**
     * @notice Drops an amount of BGT from an existing boost of validator by user.
     * @param user The address of the user to drop boost from.
     * @param pubkey The pubkey of the validator to remove boost from.
     * @return bool False if amount is zero or if enough time has not passed, otherwise true.
     */
    function dropBoost(address user, bytes calldata pubkey) external returns (bool);

    /**
     * @notice Returns the amount of BGT queued up to be used by an account to boost a validator.
     * @param account The address of the account boosting.
     * @param pubkey The pubkey of the validator being boosted.
     */
    function boostedQueue(
        address account,
        bytes calldata pubkey
    )
        external
        view
        returns (uint32 blockNumberLast, uint128 balance);

    /// @notice The mapping of queued drop boosts on a validator by an account
    function dropBoostQueue(
        address account,
        bytes calldata pubkey
    )
        external
        view
        returns (uint32 blockNumberLast, uint128 balance);

    /**
     * @notice Returns the amount of BGT queued up to be used by an account for boosts.
     * @param account The address of the account boosting.
     */
    function queuedBoost(address account) external view returns (uint128);

    /**
     * @notice Returns the amount of BGT used by an account to boost a validator.
     * @param account The address of the account boosting.
     * @param pubkey The pubkey of the validator being boosted.
     */
    function boosted(address account, bytes calldata pubkey) external view returns (uint128);

    /**
     * @notice Returns the amount of BGT used by an account for boosts.
     * @param account The address of the account boosting.
     */
    function boosts(address account) external view returns (uint128);

    /**
     * @notice Returns the amount of BGT attributed to the validator for boosts.
     * @param pubkey The pubkey of the validator being boosted.
     */
    function boostees(bytes calldata pubkey) external view returns (uint128);

    /**
     * @notice Returns the total boosts for all validators.
     */
    function totalBoosts() external view returns (uint128);

    /**
     * @notice Returns the normalized boost power for the validator given outstanding boosts.
     * @dev Used by distributor get validator boost power.
     * @param pubkey The pubkey of the boosted validator.
     */
    function normalizedBoost(bytes calldata pubkey) external view returns (uint256);

    /**
     * @notice Returns the unboosted balance of an account.
     * @param account The address of the account.
     */
    function unboostedBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Redeem the BGT token for the native token at a 1:1 rate.
     * @param receiver The receiver's address who will receive the native token.
     * @param amount The amount of BGT to redeem.
     */
    function redeem(address receiver, uint256 amount) external;

    /**
     * @notice The block delay for activating boosts.
     */
    function activateBoostDelay() external returns (uint32);

    /**
     * @notice The block delay for dropping boosts.
     */ 
    function dropBoostDelay() external returns (uint32);
}
