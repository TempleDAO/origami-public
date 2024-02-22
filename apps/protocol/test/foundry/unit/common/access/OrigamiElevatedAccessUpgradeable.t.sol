pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiElevatedAccessUpgradeable } from "contracts/common/access/OrigamiElevatedAccessUpgradeable.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase */
contract MockUpgradeable is Initializable, OrigamiElevatedAccessUpgradeable, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initialOwner) external initializer {
        __OrigamiElevatedAccess_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyElevatedAccess
        override
    {}

    // solhint-disable-next-line no-empty-blocks
    function validateOnlyElevatedAccess() public view onlyElevatedAccess {}

    function checkSig() public view {
        validateOnlyElevatedAccess();
    }

    function checkSigThis() public view {
        this.validateOnlyElevatedAccess();
    }

    // A magic function with a signature of 0x00000000
    function wycpnbqcyf() external view onlyElevatedAccess {}
}

contract OrigamiElevatedAccessUpgradeableTestBase is OrigamiTest {
    MockUpgradeable public template;
    MockUpgradeable public mock;

    function setUp() public {
        template = new MockUpgradeable();

        bytes memory data = abi.encodeCall(MockUpgradeable.initialize, origamiMultisig);
        mock = MockUpgradeable(address(new ERC1967Proxy(address(template), data)));
    }

}

contract OrigamiElevatedAccesUpgradeablesTest is OrigamiElevatedAccessUpgradeableTestBase {

    function test_initialization() public {
        assertEq(mock.owner(), origamiMultisig);
        assertEq(template.owner(), address(0));
    }

    function test_construction_fail() public {
        bytes memory data = abi.encodeCall(MockUpgradeable.initialize, address(0));       
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        mock = MockUpgradeable(address(new ERC1967Proxy(address(template), data)));
    }
    
    function test_access_proposeNewOwner() public {
        expectElevatedAccess();
        mock.proposeNewOwner(alice);

        vm.prank(origamiMultisig);
        mock.proposeNewOwner(alice);
    }

    function test_access_acceptOwner() public {
        expectElevatedAccess();
        mock.acceptOwner();

        // Not for existing owner either
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        mock.acceptOwner();
    }
    
    function test_access_setExplicitAccess() public {
        expectElevatedAccess();
        setExplicitAccess(mock, alice, msg.sig, true);
    }
}

contract OrigamiElevatedAccessUpgradeableTestSetters is OrigamiElevatedAccessUpgradeableTestBase {
    event ExplicitAccessSet(address indexed account, bytes4 indexed fnSelector, bool indexed value);

    event NewOwnerProposed(address indexed oldOwner, address indexed oldProposedOwner, address indexed newProposedOwner);
    event NewOwnerAccepted(address indexed oldOwner, address indexed newOwner);

    function test_newOwner() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        mock.proposeNewOwner(address(0));

        vm.expectEmit(address(mock));
        emit NewOwnerProposed(origamiMultisig, address(0), alice);
        mock.proposeNewOwner(alice);

        vm.startPrank(alice);
        vm.expectEmit(address(mock));
        emit NewOwnerAccepted(origamiMultisig, alice);
        mock.acceptOwner();
        assertEq(mock.owner(), alice);
    }

    function test_setExplicitAccess_single() public {
        bytes4 fnSig = bytes4(keccak256("someFunctionSignature(uint256)"));
        bytes4 fnSig2 = bytes4(keccak256("someFunctionSignature(uint256,string)"));
        assertEq(mock.explicitFunctionAccess(alice, fnSig), false);
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        setExplicitAccess(mock, address(0), msg.sig, true);

        vm.expectEmit(address(mock));
        emit ExplicitAccessSet(alice, fnSig, true);
        setExplicitAccess(mock, alice, fnSig, true);
        assertEq(mock.explicitFunctionAccess(alice, fnSig), true);
        assertEq(mock.explicitFunctionAccess(alice, fnSig2), false);

        vm.expectEmit(address(mock));
        emit ExplicitAccessSet(alice, fnSig, false);
        setExplicitAccess(mock, alice, fnSig, false);
        assertEq(mock.explicitFunctionAccess(alice, fnSig), false);
        assertEq(mock.explicitFunctionAccess(alice, fnSig2), false);
    }

    function test_setExplicitAccess_zeroSig() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        mock.wycpnbqcyf();

        vm.startPrank(origamiMultisig);
        bytes4 fnSig = bytes4(keccak256("wycpnbqcyf()"));
        vm.expectEmit(address(mock));
        emit ExplicitAccessSet(alice, fnSig, true);
        setExplicitAccess(mock, alice, fnSig, true);

        // Now succeeds
        vm.startPrank(alice);
        mock.wycpnbqcyf();
    }

    function test_setExplicitAccess_multiple() public {
        bytes4 fnSig = bytes4(keccak256("someFunctionSignature(uint256)"));
        bytes4 fnSig2 = bytes4(keccak256("someFunctionSignature(uint256,string)"));
        assertEq(mock.explicitFunctionAccess(alice, fnSig), false);
        vm.startPrank(origamiMultisig);

        // Single
        setExplicitAccess(mock, alice, fnSig, true);

        // Now update to switch
        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](2);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(fnSig, false);
        access[1] = IOrigamiElevatedAccess.ExplicitAccess(fnSig2, true);

        vm.expectEmit(address(mock));
        emit ExplicitAccessSet(alice, fnSig, false);
        emit ExplicitAccessSet(alice, fnSig2, true);
        mock.setExplicitAccess(alice, access);
        assertEq(mock.explicitFunctionAccess(alice, fnSig), false);
        assertEq(mock.explicitFunctionAccess(alice, fnSig2), true);
    }
}

contract OrigamiElevatedAccessTestUpgradeableModifiers is OrigamiElevatedAccessUpgradeableTestBase {
    function test_onlyElevatedAccess() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        mock.validateOnlyElevatedAccess();

        // The owner has access
        vm.startPrank(origamiMultisig);
        mock.validateOnlyElevatedAccess();

        // Set alice to now have explicit access too
        setExplicitAccess(mock, alice, MockUpgradeable.validateOnlyElevatedAccess.selector, true);
        vm.startPrank(alice);
        mock.validateOnlyElevatedAccess();
    }

    function test_onlyElevatedAccess_explicitExternal() public {
        // When not using `this.`, have to set to the external function we are calling
        // ie checkSig()
        {
            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
            mock.checkSig();

            vm.startPrank(origamiMultisig);
            setExplicitAccess(mock, alice, MockUpgradeable.checkSig.selector, true);

            vm.startPrank(alice);
            mock.checkSig();
        }

        // When using `this.`, have to set it to the thing which calls that external function
        // ie the mock contract calling validateOnlyElevatedAccess()
        {
            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
            mock.checkSigThis();

            vm.startPrank(origamiMultisig);
            setExplicitAccess(mock, address(mock), MockUpgradeable.validateOnlyElevatedAccess.selector, true);

            vm.startPrank(alice);
            mock.checkSigThis();
        }
    }
}
