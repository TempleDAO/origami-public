pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/erc4626/IOrigamiDelegated4626Vault.sol)

import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";

/** 
 * @title Origami Delegated ERC4626 Vault
 * @notice An Origami ERC4626 Vault, which delegates the handling of deposited assets
 * to a manager
 */
interface IOrigamiDelegated4626Vault is IOrigamiErc4626 {
    event TokenPricesSet(address indexed _tokenPrices);
    event ManagerSet(address indexed manager);
    event PerformanceFeeSet(uint256 fee);

    /**
     * @notice Set the helper to calculate current off-chain/subgraph integration
     */
    function setTokenPrices(address tokenPrices) external;

    /**
     * @notice Set the Origami delegated manager 
     */
    function setManager(address manager) external;

    /**
     * @notice The performance fee to Origami treasury
     * Represented in basis points
     */
    function performanceFeeBps() external view returns (uint48);

    /**
     * @notice The helper contract to retrieve Origami USD prices
     * @dev Required for off-chain/subgraph integration
     */
    function tokenPrices() external view returns (ITokenPrices);

    /**
     * @notice The Origami contract managing the application of
     * the deposit tokens into the underlying protocol
     */
    function manager() external view returns (address);
}
