pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibCall } from "solady/utils/LibCall.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import {
    IOrigamiBundlerPluginAaveV3Flash
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginAaveV3Flash.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginEntryPoint
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { OrigamiBundlerPluginAaveV3Flash } from "contracts/common/bundler/plugins/OrigamiBundlerPluginAaveV3Flash.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundlerPluginCore } from "contracts/common/bundler/plugins/OrigamiBundlerPluginCore.sol";
import { OrigamiBundlerPluginEntryPoint } from "contracts/common/bundler/plugins/OrigamiBundlerPluginEntryPoint.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";

contract MockPluginChecker is OrigamiBundlerPluginCore {
    error AmountNotMatching(uint256 expected, uint256 actual);

    function isApprovedBundler(
        address /*account*/
    )
        public
        pure
        override
        returns (bool)
    {
        return true;
    }

    function checkFlashloanAmounts(address aavePlugin, uint256 expectedAmount, uint256 expectedFee) external view {
        uint256 expected = expectedAmount + expectedFee;
        uint256 actual = IOrigamiBundlerPluginAaveV3Flash(aavePlugin).flashloanTotalAmountT();
        if (actual != expected) revert AmountNotMatching(expected, actual);
    }
}

contract OrigamiBundlerPluginAaveV3FlashTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    address internal constant POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address internal constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    OrigamiBundler internal bundler;
    OrigamiBundlerPluginAaveV3Flash internal plugin;
    MockPluginChecker internal checkerPlugin;
    OrigamiBundlerPluginEntryPoint internal entryPointPlugin;

    function setUp() public {
        fork("mainnet", 23_323_025);
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginAaveV3Flash(origamiMultisig, POOL_ADDRESS_PROVIDER);
        entryPointPlugin = new OrigamiBundlerPluginEntryPoint(origamiMultisig, PERMIT2_ADDRESS, WETH_ADDRESS);
        checkerPlugin = new MockPluginChecker();

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler), true);
        entryPointPlugin.setBundlerApproved(address(bundler), true);
        vm.stopPrank();
    }
}

contract OrigamiBundlerPluginAaveV3FlashTestAdmin is OrigamiBundlerPluginAaveV3FlashTestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertEq(address(plugin.ADDRESSES_PROVIDER()), POOL_ADDRESS_PROVIDER);
        assertEq(address(plugin.POOL()), POOL);
        assertEq(plugin.flashloanTotalAmountT(), 0);
        assertEq(plugin.flashloanFeeBps(), 5);
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginAaveV3Flash).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerPluginAaveV3FlashTestAccess is OrigamiBundlerPluginAaveV3FlashTestBase {
    function test_access_flashLoan() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        plugin.flashLoan(alice, 0, 0, "");

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        plugin.flashLoan(alice, 0, 0, "");
    }

    function test_access_executeOperation() public {
        expectElevatedAccess();
        plugin.executeOperation(new address[](0), new uint256[](0), new uint256[](0), alice, "");

        expectNoAccess(origamiMultisig);
        plugin.executeOperation(new address[](0), new uint256[](0), new uint256[](0), alice, "");

        expectNoAccess(address(bundler));
        plugin.executeOperation(new address[](0), new uint256[](0), new uint256[](0), alice, "");
    }
}

contract OrigamiBundlerPluginAaveV3FlashTestFlash is OrigamiBundlerPluginAaveV3FlashTestBase {
    error ReserveInactive();
    error InvalidFlashloanExecutorReturn();

    function test_flashLoan_failBadToken() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(ReserveInactive.selector));
        plugin.flashLoan(alice, 100_000e18, 1, "");
    }

    function test_flashLoan_failZeroAmount() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.flashLoan(DAI_ADDRESS, 0, 1, "");
    }

    function test_flashLoan_failNoCallbackData() public {
        vm.startPrank(address(bundler));
        vm.expectRevert();
        plugin.flashLoan(DAI_ADDRESS, 100_000e18, 1, "");
    }

    function test_flashLoan_failWhenCalledDirectly() public {
        uint256 flAmount = 100_000e18;

        Call[] memory innerBundle = mkArray(
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (DAI_ADDRESS, alice, flAmount)))
        );
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.IncorrectReenterHash.selector));
        plugin.flashLoan(DAI_ADDRESS, 100_000e18, 1, encodedInnerBundle);
    }

    function test_flashLoan_failNotRepaid() public {
        uint256 flAmount = 100_000e18;

        bytes memory encodedInnerBundle;
        {
            Call[] memory innerBundle = mkArray(
                createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (DAI_ADDRESS, alice, flAmount)))
            );
            encodedInnerBundle = abi.encode(innerBundle);
        }

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginAaveV3Flash.flashLoan, (DAI_ADDRESS, flAmount, 1, encodedInnerBundle)
                ),
                keccak256(encodedInnerBundle)
            )
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, DAI_ADDRESS, 100_050e18, 0)
        );
        IOrigamiBundler(bundler).multicall(outerBundle);
    }

    function test_flashLoan_success_single() public {
        uint256 flAmount = 100_000e18;

        uint256 expectedFeeBps = 5;
        bytes memory encodedInnerBundle;
        {
            Call[] memory innerBundle = mkArray(
                createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (DAI_ADDRESS, alice, flAmount))),
                createCall(
                    checkerPlugin,
                    abi.encodeCall(
                        MockPluginChecker.checkFlashloanAmounts,
                        (address(plugin), flAmount, flAmount * expectedFeeBps / 10_000)
                    )
                )
            );
            encodedInnerBundle = abi.encode(innerBundle);
        }

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginAaveV3Flash.flashLoan, (DAI_ADDRESS, flAmount, 1, encodedInnerBundle)
                ),
                keccak256(encodedInnerBundle)
            )
        );

        deal(DAI_ADDRESS, address(plugin), 2 * flAmount * (10_000 + expectedFeeBps) / 10_000);
        vm.startPrank(origamiMultisig);
        IOrigamiBundler(bundler).multicall(outerBundle);
        IOrigamiBundler(bundler).multicall(outerBundle);

        assertEq(IERC20(DAI_ADDRESS).balanceOf(alice), 2 * flAmount);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(plugin.flashloanTotalAmountT(), 0);
    }

    function test_flashLoan_success_2Deep() public {
        uint256 flAmount1 = 100_000e18;
        uint256 flAmount2 = 25_000e18;

        uint256 totalFlAmount = flAmount1 + flAmount2;
        uint256 expectedFeeBps = 5;
        uint256 totalFlWithFees = totalFlAmount * (10_000 + expectedFeeBps) / 10_000;
        deal(DAI_ADDRESS, overlord, totalFlWithFees);
        vm.prank(overlord);
        IERC20(DAI_ADDRESS).approve(address(entryPointPlugin), totalFlWithFees);

        // (3) Pull total + fees owed from Bob, check flash loan amounts
        bytes memory encodedMostInnerBundle;
        {
            Call[] memory mostInnerBundle = mkArray(
                createCall(
                    entryPointPlugin,
                    abi.encodeCall(
                        IOrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator,
                        (DAI_ADDRESS, address(plugin), totalFlWithFees)
                    )
                ),
                createCall(
                    checkerPlugin,
                    abi.encodeCall(
                        MockPluginChecker.checkFlashloanAmounts,
                        (address(plugin), flAmount2, flAmount2 * expectedFeeBps / 10_000)
                    )
                )
            );
            encodedMostInnerBundle = abi.encode(mostInnerBundle);
        }

        // (2) A repeat flash loan, send proceeds to Alice, check flash loan amounts
        bytes memory encodedSecondMostInnerBundle;
        {
            // Split out due to stack too deep
            Call[] memory secondMostInnerBundle = new Call[](3);
            secondMostInnerBundle[0] = createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginAaveV3Flash.flashLoan, (DAI_ADDRESS, flAmount2, 0, encodedMostInnerBundle)
                ),
                keccak256(encodedMostInnerBundle)
            );
            secondMostInnerBundle[1] = createCall(
                plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (DAI_ADDRESS, alice, flAmount2))
            );
            secondMostInnerBundle[2] = createCall(
                checkerPlugin,
                abi.encodeCall(
                    MockPluginChecker.checkFlashloanAmounts,
                    (address(plugin), flAmount1, flAmount1 * expectedFeeBps / 10_000)
                )
            );
            encodedSecondMostInnerBundle = abi.encode(secondMostInnerBundle);
        }

        // (1) A flash loan, send proceeds to Alice, check flash loan amounts
        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginAaveV3Flash.flashLoan,
                    (DAI_ADDRESS, flAmount1, 1, encodedSecondMostInnerBundle)
                ),
                keccak256(encodedSecondMostInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (DAI_ADDRESS, alice, flAmount1))),
            createCall(checkerPlugin, abi.encodeCall(MockPluginChecker.checkFlashloanAmounts, (address(plugin), 0, 0)))
        );

        vm.startPrank(overlord);
        IOrigamiBundler(bundler).multicall(outerBundle);

        assertEq(IERC20(DAI_ADDRESS).balanceOf(alice), totalFlAmount);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(bob), 0);
        assertEq(IERC20(DAI_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(plugin.flashloanTotalAmountT(), 0);
    }

    function test_executeOperation_failInitiator() public {
        vm.prank(POOL);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, alice));
        plugin.executeOperation(new address[](0), new uint256[](0), new uint256[](0), alice, "");
    }

    function test_executeOperation_failBadLengths() public {
        vm.startPrank(POOL);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        plugin.executeOperation(new address[](0), new uint256[](1), new uint256[](1), address(plugin), "");

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        plugin.executeOperation(new address[](1), new uint256[](0), new uint256[](1), address(plugin), "");

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        plugin.executeOperation(new address[](1), new uint256[](1), new uint256[](0), address(plugin), "");
    }

    function test_executeOperation_failCalledOutsideOfReenter() public {
        vm.startPrank(POOL);
        vm.expectRevert(abi.encodeWithSelector(LibCall.TargetIsNotContract.selector));
        plugin.executeOperation(mkArray(alice), mkArray(1e18), mkArray(0), address(plugin), "");
    }
}
