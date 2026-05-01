pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import {
    MockMultiTokenOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockMultiTokenOpalAdapter.m.sol";
import { IOpalAdapterFactory } from "contracts/interfaces/investments/opal/IOpalAdapterFactory.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { LibString } from "solady/utils/LibString.sol";

contract OpalAdapterFactoryTestBase is OrigamiTest {
    OpalAdapterFactory internal adapterFactory;
    MockMultiTokenOpalAdapter internal adapterImpl1;
    MockMultiTokenOpalAdapter internal adapterImpl2;
    MockMultiTokenOpalAdapter internal adapterImpl3;

    MockMultiTokenOpalAdapter internal adapter1;
    MockMultiTokenOpalAdapter internal adapter2;
    MockMultiTokenOpalAdapter internal adapter3;

    address internal manager = makeAddr("manager");

    bytes32 internal DEFAULT_GROUP_ID = bytes32("DEFAULT");

    function setUp() public virtual {
        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl1 = new MockMultiTokenOpalAdapter("MOCK.1");
        adapterImpl2 = new MockMultiTokenOpalAdapter("MOCK.2");
        adapterImpl3 = new MockMultiTokenOpalAdapter("MOCK.3");

        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl1));
        adapterFactory.addImplementation(address(adapterImpl2));
        vm.stopPrank();
    }
}

contract OpalAdapterFactoryTestAdmin is OpalAdapterFactoryTestBase {
    event ImplementationAdded(address indexed implementation, bytes32 indexed implTypeAndVersion);

    event ImplementationRemoved(address indexed implementation);

    event AdapterAdded(
        address newAdapter,
        address indexed implementation,
        bytes32 indexed implTypeAndVersion,
        address indexed manager,
        bytes32 description
    );

    function test_initialization() public view {
        assertEq(adapterFactory.owner(), origamiMultisig);
        assertEq(adapterFactory.numImplementations(), 2);
        assertEq(adapterFactory.isRegistered(address(adapterImpl1)), true);
        assertEq(adapterFactory.isRegistered(address(adapterImpl2)), true);
        assertEq(adapterFactory.isRegistered(address(adapterImpl3)), false);
    }

    function test_addImplementation_failure_badImpl() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(); // not an adapter
        adapterFactory.addImplementation(address(0));
    }

    function test_addImplementation_failure_alreadyRegistered() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapterFactory.AlreadyRegistered.selector));
        adapterFactory.addImplementation(address(adapterImpl1));
    }

    function test_addImplementation_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapterFactory));
        emit ImplementationAdded(address(adapterImpl3), "MOCK.3");
        adapterFactory.addImplementation(address(adapterImpl3));
        assertEq(adapterFactory.isRegistered(address(adapterImpl3)), true);
        assertEq(adapterFactory.numImplementations(), 3);
    }

    function test_removeImplementation_failure_notRegistered() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapterFactory.NotRegistered.selector));
        adapterFactory.removeImplementation(alice);
    }

    function test_removeImplementation_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapterFactory));
        emit ImplementationRemoved(address(adapterImpl2));
        adapterFactory.removeImplementation(address(adapterImpl2));
        assertEq(adapterFactory.isRegistered(address(adapterImpl2)), false);
        assertEq(adapterFactory.numImplementations(), 1);
    }

    function test_create_failure_notRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapterFactory.NotRegistered.selector));
        adapterFactory.create(alice, manager, "xyz", "");
    }

    function test_create_success_noArgs() public {
        bytes32 desc = "xyz";
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(0x104fBc016F4bb334D775a19E8A6510109AC63E00, address(adapterImpl1), "MOCK.1", manager, desc);
        address newAdapter = adapterFactory.create(address(adapterImpl1), manager, desc, "");
        assertEq(newAdapter, 0x104fBc016F4bb334D775a19E8A6510109AC63E00);
        assertEq(MockMultiTokenOpalAdapter(newAdapter).bundler(), address(0)); // transient
        assertEq(MockMultiTokenOpalAdapter(newAdapter).description(), LibString.fromSmallString(desc));

        bytes memory args = LibClone.argsOnClone(newAdapter);
        assertEq(args, abi.encodePacked(manager, desc));
    }

    function test_create_success_withArgs() public {
        bytes32 desc = "xyz";
        bytes memory extraArgs =
            adapterImpl1.encodeImmutableArgs(address(1), address(2), address(3), address(4), DEFAULT_GROUP_ID);
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(0x104fBc016F4bb334D775a19E8A6510109AC63E00, address(adapterImpl1), "MOCK.1", manager, desc);
        address newAdapter = adapterFactory.create(address(adapterImpl1), manager, desc, extraArgs);
        assertEq(newAdapter, 0x104fBc016F4bb334D775a19E8A6510109AC63E00);
        assertEq(MockMultiTokenOpalAdapter(newAdapter).bundler(), address(0)); // transient
        assertEq(MockMultiTokenOpalAdapter(newAdapter).description(), LibString.fromSmallString(desc));

        (address[] memory assetTokens, address[] memory liabilityTokens) =
            MockMultiTokenOpalAdapter(newAdapter).tokens();
        assertEq(assetTokens.length, 2);
        assertEq(assetTokens[0], address(1));
        assertEq(assetTokens[1], address(2));
        assertEq(liabilityTokens.length, 2);
        assertEq(liabilityTokens[0], address(3));
        assertEq(liabilityTokens[1], address(4));

        bytes memory args = LibClone.argsOnClone(newAdapter);
        assertEq(args, abi.encodePacked(manager, desc, extraArgs));
    }
}

contract OpalAdapterFactoryTestAccess is OpalAdapterFactoryTestBase {
    function test_access_addImplementation() public {
        expectElevatedAccess();
        adapterFactory.addImplementation(alice);
    }

    function test_access_removeImplementation() public {
        expectElevatedAccess();
        adapterFactory.removeImplementation(alice);
    }
}

contract OpalAdapterFactoryTestList is OpalAdapterFactoryTestBase {
    MockMultiTokenOpalAdapter internal adapterImpl4;
    MockMultiTokenOpalAdapter internal adapterImpl5;

    function setUp() public override {
        super.setUp();

        adapterImpl4 = new MockMultiTokenOpalAdapter("MOCK.4");
        adapterImpl5 = new MockMultiTokenOpalAdapter("MOCK.5");

        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl3));
        adapterFactory.addImplementation(address(adapterImpl4));
        adapterFactory.addImplementation(address(adapterImpl5));
        vm.stopPrank();
    }

    function test_implementationDetailList_empty() public {
        adapterFactory = new OpalAdapterFactory(origamiMultisig);

        IOpalAdapterFactory.ImplementationDetail[] memory impls = adapterFactory.implementationDetailList(0, 50);
        assertEq(impls.length, 0);
    }

    function test_implementationDetailList_underOnePage() public view {
        IOpalAdapterFactory.ImplementationDetail[] memory impls = adapterFactory.implementationDetailList(0, 50);
        assertEq(impls.length, 5);
        assertEq(impls[0].implementation, address(adapterImpl1));
        assertEq(impls[0].implTypeAndVersion, "MOCK.1");
        assertEq(impls[1].implementation, address(adapterImpl2));
        assertEq(impls[1].implTypeAndVersion, "MOCK.2");
        assertEq(impls[2].implementation, address(adapterImpl3));
        assertEq(impls[2].implTypeAndVersion, "MOCK.3");
        assertEq(impls[3].implementation, address(adapterImpl4));
        assertEq(impls[3].implTypeAndVersion, "MOCK.4");
        assertEq(impls[4].implementation, address(adapterImpl5));
        assertEq(impls[4].implTypeAndVersion, "MOCK.5");
    }

    function test_implementationDetailList_exactlyOnePage() public view {
        IOpalAdapterFactory.ImplementationDetail[] memory impls = adapterFactory.implementationDetailList(0, 5);
        assertEq(impls.length, 5);
        assertEq(impls[0].implementation, address(adapterImpl1));
        assertEq(impls[0].implTypeAndVersion, "MOCK.1");
        assertEq(impls[1].implementation, address(adapterImpl2));
        assertEq(impls[1].implTypeAndVersion, "MOCK.2");
        assertEq(impls[2].implementation, address(adapterImpl3));
        assertEq(impls[2].implTypeAndVersion, "MOCK.3");
        assertEq(impls[3].implementation, address(adapterImpl4));
        assertEq(impls[3].implTypeAndVersion, "MOCK.4");
        assertEq(impls[4].implementation, address(adapterImpl5));
        assertEq(impls[4].implTypeAndVersion, "MOCK.5");
    }

    function test_implementationDetailList_multiPages() public view {
        IOpalAdapterFactory.ImplementationDetail[] memory impls = adapterFactory.implementationDetailList(0, 3);
        assertEq(impls.length, 3);
        assertEq(impls[0].implementation, address(adapterImpl1));
        assertEq(impls[0].implTypeAndVersion, "MOCK.1");
        assertEq(impls[1].implementation, address(adapterImpl2));
        assertEq(impls[1].implTypeAndVersion, "MOCK.2");
        assertEq(impls[2].implementation, address(adapterImpl3));
        assertEq(impls[2].implTypeAndVersion, "MOCK.3");

        impls = adapterFactory.implementationDetailList(3, 5);
        assertEq(impls.length, 2);
        assertEq(impls[0].implementation, address(adapterImpl4));
        assertEq(impls[0].implTypeAndVersion, "MOCK.4");
        assertEq(impls[1].implementation, address(adapterImpl5));
        assertEq(impls[1].implTypeAndVersion, "MOCK.5");

        impls = adapterFactory.implementationDetailList(3, 10);
        assertEq(impls.length, 2);

        impls = adapterFactory.implementationDetailList(3, 0);
        assertEq(impls.length, 0);

        impls = adapterFactory.implementationDetailList(30, 30);
        assertEq(impls.length, 0);

        impls = adapterFactory.implementationDetailList(30, 0);
        assertEq(impls.length, 0);
    }
}
