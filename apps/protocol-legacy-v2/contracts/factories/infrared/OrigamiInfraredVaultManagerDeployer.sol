pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (factories/infrared/OrigamiInfraredVaultManagerDeployer.sol)

import { OrigamiInfraredVaultManager } from "contracts/investments/infrared/OrigamiInfraredVaultManager.sol";

contract OrigamiInfraredVaultManagerDeployer {
    /**
     * @notice Deploys a new `OrigamiInfraredVaultManager` contract.
     */
    function deploy(
        address owner,
        address vault,
        address asset,
        address infraredRewardVault,
        address feeCollector,
        address swapper,
        uint16 performanceFeeBps
    ) external returns (OrigamiInfraredVaultManager deployedAddress) {
        return new OrigamiInfraredVaultManager(
            owner,
            vault,
            asset,
            infraredRewardVault,
            feeCollector, 
            swapper,
            performanceFeeBps
        );
    }
}
