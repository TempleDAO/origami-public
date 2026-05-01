pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/factories/swappers/OrigamiSwapperWithLiquidityManagementDeployer.sol)

import { OrigamiSwapperWithLiquidityManagement } from "contracts/common/swappers/OrigamiSwapperWithLiquidityManagement.sol";

/**
 * @title Origami Swapper With Liquidity Management Deployer
 * @notice Responsible for deploying an instance of OrigamiSwapperWithLiquidityManagement for use in a factory
 */
contract OrigamiSwapperWithLiquidityManagementDeployer {
    /// @notice Deploys a new `OrigamiSwapperWithLiquidityManagement` contract.
    function deploy(
        address owner,
        address asset
    ) external returns (OrigamiSwapperWithLiquidityManagement deployedAddress) {
        return new OrigamiSwapperWithLiquidityManagement(
            owner,
            asset
        );
    }
}
