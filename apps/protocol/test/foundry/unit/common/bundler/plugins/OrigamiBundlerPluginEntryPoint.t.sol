pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginEntryPoint
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { Call } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundlerPluginEntryPoint } from "contracts/common/bundler/plugins/OrigamiBundlerPluginEntryPoint.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { IPermit2AllowanceTransfer } from "contracts/interfaces/external/permit2/IPermit2AllowanceTransfer.sol";

contract OrigamiBundlerPluginEntryPointTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    OrigamiBundler internal bundler;
    OrigamiBundlerPluginEntryPoint internal plugin;

    function setUp() public {
        fork("mainnet", 23_323_025);
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginEntryPoint(origamiMultisig, PERMIT2_ADDRESS, WETH_ADDRESS);

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler), true);
        vm.stopPrank();
    }
}

contract OrigamiBundlerPluginEntryPointTestAdmin is OrigamiBundlerPluginEntryPointTestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertFalse(plugin.isApprovedBundler(alice));
        assertEq(plugin.PERMIT2(), PERMIT2_ADDRESS);
        assertEq(plugin.WRAPPED_NATIVE(), WETH_ADDRESS);
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginEntryPoint).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerPluginEntryPointTestAccess is OrigamiBundlerPluginEntryPointTestBase {
    function test_access_nativeTransfer() public {
        checkInvalidBundler(alice);
        plugin.nativeTransfer(alice, 0);

        checkInvalidBundler(origamiMultisig);
        plugin.nativeTransfer(alice, 0);
    }

    function test_access_nativeTransferBalance() public {
        checkInvalidBundler(alice);
        plugin.nativeTransferBalance(alice, 0);

        checkInvalidBundler(origamiMultisig);
        plugin.nativeTransferBalance(alice, 0);
    }

    function test_access_erc20TransferFromInitiator() public {
        checkInvalidBundler(alice);
        plugin.erc20TransferFromInitiator(alice, alice, 0);

        checkInvalidBundler(origamiMultisig);
        plugin.erc20TransferFromInitiator(alice, alice, 0);
    }

    function test_access_erc20TransferBalanceFromInitiator() public {
        checkInvalidBundler(alice);
        plugin.erc20TransferBalanceFromInitiator(alice, alice, 0);

        checkInvalidBundler(origamiMultisig);
        plugin.erc20TransferBalanceFromInitiator(alice, alice, 0);
    }

    function test_access_permit2TransferFromInitiator() public {
        checkInvalidBundler(alice);
        plugin.permit2TransferFromInitiator(alice, alice, 0);

        checkInvalidBundler(origamiMultisig);
        plugin.permit2TransferFromInitiator(alice, alice, 0);
    }

    function test_access_permit2TransferBalanceFromInitiator() public {
        checkInvalidBundler(alice);
        plugin.permit2TransferBalanceFromInitiator(alice, alice, 0);

        checkInvalidBundler(origamiMultisig);
        plugin.permit2TransferBalanceFromInitiator(alice, alice, 0);
    }

    function test_access_wrapNative() public {
        checkInvalidBundler(alice);
        plugin.wrapNative(0, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.wrapNative(0, alice);
    }

    function test_access_wrapNativeBalance() public {
        checkInvalidBundler(alice);
        plugin.wrapNativeBalance(alice);

        checkInvalidBundler(origamiMultisig);
        plugin.wrapNativeBalance(alice);
    }

    function test_access_unwrapNative() public {
        checkInvalidBundler(alice);
        plugin.unwrapNative(0, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.unwrapNative(0, alice);
    }

    function test_access_unwrapNativeBalance() public {
        checkInvalidBundler(alice);
        plugin.unwrapNativeBalance(alice);

        checkInvalidBundler(origamiMultisig);
        plugin.unwrapNativeBalance(alice);
    }
}

contract OrigamiBundlerPluginEntryPointNative is OrigamiBundlerPluginEntryPointTestBase {
    function test_receive_native() public {
        deal(address(plugin), 0);
        deal(alice, 5e18);
        vm.startPrank(alice);
        Address.sendValue(payable(plugin), 1.123e18);
        assertEq(address(plugin).balance, 1.123e18);
    }

    function test_nativeTransfer_failParams() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.nativeTransfer(address(0), 123);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(plugin)));
        plugin.nativeTransfer(address(plugin), 123);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.nativeTransfer(address(alice), 0);
    }

    function test_nativeTransfer_failNotEnough() public {
        deal(address(bundler), 1e18);
        vm.startPrank(address(bundler));
        vm.expectRevert("Address: insufficient balance");
        plugin.nativeTransfer(address(alice), 1e18 + 1);
    }

    function test_nativeTransfer_success() public {
        deal(address(alice), 0);
        deal(address(bundler), 0);
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.nativeTransfer(address(alice), 1e18);
        assertEq(address(bundler).balance, 0);
        assertEq(address(plugin).balance, 0);
        assertEq(address(alice).balance, 1e18);
    }

    function test_nativeTransferBalance_failParams() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.nativeTransferBalance(address(0), 123);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(plugin)));
        plugin.nativeTransferBalance(address(plugin), 123);

        deal(address(plugin), 0);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 123, 0));
        plugin.nativeTransferBalance(address(alice), 123);
    }

    function test_nativeTransferBalance_failNotEnough() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 1e18 + 1, 1e18));
        plugin.nativeTransferBalance(address(alice), 1e18 + 1);
    }

    function test_nativeTransferBalance_successNoBalance() public {
        deal(address(alice), 0);
        deal(address(bundler), 0);
        deal(address(plugin), 0);
        vm.startPrank(address(bundler));
        plugin.nativeTransferBalance(address(alice), 0);
        assertEq(address(bundler).balance, 0);
        assertEq(address(plugin).balance, 0);
        assertEq(address(alice).balance, 0);
    }

    function test_nativeTransferBalance_successWithBalance() public {
        deal(address(alice), 0);
        deal(address(bundler), 0);
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.nativeTransferBalance(address(alice), 1e18);
        assertEq(address(bundler).balance, 0);
        assertEq(address(plugin).balance, 0);
        assertEq(address(alice).balance, 1e18);
    }
}

contract OrigamiBundlerPluginEntryPointTransferFrom is OrigamiBundlerPluginEntryPointTestBase {
    function test_erc20TransferFromInitiator_failParams() public {
        // no initiator
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.erc20TransferFromInitiator(WETH_ADDRESS, bob, 123);

        vm.startPrank(alice);

        // zero receiver
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator, (WETH_ADDRESS, address(0), 123)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        bundler.multicall(bundle);

        // initiator = receiver
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator, (WETH_ADDRESS, alice, 123))
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(alice)));
        bundler.multicall(bundle);

        // zero amount
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator, (WETH_ADDRESS, bob, 0))
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        bundler.multicall(bundle);
    }

    function test_erc20TransferFromInitiator_failNotEnough() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);

        // no approval
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator, (WETH_ADDRESS, bob, 1e18))
            )
        );
        vm.expectRevert("SafeERC20: low-level call failed");
        bundler.multicall(bundle);

        // not enough balance
        IERC20(WETH_ADDRESS).approve(address(plugin), 1e18);
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator, (WETH_ADDRESS, bob, 1e18 + 1))
            )
        );
        vm.expectRevert("SafeERC20: low-level call failed");
        bundler.multicall(bundle);
    }

    function test_erc20TransferFromInitiator_success() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);
        IERC20(WETH_ADDRESS).approve(address(plugin), 1e18);
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator, (WETH_ADDRESS, bob, 1e18))
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 1e18);
    }

    function test_erc20TransferBalanceFromInitiator_failParams() public {
        // no initiator
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.erc20TransferBalanceFromInitiator(WETH_ADDRESS, bob, 123);

        vm.startPrank(alice);

        // zero receiver
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.erc20TransferBalanceFromInitiator, (WETH_ADDRESS, address(0), 123)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        bundler.multicall(bundle);

        // initiator = receiver
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.erc20TransferBalanceFromInitiator, (WETH_ADDRESS, alice, 123)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(alice)));
        bundler.multicall(bundle);
    }

    function test_erc20TransferBalanceFromInitiator_failSlippage() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);
        IERC20(WETH_ADDRESS).approve(address(plugin), 1e18);
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.erc20TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 1e18 + 1)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 1e18 + 1, 1e18));
        bundler.multicall(bundle);
    }

    function test_erc20TransferBalanceFromInitiator_successNoBalance() public {
        deal(WETH_ADDRESS, alice, 0);
        vm.startPrank(alice);
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.erc20TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 0))
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 0);
    }

    function test_erc20TransferBalanceFromInitiator_successWithBalance() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);
        IERC20(WETH_ADDRESS).approve(address(plugin), 1e18);
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.erc20TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 1e18)
                )
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 1e18);
    }
}

contract OrigamiBundlerPluginEntryPointPermit2 is OrigamiBundlerPluginEntryPointTestBase {
    bytes32 internal constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");

    bytes32 internal constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    bytes4 internal constant _PERMIT_SINGLE_SELECTOR =
        bytes4(keccak256("permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)"));

    function _createSig(IPermit2AllowanceTransfer.PermitSingle memory pSingle, uint256 ownerPk)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 domainSeparator = IPermit2AllowanceTransfer(PERMIT2_ADDRESS).DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                _PERMIT_DETAILS_TYPEHASH,
                pSingle.details.token,
                pSingle.details.amount,
                pSingle.details.expiration,
                pSingle.details.nonce
            )
        );
        structHash = keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, structHash, pSingle.spender, pSingle.sigDeadline));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, typedDataHash);
        signature = abi.encodePacked(r, s, v);
    }

    function test_permit2TransferFromInitiator_failParams() public {
        // no initiator
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.permit2TransferFromInitiator(WETH_ADDRESS, bob, 123);

        vm.startPrank(alice);

        // zero receiver
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, address(0), 123)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        bundler.multicall(bundle);

        // initiator = receiver
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, alice, 123))
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(alice)));
        bundler.multicall(bundle);

        // zero amount
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, bob, 0))
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        bundler.multicall(bundle);
    }

    function test_permit2TransferFromInitiator_failNotEnough() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);

        // no approval to PERMIT2
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, bob, 1e18))
            )
        );
        vm.expectRevert(abi.encodeWithSelector(IPermit2AllowanceTransfer.AllowanceExpired.selector, 0));
        bundler.multicall(bundle);

        // not enough balance
        IPermit2AllowanceTransfer(PERMIT2_ADDRESS)
            .approve(WETH_ADDRESS, address(plugin), 1e18, uint48(vm.getBlockTimestamp() + 1));
        IERC20(WETH_ADDRESS).approve(PERMIT2_ADDRESS, 1e18);
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, bob, 1e18 + 1)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(IPermit2AllowanceTransfer.InsufficientAllowance.selector, 1e18));
        bundler.multicall(bundle);
    }

    function test_permit2TransferFromInitiator_successPreApprove() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);
        uint48 expiry = uint48(vm.getBlockTimestamp() + 1);
        IPermit2AllowanceTransfer(PERMIT2_ADDRESS).approve(WETH_ADDRESS, address(plugin), 1e18, expiry);
        IERC20(WETH_ADDRESS).approve(PERMIT2_ADDRESS, 1e18);
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, bob, 1e18))
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 1e18);
        assertEq(IERC20(WETH_ADDRESS).allowance(alice, PERMIT2_ADDRESS), 0);
        (uint256 amt, uint48 exp, uint48 nonce) =
            IPermit2AllowanceTransfer(PERMIT2_ADDRESS).allowance(alice, WETH_ADDRESS, address(plugin));
        assertEq(amt, 0);
        assertEq(exp, expiry);
        assertEq(nonce, 0);
    }

    function test_permit2TransferFromInitiator_successWithSig() public {
        (address ownerAddr, uint256 ownerPk) = makeAddrAndKey("A11CE");

        deal(WETH_ADDRESS, ownerAddr, 1e18);
        vm.startPrank(ownerAddr);
        IERC20(WETH_ADDRESS).approve(PERMIT2_ADDRESS, 1e18);

        uint48 expiry = uint48(vm.getBlockTimestamp() + 1);
        IPermit2AllowanceTransfer.PermitDetails memory pDetails = IPermit2AllowanceTransfer.PermitDetails({
            token: WETH_ADDRESS, amount: uint160(1e18), expiration: uint48(expiry), nonce: uint48(0)
        });
        IPermit2AllowanceTransfer.PermitSingle memory pSingle = IPermit2AllowanceTransfer.PermitSingle({
            details: pDetails, spender: address(plugin), sigDeadline: expiry
        });

        bytes memory sig = _createSig(pSingle, ownerPk);

        Call[] memory bundle = mkArray(
            Call({
                to: PERMIT2_ADDRESS,
                data: abi.encodeWithSelector(_PERMIT_SINGLE_SELECTOR, ownerAddr, pSingle, sig),
                value: 0,
                skipRevert: false,
                callbackHash: bytes32(0)
            }),
            createCall(
                plugin,
                abi.encodeCall(OrigamiBundlerPluginEntryPoint.permit2TransferFromInitiator, (WETH_ADDRESS, bob, 1e18))
            )
        );

        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(ownerAddr), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 1e18);
        assertEq(IERC20(WETH_ADDRESS).allowance(ownerAddr, PERMIT2_ADDRESS), 0);
        (uint256 amt, uint48 exp, uint48 nonce) =
            IPermit2AllowanceTransfer(PERMIT2_ADDRESS).allowance(ownerAddr, WETH_ADDRESS, address(plugin));
        assertEq(amt, 0);
        assertEq(exp, expiry);
        assertEq(nonce, 1);
    }

    function test_permit2TransferBalanceFromInitiator_failParams() public {
        // no initiator
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.permit2TransferBalanceFromInitiator(WETH_ADDRESS, bob, 123);

        vm.startPrank(alice);

        // zero receiver
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferBalanceFromInitiator, (WETH_ADDRESS, address(0), 123)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        bundler.multicall(bundle);

        // initiator = receiver
        bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferBalanceFromInitiator, (WETH_ADDRESS, alice, 123)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(alice)));
        bundler.multicall(bundle);
    }

    function test_permit2TransferBalanceFromInitiator_failSlippage() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);

        uint48 expiry = uint48(vm.getBlockTimestamp() + 1);
        IPermit2AllowanceTransfer(PERMIT2_ADDRESS).approve(WETH_ADDRESS, address(plugin), 1e18, expiry);
        IERC20(WETH_ADDRESS).approve(PERMIT2_ADDRESS, 1e18);

        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 1e18 + 1)
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 1e18 + 1, 1e18));
        bundler.multicall(bundle);
    }

    function test_permit2TransferBalanceFromInitiator_successNoBalance() public {
        deal(WETH_ADDRESS, alice, 0);
        vm.startPrank(alice);
        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 0)
                )
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 0);
    }

    function test_permit2TransferBalanceFromInitiator_successWithBalancePreApprove() public {
        deal(WETH_ADDRESS, alice, 1e18);
        vm.startPrank(alice);

        uint48 expiry = uint48(vm.getBlockTimestamp() + 1);
        IPermit2AllowanceTransfer(PERMIT2_ADDRESS).approve(WETH_ADDRESS, address(plugin), 1e18, expiry);
        IERC20(WETH_ADDRESS).approve(PERMIT2_ADDRESS, 1e18);

        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 1e18)
                )
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 1e18);
    }

    function test_permit2TransferBalanceFromInitiator_successWithBalanceWithSig() public {
        (address ownerAddr, uint256 ownerPk) = makeAddrAndKey("A11CE");

        deal(WETH_ADDRESS, ownerAddr, 1e18);
        vm.startPrank(ownerAddr);
        IERC20(WETH_ADDRESS).approve(PERMIT2_ADDRESS, 1e18);

        uint48 expiry = uint48(vm.getBlockTimestamp() + 1);
        IPermit2AllowanceTransfer.PermitDetails memory pDetails = IPermit2AllowanceTransfer.PermitDetails({
            token: WETH_ADDRESS, amount: uint160(1e18), expiration: uint48(expiry), nonce: uint48(0)
        });
        IPermit2AllowanceTransfer.PermitSingle memory pSingle = IPermit2AllowanceTransfer.PermitSingle({
            details: pDetails, spender: address(plugin), sigDeadline: expiry
        });

        bytes memory sig = _createSig(pSingle, ownerPk);
        Call[] memory bundle = mkArray(
            Call({
                to: PERMIT2_ADDRESS,
                data: abi.encodeWithSelector(_PERMIT_SINGLE_SELECTOR, ownerAddr, pSingle, sig),
                value: 0,
                skipRevert: false,
                callbackHash: bytes32(0)
            }),
            createCall(
                plugin,
                abi.encodeCall(
                    OrigamiBundlerPluginEntryPoint.permit2TransferBalanceFromInitiator, (WETH_ADDRESS, bob, 1e18)
                )
            )
        );
        bundler.multicall(bundle);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(bob), 1e18);
    }
}

contract OrigamiBundlerPluginEntryPointWrapNative is OrigamiBundlerPluginEntryPointTestBase {
    function test_wrapNative_failParams() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.wrapNative(0, alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.wrapNative(123, address(0));
    }

    function test_wrapNative_failNotEnough() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        vm.expectRevert();
        plugin.wrapNative(1e18 + 1, alice);
    }

    function test_wrapNative_successToSelf() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.wrapNative(1e18, address(plugin));
        assertEq(address(plugin).balance, 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 1e18);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_wrapNative_successDifferentReceiver() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.wrapNative(1e18, alice);
        assertEq(address(plugin).balance, 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 1e18);
    }

    function test_wrapNativeBalance_failParams() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.wrapNativeBalance(address(0));
    }

    function test_wrapNativeBalance_successNoEth() public {
        deal(address(plugin), 0);
        vm.startPrank(address(bundler));
        plugin.wrapNativeBalance(alice);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_wrapNativeBalance_successToSelf() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.wrapNativeBalance(address(plugin));
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 1e18);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_wrapNativeBalance_successDifferentReceiver() public {
        deal(address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.wrapNativeBalance(alice);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 1e18);
    }
}

contract OrigamiBundlerPluginEntryPointUnwrapNative is OrigamiBundlerPluginEntryPointTestBase {
    function test_unwrapNative_failParams() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.unwrapNative(0, alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.unwrapNative(123, address(0));
    }

    function test_unwrapNative_failNotEnough() public {
        deal(WETH_ADDRESS, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        vm.expectRevert();
        plugin.unwrapNative(1e18 + 1, alice);
    }

    function test_unwrapNative_successToSelf() public {
        deal(WETH_ADDRESS, address(plugin), 1e18);
        deal(address(plugin), 0);
        deal(alice, 0);
        vm.startPrank(address(bundler));
        plugin.unwrapNative(1e18, address(plugin));
        assertEq(address(plugin).balance, 1e18);
        assertEq(address(alice).balance, 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_unwrapNative_successDifferentReceiver() public {
        deal(WETH_ADDRESS, address(plugin), 1e18);
        deal(address(plugin), 0);
        deal(alice, 0);
        vm.startPrank(address(bundler));
        plugin.unwrapNative(1e18, alice);
        assertEq(address(plugin).balance, 0);
        assertEq(address(alice).balance, 1e18);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_unwrapNativeBalance_failParams() public {
        deal(WETH_ADDRESS, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.unwrapNativeBalance(address(0));
    }

    function test_unwrapNativeBalance_successNoWEth() public {
        deal(address(plugin), 0);
        deal(alice, 0);
        vm.startPrank(address(bundler));
        plugin.unwrapNativeBalance(alice);
        assertEq(address(plugin).balance, 0);
        assertEq(address(alice).balance, 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_unwrapNativeBalance_successToSelf() public {
        deal(WETH_ADDRESS, address(plugin), 1e18);
        deal(address(plugin), 0);
        deal(alice, 0);
        vm.startPrank(address(bundler));
        plugin.unwrapNativeBalance(address(plugin));
        assertEq(address(plugin).balance, 1e18);
        assertEq(address(alice).balance, 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }

    function test_unwrapNativeBalance_successDifferentReceiver() public {
        deal(WETH_ADDRESS, address(plugin), 1e18);
        deal(address(plugin), 0);
        deal(alice, 0);
        vm.startPrank(address(bundler));
        plugin.unwrapNativeBalance(alice);
        assertEq(address(plugin).balance, 0);
        assertEq(address(alice).balance, 1e18);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_ADDRESS).balanceOf(alice), 0);
    }
}
