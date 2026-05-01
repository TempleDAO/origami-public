pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OpalManager } from "contracts/investments/opal/OpalManager.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";

import {
    MockMoneyMarketOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockMoneyMarketOpalAdapter.m.sol";
import { MockSwapPlugin } from "test/foundry/mocks/common/bundler/plugins/MockSwapPlugin.m.sol";

import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { Call } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";

import { OpalManagerTestBase } from "test/foundry/unit/investments/opal/OpalManager.t.sol";

contract OpalManagerTestBundler is OpalManagerTestBase {
    MockMoneyMarketOpalAdapter internal mockMMAdapter;

    MockSwapPlugin internal mockSwapPlugin;

    function setUp() public override {
        super.setUp();

        mockMMAdapter = MockMoneyMarketOpalAdapter(createInstance());
        vm.label(address(mockMMAdapter), "ADAPTER_MM.1");
        mockSwapPlugin = new MockSwapPlugin(address(manager));
        vm.label(address(mockSwapPlugin), "ADAPTER_SWAP.1");

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT1, address(mockMMAdapter.mockMorpho()), 1_000_000e18);

        vm.startPrank(origamiMultisig);
        manager.setPluginApproved(address(mockMMAdapter), true);
        manager.setPluginApproved(address(mockSwapPlugin), true);
        vm.stopPrank();
    }

    function createInstance() internal returns (address instance) {
        vm.startPrank(origamiMultisig);
        instance = manager.addAdapter(
            address(adapterImpl2),
            "TEST.1",
            adapterImpl2.encodeImmutableArgs(ASSET1, DEBT1, "GROUP_1"),
            adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
        );
        vm.stopPrank();
    }

    function expectBs(uint256 collateralAmount, uint256 debtAmount) internal view {
        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, collateralAmount);
        expectArr(combinedLiabilities, debtAmount);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 1);
        expectArr(perAdapterBalanceSheet[0].assets, collateralAmount);
        assertEq(perAdapterBalanceSheet.length, 1);
        expectArr(perAdapterBalanceSheet[0].liabilities, debtAmount);
    }

    function bundleSupply(uint256 supplyAmount) internal {
        Call[] memory bundle = new Call[](1);
        bundle[0] = createCall(
            mockMMAdapter,
            abi.encodeWithSelector(MockMoneyMarketOpalAdapter.supplyCollateral.selector, supplyAmount, "")
        );

        vm.startPrank(overlord);
        deal(ASSET1, address(mockMMAdapter), supplyAmount);
        IERC20(ASSET1).approve(address(mockMMAdapter), supplyAmount);

        vm.expectEmit(address(manager));
        emit IOpalManager.Multicall();
        manager.multicall(bundle);
    }

    function test_bundle_supply() public {
        uint256 supplyAmount = 33e18;
        bundleSupply(supplyAmount);

        expectBs(supplyAmount, 0);
    }

    function test_bundle_withCallback_condensed() public {
        uint256 supplyAmount = 10e18;
        uint256 borrowAmount = 15e18;

        bundleSupply(supplyAmount);

        // Dish out some funds to the mock swapper
        deal(ASSET1, address(mockSwapPlugin), supplyAmount);

        Call[] memory innerBundle = new Call[](2);
        innerBundle[0] = createCall( // MMAdapter: Borrow, receiver: SwapAdapter
            mockMMAdapter,
            abi.encodeWithSelector(MockMoneyMarketOpalAdapter.borrow.selector, borrowAmount, address(mockSwapPlugin))
        );
        innerBundle[1] = createCall( // SwapAdapter: Swap debtToken => collateralToken, receiver: MMAdapter
            mockSwapPlugin,
            abi.encodeWithSelector(
                MockSwapPlugin.swap.selector, DEBT1, borrowAmount, ASSET1, supplyAmount, address(mockMMAdapter)
            )
        );
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        Call[] memory outerBundle = new Call[](1);
        // MMAdapter: supply collateralToken, but runs the innerBundle via the callback first
        // which borrows and swaps
        outerBundle[0] = createCall(
            mockMMAdapter,
            abi.encodeWithSelector(
                MockMoneyMarketOpalAdapter.supplyCollateral.selector, supplyAmount, encodedInnerBundle
            ),
            keccak256(encodedInnerBundle)
        );

        vm.startPrank(overlord);
        manager.multicall(outerBundle);

        expectBs(supplyAmount * 2, borrowAmount);
        assertEq(mockMMAdapter.currentLtv(), 0.75e18);
    }

    function test_bundle_withCallback_expanded() public {
        uint256 supplyAmount = 10e18;
        uint256 borrowAmount = 15e18;

        bundleSupply(supplyAmount);

        // Dish out some funds to the mock swapper
        deal(ASSET1, address(mockSwapPlugin), supplyAmount);

        Call[] memory innerBundle = new Call[](4);
        innerBundle[0] = createCall( // MMAdapter: Borrow, receiver: MMAdapter
            mockMMAdapter,
            abi.encodeWithSelector(MockMoneyMarketOpalAdapter.borrow.selector, borrowAmount, address(mockMMAdapter))
        );
        innerBundle[1] = createCall( // MMAdapter: Transfer debtToken => SwapAdapter
            mockMMAdapter,
            abi.encodeWithSelector(
                IOrigamiBundlerPlugin.erc20Transfer.selector, DEBT1, address(mockSwapPlugin), borrowAmount
            )
        );
        innerBundle[2] = createCall( // SwapAdapter: Swap debtToken => collateralToken, receiver: SwapAdapter
            mockSwapPlugin,
            abi.encodeWithSelector(
                MockSwapPlugin.swap.selector, DEBT1, borrowAmount, ASSET1, supplyAmount, address(mockSwapPlugin)
            )
        );
        innerBundle[3] = createCall( // SwapAdapter: Swap debtToken => collateralToken, receiver: MMAdapter
            mockSwapPlugin,
            abi.encodeWithSelector(
                IOrigamiBundlerPlugin.erc20Transfer.selector, ASSET1, address(mockMMAdapter), supplyAmount
            )
        );
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        Call[] memory outerBundle = new Call[](1);
        // MMAdapter: supply collateralToken, but runs the innerBundle via the callback first
        // which borrows and swaps with intermediate ERC20 transfers
        outerBundle[0] = createCall(
            mockMMAdapter,
            abi.encodeWithSelector(
                MockMoneyMarketOpalAdapter.supplyCollateral.selector, supplyAmount, encodedInnerBundle
            ),
            keccak256(encodedInnerBundle)
        );

        vm.startPrank(overlord);
        manager.multicall(outerBundle);

        expectBs(supplyAmount * 2, borrowAmount);
        assertEq(mockMMAdapter.currentLtv(), 0.75e18);
    }
}
