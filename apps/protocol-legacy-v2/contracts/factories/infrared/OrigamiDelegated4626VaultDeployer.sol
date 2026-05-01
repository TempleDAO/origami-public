pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (factories/infrared/OrigamiDelegated4626VaultDeployer.sol)

import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OrigamiDelegated4626VaultDeployer {
    /**
     * @notice Deploys a new `OrigamiDelegated4626Vault` contract.
     */
    function deploy(
        address owner,
        string calldata name,
        string calldata symbol,
        address asset,
        address tokenPrices
    ) external returns (OrigamiDelegated4626Vault deployedAddress) {
        return new OrigamiDelegated4626Vault(
            owner,
            name,
            symbol,
            IERC20(asset),
            tokenPrices
        );
    }
}
