pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { MockCloneImpl } from "test/foundry/mocks/libraries/MockCloneImpl.sol";
import { MockCloneFactory } from "test/foundry/mocks/libraries/MockCloneFactory.sol";

contract ClonesImmutableReaderTest is OrigamiTest {
    MockCloneFactory internal factory;
    address internal impl;

    function setUp() public {
        factory = new MockCloneFactory();
        impl = address(new MockCloneImpl());
    }

    function test_getArgAddress() public {
        MockCloneImpl instance = MockCloneImpl(factory.create(impl, abi.encodePacked(origamiMultisig, alice, bob)));

        assertEq(instance.getArgAddress(0), origamiMultisig);
        assertEq(instance.getArgAddress(0 + 20), alice);
        assertEq(instance.getArgAddress(0 + 20 + 20), bob);
    }

    function test_getArgBytes32() public {
        MockCloneImpl instance = MockCloneImpl(
            factory.create(
                impl, abi.encodePacked(bytes32("Hello World"), bytes32("12345678910"), bytes32("Hello World2"))
            )
        );

        assertEq(instance.getArgBytes32(0), bytes32("Hello World"));
        assertEq(instance.getArgBytes32(0 + 32), bytes32("12345678910"));
        assertEq(instance.getArgBytes32(0 + 32 + 32), bytes32("Hello World2"));
    }

    function test_getArgUint8() public {
        MockCloneImpl instance =
            MockCloneImpl(factory.create(impl, abi.encodePacked(uint8(123), type(uint8).max, uint8(33))));

        assertEq(instance.getArgUint8(0), uint8(123));
        assertEq(instance.getArgUint8(0 + 1), type(uint8).max);
        assertEq(instance.getArgUint8(0 + 1 + 1), uint8(33));
    }

    function test_getArgUint256() public {
        MockCloneImpl instance = MockCloneImpl(
            factory.create(
                impl, abi.encodePacked(uint256(123e18), type(uint256).max, uint256(33.333333333333333333e18))
            )
        );

        assertEq(instance.getArgUint256(0), 123e18);
        assertEq(instance.getArgUint256(0 + 32), type(uint256).max);
        assertEq(instance.getArgUint256(0 + 32 + 32), 33.333333333333333333e18);
    }

    function test_multi() public {
        MockCloneImpl instance = MockCloneImpl(
            factory.create(
                impl,
                abi.encodePacked(origamiMultisig, alice, uint8(33), bytes32("Hello World"), uint256(type(uint128).max))
            )
        );

        assertEq(instance.getArgAddress(0), origamiMultisig);
        assertEq(instance.getArgAddress(0 + 20), alice);
        assertEq(instance.getArgUint8(0 + 20 + 20), uint8(33));
        assertEq(instance.getArgBytes32(0 + 20 + 20 + 1), bytes32("Hello World"));
        assertEq(instance.getArgUint256(0 + 20 + 20 + 1 + 32), uint256(type(uint128).max));
    }
}
