pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/factories/swappers/OrigamiSwapperWithCallbackDeployer.sol)

import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";

/**
 * @title Origami Swapper With Callback Deployer
 * @notice Responsible for deploying an instance of OrigamiSwapperWithCallback for use in a factory
 */
contract OrigamiSwapperWithCallbackDeployer {
    /// @notice Deploys a new `OrigamiSwapperWithCallback` contract.
    function deploy(
        address owner
    ) external returns (OrigamiSwapperWithCallback deployedAddress) {
        return new OrigamiSwapperWithCallback(owner);
    }
}
