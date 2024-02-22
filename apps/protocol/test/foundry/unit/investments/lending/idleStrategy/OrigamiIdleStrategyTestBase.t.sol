pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyIdleStrategy } from "contracts/test/investments/lovToken/DummyIdleStrategy.m.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";
import { OrigamiIdleStrategyManager } from "contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol";

contract OrigamiIdleStrategyTestBase is OrigamiTest {
    DummyMintableToken public asset;
    DummyIdleStrategy public idleStrategy;
    OrigamiIdleStrategyManager public manager;

    uint128 public availableBps = 8_000; // 80%

    function setUp() public {
        asset = new DummyMintableToken(origamiMultisig, "asset", "asset", 18);
        idleStrategy = new DummyIdleStrategy(origamiMultisig, address(asset), availableBps);
        manager = new OrigamiIdleStrategyManager(origamiMultisig, address(asset));
    }

    function checkLatestAssetBalances(uint256 expectedAmount) internal {
        IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = manager.latestAssetBalances();
        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(asset));
        assertEq(assetBalances[0].balance, expectedAmount);
    }

    function checkCheckpointAssetBalances(uint256 expectedAmount) internal {
        IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = manager.checkpointAssetBalances();
        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(asset));
        assertEq(assetBalances[0].balance, expectedAmount);
    }

    function addThresholds(uint256 depositThreshold, uint256 withdrawalBuffer) internal {
        manager.setIdleStrategy(address(idleStrategy));
        manager.setDepositsEnabled(true);
        manager.setThresholds(depositThreshold, withdrawalBuffer);
    }

    function allocate(uint256 amount) internal {
        deal(address(asset), origamiMultisig, amount);
        asset.approve(address(manager), amount);
        manager.allocate(amount);
    }
}
