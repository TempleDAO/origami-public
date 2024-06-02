pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

import { OrigamiCircuitBreakerAllUsersPerPeriod } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol";
import { OrigamiCircuitBreakerProxy } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerProxy.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

/* solhint-disable func-name-mixedcase, not-rely-on-time */
contract OrigamiCircuitBreakerProxyTest is OrigamiTest {
    OrigamiCircuitBreakerAllUsersPerPeriod public templeCircuitBreaker;
    OrigamiCircuitBreakerAllUsersPerPeriod public daiCircuitBreaker;
    OrigamiCircuitBreakerProxy public circuitBreakerProxy;

    DummyMintableToken public daiToken;
    DummyMintableToken public templeToken;

    address public caller = makeAddr("caller");

    bytes32 public constant EXTERNAL_ALL_USERS = keccak256("EXTERNAL_USER");

    event CircuitBreakerSet(bytes32 indexed identifier, address indexed token, address circuitBreaker);
    event IdentifierForCallerSet(address indexed caller, string identifierString, bytes32 identifier);

    function setUp() public {
        daiToken = new DummyMintableToken(origamiMultisig, "DAI Token", "DAI", 18);
        templeToken = new DummyMintableToken(origamiMultisig, "Temple Token", "TEMPLE", 18);
        circuitBreakerProxy = new OrigamiCircuitBreakerProxy(origamiMultisig);
        templeCircuitBreaker = new OrigamiCircuitBreakerAllUsersPerPeriod(origamiMultisig, address(circuitBreakerProxy), 26 hours, 13, 1_000e18);
        daiCircuitBreaker = new OrigamiCircuitBreakerAllUsersPerPeriod(origamiMultisig, address(circuitBreakerProxy), 26 hours, 13, 1_000e18);
    }

    function test_initialisation() public {
        assertEq(circuitBreakerProxy.owner(), origamiMultisig);
        bytes32[] memory ids = circuitBreakerProxy.identifiers();
        assertEq(ids.length, 0);
    }

    function test_access_setIdentifierForCaller() public {
        expectElevatedAccess();
        circuitBreakerProxy.setIdentifierForCaller(address(0), "EXTERNAL_USER");
    }

    function test_access_setCircuitBreaker() public {
        expectElevatedAccess();
        circuitBreakerProxy.setCircuitBreaker(EXTERNAL_ALL_USERS, address(templeToken), address(templeCircuitBreaker));
    }

    function test_access_preCheck() public {
        // Alice isn't mapped - so this will revert
        vm.startPrank(alice);
        vm.expectRevert();
        circuitBreakerProxy.preCheck(address(templeToken), 100);
    }

    function test_setIdentifierForCaller_failBadAddress() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        circuitBreakerProxy.setIdentifierForCaller(address(0), "");
    }

    function test_setIdentifierForCaller_failBadId() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        circuitBreakerProxy.setIdentifierForCaller(caller, "");
    }

    function test_setIdentifierForCaller_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(circuitBreakerProxy));
        emit IdentifierForCallerSet(caller, "EXTERNAL_USER", EXTERNAL_ALL_USERS);
        circuitBreakerProxy.setIdentifierForCaller(caller, "EXTERNAL_USER");

        bytes32[] memory ids = circuitBreakerProxy.identifiers();
        assertEq(ids.length, 1);
        assertEq(ids[0], EXTERNAL_ALL_USERS);
        assertEq(circuitBreakerProxy.callerToIdentifier(caller), EXTERNAL_ALL_USERS);
    }

    function test_setCircuitBreaker_failNoIdentifier() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        circuitBreakerProxy.setCircuitBreaker(EXTERNAL_ALL_USERS, address(templeToken), address(0));
    }

    function test_setCircuitBreaker_disable() public {
        setupProxy();
        vm.startPrank(caller);
        circuitBreakerProxy.preCheck(address(daiToken), 250e18);

        assertEq(address(circuitBreakerProxy.circuitBreakers(EXTERNAL_ALL_USERS, address(daiToken))), address(daiCircuitBreaker));
        assertEq(circuitBreakerProxy.cap(address(daiToken), caller), 1_000e18);
        assertEq(circuitBreakerProxy.currentUtilisation(address(daiToken), caller), 250e18);
        assertEq(circuitBreakerProxy.available(address(daiToken), caller), 750e18);

        // Remove
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(circuitBreakerProxy));
        emit CircuitBreakerSet(EXTERNAL_ALL_USERS, address(daiToken), address(0));
        circuitBreakerProxy.setCircuitBreaker(EXTERNAL_ALL_USERS, address(daiToken), address(0));
        assertEq(address(circuitBreakerProxy.circuitBreakers(EXTERNAL_ALL_USERS, address(daiToken))), address(0));
        assertEq(circuitBreakerProxy.cap(address(daiToken), caller), 0);
        assertEq(circuitBreakerProxy.currentUtilisation(address(daiToken), caller), 0);
        assertEq(circuitBreakerProxy.available(address(daiToken), caller), 0);
    }

    function test_setCircuitBreaker_success() public {
        vm.startPrank(origamiMultisig);
        circuitBreakerProxy.setIdentifierForCaller(caller, "EXTERNAL_USER");

        vm.expectEmit(address(circuitBreakerProxy));
        emit CircuitBreakerSet(EXTERNAL_ALL_USERS, address(templeToken), address(daiCircuitBreaker));
        circuitBreakerProxy.setCircuitBreaker(EXTERNAL_ALL_USERS, address(templeToken), address(daiCircuitBreaker));

        assertEq(address(circuitBreakerProxy.circuitBreakers(EXTERNAL_ALL_USERS, address(templeToken))), address(daiCircuitBreaker));
    }

    function setupProxy() internal {
        vm.startPrank(origamiMultisig);
        circuitBreakerProxy.setIdentifierForCaller(caller, "EXTERNAL_USER");
        circuitBreakerProxy.setCircuitBreaker(EXTERNAL_ALL_USERS, address(templeToken), address(templeCircuitBreaker));
        circuitBreakerProxy.setCircuitBreaker(EXTERNAL_ALL_USERS, address(daiToken), address(daiCircuitBreaker));
        vm.stopPrank();
    }

    function test_preCheck_unknownId() public {
        setupProxy();

        vm.startPrank(alice);
        vm.expectRevert();
        circuitBreakerProxy.preCheck(address(daiToken), 100);
    }

    function test_preCheck_unknownToken() public {
        setupProxy();

        vm.startPrank(caller);
        vm.expectRevert();
        circuitBreakerProxy.preCheck(bob, 100);
    }

    function test_preCheck_success() public {
        setupProxy();
        vm.startPrank(caller);
        
        circuitBreakerProxy.preCheck(address(daiToken), 250e18);
        assertEq(circuitBreakerProxy.cap(address(daiToken), caller), 1_000e18);
        assertEq(circuitBreakerProxy.currentUtilisation(address(daiToken), caller), 250e18);
        assertEq(circuitBreakerProxy.available(address(daiToken), caller), 750e18);

        circuitBreakerProxy.preCheck(address(daiToken), 750e18);
        assertEq(circuitBreakerProxy.cap(address(daiToken), caller), 1_000e18);
        assertEq(circuitBreakerProxy.currentUtilisation(address(daiToken), caller), 1_000e18);
        assertEq(circuitBreakerProxy.available(address(daiToken), caller), 0);

        // Can't borrow any more dai
        vm.expectRevert(abi.encodeWithSelector(OrigamiCircuitBreakerAllUsersPerPeriod.CapBreached.selector, 2_000e18, 1_000e18));
        circuitBreakerProxy.preCheck(address(daiToken), 1_000e18);

        // Can borrow temple though
        circuitBreakerProxy.preCheck(address(templeToken), 1_000e18);

        // Can borrow more after waiting...
        vm.warp(block.timestamp + 2 days);
        circuitBreakerProxy.preCheck(address(daiToken), 1_000e18);
    }

    function test_unmapped_views() public {
        // Alice isn't mapped, so returns zero
        vm.startPrank(alice);
        assertEq(circuitBreakerProxy.cap(address(daiToken), alice), 0);
        assertEq(circuitBreakerProxy.currentUtilisation(address(daiToken), alice), 0);
        assertEq(circuitBreakerProxy.available(address(daiToken), alice), 0);
    }
}