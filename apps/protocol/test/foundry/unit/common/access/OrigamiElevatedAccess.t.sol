pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase */
contract Mock is OrigamiElevatedAccess {
    constructor(
        address _initialOwner
    ) OrigamiElevatedAccess(_initialOwner)
    // solhint-disable-next-line no-empty-blocks
    {}

    // solhint-disable-next-line no-empty-blocks
    function validateOnlyElevatedAccess() public view onlyElevatedAccess {}

    function checkSig() public view {
        validateOnlyElevatedAccess();
    }

    function init(address _owner) external {
        _init(_owner);
    }

    function checkSigThis() public view {
        this.validateOnlyElevatedAccess();
    }

    // A magic function with a signature of 0x00000000
    function wycpnbqcyf() external view onlyElevatedAccess {}
}

contract OrigamiElevatedAccessTestBase is OrigamiTest {
    Mock public mock;

    function setUp() public {
        mock = new Mock(origamiMultisig);
    }

}

contract OrigamiElevatedAccessTest is OrigamiElevatedAccessTestBase {

    function test_initialization() public {
        assertEq(mock.owner(), origamiMultisig);
    }

    function test_construction_fail() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        mock = new Mock(address(0));
    }
    
    function test_re_init_fail() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        mock.init(alice);
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

contract OrigamiElevatedAccessTestSetters is OrigamiElevatedAccessTestBase {
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

contract OrigamiElevatedAccessTestModifiers is OrigamiElevatedAccessTestBase {
    function test_onlyElevatedAccess() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        mock.validateOnlyElevatedAccess();

        // The owner has access
        vm.startPrank(origamiMultisig);
        mock.validateOnlyElevatedAccess();

        // Set alice to now have explicit access too
        setExplicitAccess(mock, alice, Mock.validateOnlyElevatedAccess.selector, true);
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
            setExplicitAccess(mock, alice, Mock.checkSig.selector, true);

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
            setExplicitAccess(mock, address(mock), Mock.validateOnlyElevatedAccess.selector, true);

            vm.startPrank(alice);
            mock.checkSigThis();
        }
    }
}
