pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IEulerFlashLoan } from "contracts/interfaces/external/euler/IEulerFlashLoan.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import {
    IOrigamiBundlerPluginEulerFlash
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEulerFlash.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginEntryPoint
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { OrigamiBundlerPluginEulerFlash } from "contracts/common/bundler/plugins/OrigamiBundlerPluginEulerFlash.sol";
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
        uint256 actual = IOrigamiBundlerPluginEulerFlash(aavePlugin).flashloanTotalAmountT();
        if (actual != expected) revert AmountNotMatching(expected, actual);
    }
}

contract OrigamiBundlerPluginEulerFlashTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    // https://app.euler.finance/positions/0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9/0x7c280DBDEf569e96c7919251bD2B0edF0734C5A8?network=ethereum
    address internal constant EULER_USDT_VAULT = 0x7c280DBDEf569e96c7919251bD2B0edF0734C5A8;
    address internal constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    error E_Reentrancy();

    OrigamiBundler internal bundler;
    OrigamiBundlerPluginEulerFlash internal plugin;
    MockPluginChecker internal checkerPlugin;
    OrigamiBundlerPluginEntryPoint internal entryPointPlugin;

    function setUp() public {
        fork("mainnet", 23_323_025);
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginEulerFlash(origamiMultisig);
        entryPointPlugin = new OrigamiBundlerPluginEntryPoint(origamiMultisig, PERMIT2_ADDRESS, WETH_ADDRESS);
        checkerPlugin = new MockPluginChecker();

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler), true);
        entryPointPlugin.setBundlerApproved(address(bundler), true);
        vm.stopPrank();
    }
}

contract OrigamiBundlerPluginEulerFlashTestAdmin is OrigamiBundlerPluginEulerFlashTestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertEq(plugin.flashloanTotalAmountT(), 0);
        assertEq(plugin.flashloanFeeBps(), 0);
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginEulerFlash).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerPluginEulerFlashTestAccess is OrigamiBundlerPluginEulerFlashTestBase {
    function test_access_flashLoan() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        plugin.flashLoan(alice, 0, "");

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        plugin.flashLoan(alice, 0, "");
    }
}

contract OrigamiBundlerPluginEulerFlashTestFlash is OrigamiBundlerPluginEulerFlashTestBase {
    using SafeERC20 for IERC20;

    // error ReserveInactive();
    // error InvalidFlashloanExecutorReturn();

    // function test_flashLoan_failBadToken() public {
    //     vm.startPrank(address(bundler));
    //     vm.expectRevert(abi.encodeWithSelector(ReserveInactive.selector));
    //     plugin.flashLoan(alice, 1_000e6, 1, "");
    // }

    function test_flashLoan_failZeroAmount() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.flashLoan(EULER_USDT_VAULT, 0, "");
    }

    function test_flashLoan_failNoCallbackData() public {
        vm.startPrank(address(bundler));
        // Can't abi decode
        vm.expectRevert();
        plugin.flashLoan(EULER_USDT_VAULT, 1000e6, "");
    }

    function test_flashLoan_failWhenCalledDirectly() public {
        uint256 flAmount = 1000e6;

        Call[] memory innerBundle = mkArray(
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (USDT_ADDRESS, alice, flAmount)))
        );
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.IncorrectReenterHash.selector));
        plugin.flashLoan(EULER_USDT_VAULT, 1000e6, encodedInnerBundle);
    }

    function test_flashLoan_failNotRepaid() public {
        uint256 flAmount = 1000e6;

        bytes memory encodedInnerBundle;
        {
            Call[] memory innerBundle = mkArray(
                createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (USDT_ADDRESS, alice, flAmount)))
            );
            encodedInnerBundle = abi.encode(innerBundle);
        }

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginEulerFlash.flashLoan, (EULER_USDT_VAULT, flAmount, encodedInnerBundle)
                ),
                keccak256(encodedInnerBundle)
            )
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, USDT_ADDRESS, flAmount, 0)
        );
        IOrigamiBundler(bundler).multicall(outerBundle);
    }

    function test_flashLoan_success_single() public {
        uint256 flAmount = 1000e6;

        bytes memory encodedInnerBundle;
        {
            Call[] memory innerBundle = mkArray(
                createCall(
                    plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (USDT_ADDRESS, alice, flAmount))
                ),
                createCall(
                        checkerPlugin,
                        abi.encodeCall(MockPluginChecker.checkFlashloanAmounts, (address(plugin), flAmount, 0))
                    )
            );
            encodedInnerBundle = abi.encode(innerBundle);
        }

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginEulerFlash.flashLoan, (EULER_USDT_VAULT, flAmount, encodedInnerBundle)
                ),
                keccak256(encodedInnerBundle)
            )
        );

        deal(USDT_ADDRESS, address(plugin), 2 * flAmount);
        vm.startPrank(origamiMultisig);
        IOrigamiBundler(bundler).multicall(outerBundle);
        IOrigamiBundler(bundler).multicall(outerBundle);

        assertEq(IERC20(USDT_ADDRESS).balanceOf(alice), 2 * flAmount);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(plugin.flashloanTotalAmountT(), 0);
    }

    function test_flashLoan_fail_reentrancy() public {
        uint256 flAmount1 = 1000e6;
        uint256 flAmount2 = 25_000e6;

        uint256 totalFlAmount = flAmount1 + flAmount2;
        uint256 expectedFeeBps = 0;
        uint256 totalFlWithFees = totalFlAmount * (10_000 + expectedFeeBps) / 10_000;
        deal(USDT_ADDRESS, overlord, totalFlWithFees);
        vm.prank(overlord);
        IERC20(USDT_ADDRESS).forceApprove(address(entryPointPlugin), totalFlWithFees);

        // (3) Pull total + fees owed from Bob, check flash loan amounts
        bytes memory encodedMostInnerBundle;
        {
            Call[] memory mostInnerBundle = mkArray(
                createCall(
                    entryPointPlugin,
                    abi.encodeCall(
                        IOrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator,
                        (USDT_ADDRESS, address(plugin), totalFlWithFees)
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
                    IOrigamiBundlerPluginEulerFlash.flashLoan, (EULER_USDT_VAULT, flAmount2, encodedMostInnerBundle)
                ),
                keccak256(encodedMostInnerBundle)
            );
            secondMostInnerBundle[1] = createCall(
                plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (USDT_ADDRESS, alice, flAmount2))
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
                    IOrigamiBundlerPluginEulerFlash.flashLoan,
                    (EULER_USDT_VAULT, flAmount1, encodedSecondMostInnerBundle)
                ),
                keccak256(encodedSecondMostInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (USDT_ADDRESS, alice, flAmount1))),
            createCall(checkerPlugin, abi.encodeCall(MockPluginChecker.checkFlashloanAmounts, (address(plugin), 0, 0)))
        );

        vm.startPrank(overlord);
        vm.expectRevert(abi.encodeWithSelector(E_Reentrancy.selector));
        IOrigamiBundler(bundler).multicall(outerBundle);

        assertEq(IERC20(USDT_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(bob), 0);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(plugin.flashloanTotalAmountT(), 0);
    }

    function test_flashLoan_withOnFlashLoanInCallback() public {
        uint256 flAmount = 1000e6;

        bytes memory encodedInnerBundle;
        {
            Call[] memory innerBundle = mkArray(createCall(plugin, abi.encodeCall(IEulerFlashLoan.onFlashLoan, "")));
            encodedInnerBundle = abi.encode(innerBundle);
        }

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginEulerFlash.flashLoan, (EULER_USDT_VAULT, flAmount, encodedInnerBundle)
                ),
                keccak256(encodedInnerBundle)
            )
        );

        deal(USDT_ADDRESS, address(plugin), flAmount);
        vm.startPrank(origamiMultisig);

        // Can't call onFlashLoan within the flashloan because it's not the vault transient storage.
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(bundler)));
        IOrigamiBundler(bundler).multicall(outerBundle);
    }

    function test_onFlashLoan_failCalledDirectly() public {
        vm.startPrank(EULER_USDT_VAULT);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, EULER_USDT_VAULT));
        plugin.onFlashLoan("");
    }
}
