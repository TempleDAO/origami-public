pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { Whitelisted } from "contracts/common/access/Whitelisted.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract MockWhitelisted is Whitelisted {
    constructor(address _initialGov) OrigamiElevatedAccess(_initialGov) {}

    function isAllowed(address account) external view returns (bool) {
        return _isAllowed(account);
    }
}

contract MockAccessInConstruction {
    MockWhitelisted public whitelist;
    bool public allowedInConstruction;

    constructor(MockWhitelisted _whitelist) {
        whitelist = _whitelist;
        allowedInConstruction = _whitelist.isAllowed(address(this));
    }

    function allowedAfterConstruction() external view returns (bool) {
        return whitelist.isAllowed(address(this));
    }
}

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract WhitelistedTestBase is OrigamiTest {
    MockWhitelisted public whitelisted;
    DummyMintableToken public someContract;

    function setUp() public {
        vm.startPrank(origamiMultisig);
        whitelisted = new MockWhitelisted(origamiMultisig);
        someContract = new DummyMintableToken(origamiMultisig, "Deposit Token", "token", 18);
        vm.stopPrank();
    }
}

contract WhitelistedTestAccess is WhitelistedTestBase {
    function test_access_setAllowAll() public {
        expectElevatedAccess();
        whitelisted.setAllowAll(true);
    }

    function test_access_setAllowAccount() public {
        expectElevatedAccess();
        whitelisted.setAllowAccount(bob, true);
    }
}

contract WhitelistedTestAdmin is WhitelistedTestBase {
    event AllowAllSet(bool value);
    event AllowAccountSet(address indexed account, bool value);

    function test_initialization() public {
        assertEq(whitelisted.allowAll(), false);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), false);
    }

    function test_setAllowAll() public {
        vm.startPrank(origamiMultisig);
        assertEq(whitelisted.allowAll(), false);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), false);

        vm.expectEmit(address(whitelisted));
        emit AllowAllSet(true);
        whitelisted.setAllowAll(true);

        assertEq(whitelisted.allowAll(), true);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), true);

        vm.expectEmit(address(whitelisted));
        emit AllowAllSet(false);
        whitelisted.setAllowAll(false);

        assertEq(whitelisted.allowAll(), false);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), false);
    }

    function test_setAllowAccount_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        whitelisted.setAllowAccount(address(0), true);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, bob));
        whitelisted.setAllowAccount(bob, true);
    }

    function test_setAllowAccount_success() public {
        vm.startPrank(origamiMultisig);
        assertEq(whitelisted.allowAll(), false);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), false);
        assertEq(whitelisted.allowedAccounts(address(someContract)), false);

        vm.expectEmit(address(whitelisted));
        emit AllowAccountSet(address(someContract), true);
        whitelisted.setAllowAccount(address(someContract), true);

        assertEq(whitelisted.allowAll(), false);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), true);
        assertEq(whitelisted.allowedAccounts(address(someContract)), true);

        vm.expectEmit(address(whitelisted));
        emit AllowAccountSet(address(someContract), false);
        whitelisted.setAllowAccount(address(someContract), false);

        assertEq(whitelisted.allowAll(), false);
        assertEq(whitelisted.isAllowed(bob), true);
        assertEq(whitelisted.isAllowed(address(someContract)), false);
        assertEq(whitelisted.allowedAccounts(address(someContract)), false);
    }

    function test_allowedDepositorAtConstruction() public {
        // A contract will be allowed to deposit during construction (since code.length == 0 during that time)
        MockAccessInConstruction inConstruction = new MockAccessInConstruction(whitelisted);
        assertEq(inConstruction.allowedInConstruction(), true);
        assertEq(inConstruction.allowedAfterConstruction(), false);
    }
}
