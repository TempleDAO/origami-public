pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later


import { OrigamiTeleportableToken } from "contracts/common/omnichain/OrigamiTeleportableToken.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOrigamiTeleportableToken } from "contracts/interfaces/common/omnichain/IOrigamiTeleportableToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiTeleportableTokenTestBase is OrigamiTest {
    OrigamiTeleportableToken public token;

    address internal teleporter = makeAddr("teleporter");
    event TeleporterSet(address indexed teleporter);

    function setUp() public {
        token = new OrigamiTeleportableToken("TELE_TOKEN", "TTOKEN", origamiMultisig);
        vm.prank(origamiMultisig);
        token.setTeleporter(teleporter);
    }
}

contract OrigamiTeleportableTokenTestAdmin is OrigamiTeleportableTokenTestBase {
    function test_init() public view {
        assertEq(token.name(), "TELE_TOKEN");
        assertEq(token.symbol(), "TTOKEN");
        assertEq(token.owner(), origamiMultisig);
        assertEq(token.decimals(), 18);
    }

    function test_supportsInterface() public view {
        assertEq(token.supportsInterface(type(IOrigamiTeleportableToken).interfaceId), true);
        assertEq(token.supportsInterface(type(IERC20Metadata).interfaceId), true);
        assertEq(token.supportsInterface(type(IERC20).interfaceId), true);
        assertEq(token.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(token.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(token.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(token.supportsInterface(type(IOrigamiInvestment).interfaceId), false);
    }

    function test_access_setTeleporter() public {
        expectElevatedAccess();
        token.setTeleporter(alice);
    }

    function test_setTeleporter_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        token.setTeleporter(address(0));
    }
    
    function test_setTeleporter_success() public {
        assertEq(address(token.teleporter()), teleporter);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(token));
        emit TeleporterSet(alice);
        token.setTeleporter(alice);
        assertEq(address(token.teleporter()), alice);
    }
}

contract OrigamiTeleportableTokenTestPermit is OrigamiTeleportableTokenTestBase {
    function test_permit() public {
        check_permit(token);
    }

    function test_allowance_bob() public {
        deal(address(token), alice, 1_000e18);

        assertEq(token.allowance(alice, bob), 0);
        vm.prank(alice);
        token.approve(bob, 100e18);
        assertEq(token.allowance(alice, bob), 100e18);

        vm.prank(bob);
        token.transferFrom(alice, bob, 25e18);
        assertEq(token.allowance(alice, bob), 75e18);
    }

    // Always type(uint256).max
    function test_allowance_teleporter() public {
        deal(address(token), alice, 1_000e18);
        assertEq(token.allowance(alice, teleporter), type(uint256).max);

        vm.prank(alice);
        token.approve(bob, 100e18);
        assertEq(token.allowance(alice, teleporter), type(uint256).max);

        vm.prank(teleporter);
        token.transferFrom(alice, teleporter, 25e18);
        assertEq(token.allowance(alice, teleporter), type(uint256).max);
    }
}
