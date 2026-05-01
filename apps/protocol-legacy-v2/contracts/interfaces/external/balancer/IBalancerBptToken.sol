pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/balancer/IBalancerBptToken.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBalancerBptToken is IERC20 {
    /**
     * @notice Returns the effective BPT supply.
     *
     * @dev The Pool owes debt to the Protocol and the Pool's owner in the form of unminted BPT, which will be minted
     * immediately before the next join or exit. We need to take these into account since, even if they don't yet exist,
     * they will effectively be included in any Pool operation that involves BPT.
     *
     * In the vast majority of cases, this function should be used instead of `totalSupply()`.
     *
     * WARNING: since this function reads balances directly from the Vault, it is potentially subject to manipulation
     * via reentrancy. See https://forum.balancer.fi/t/reentrancy-vulnerability-scope-expanded/4345 for reference.
     *
     * To call this function safely, attempt to trigger the reentrancy guard in the Vault by calling a non-reentrant
     * function before calling `getActualSupply`. That will make the transaction revert in an unsafe context.
     * (See `whenNotInVaultContext` in `ManagedPoolSettings`).
    */
    function getActualSupply() external view returns (uint256);

    /**
     * @dev Returns the index of the Pool's BPT in the Pool tokens array (as returned by IVault.getPoolTokens).
    */
    function getBptIndex() external view returns (uint256);

    /**
     * @dev Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).
    */
    function getPoolId() external view returns (bytes32);
}
