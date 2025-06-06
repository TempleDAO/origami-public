pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bera/IOrigamiBeraBgtProxy.sol)

import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";

/**
 * @title Origami Berachain BGT Proxy
 * @notice Apply actions on the non-transferrable BGT token
 * @dev Given BGT is non-transferrable, and that there may be new features we need to handle
 * this contract is a UUPS upgradeable contract.
 */
interface IOrigamiBeraBgtProxy {
    /**
     * @notice Recover any token other than the underlying erc4626 asset.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external;

    /**
     * @notice Set the allowance of any token spend
     */
    function setTokenAllowance(address token, address spender, uint256 amount) external;

    /**
     * @notice Redeem the BGT token for the native token at a 1:1 rate.
     * @param receiver The receiver's address who will receive the native token.
     * @param amount The amount of BGT to redeem.
     */
    function redeem(address receiver, uint256 amount) external;

    /**
     * @notice Delegate votes from the sender to `delegatee`.
     * @dev From OZ's ERC20Votes
     */
    function delegate(address delegatee) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  BGT VALIDATOR BOOSTS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
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
     * @notice Boost the validator with an amount of BGT from this contract.
     * @param pubkey The pubkey of the validator to be boosted.
     * @return bool False if amount is zero or if enough time has not passed, otherwise true.
     */
    function activateBoost(bytes calldata pubkey) external returns (bool);

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
     * @notice Drops an amount of BGT from an existing boost of validator by this contract
     * @param pubkey The pubkey of the validator to remove boost from.
     * @return bool False if amount is zero or if enough time has not passed, otherwise true.
     */
    function dropBoost(bytes calldata pubkey) external returns (bool);

    /**
     * @notice The Berachain governance token (BGT)
     */
    function bgt() external view returns (IBeraBgt);

    /**
     * @notice The current balance of the Berachain governance token (BGT)
     */
    function balance() external view returns (uint256);
}
