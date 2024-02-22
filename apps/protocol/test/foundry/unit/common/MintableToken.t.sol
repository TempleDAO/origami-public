pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { MintableToken } from "contracts/common/MintableToken.sol";

contract MintableTokenTestBase is OrigamiTest {
    DummyMintableToken public token;

    function setUp() public {
        token = new DummyMintableToken(origamiMultisig, "TOKEN", "TKN", 18);
        vm.warp(100000000);
    }
}

contract MintableTokenTestAdmin is MintableTokenTestBase {
    event AddedMinter(address indexed account);
    event RemovedMinter(address indexed account);

    function test_initialization() public {
        assertEq(token.name(), "TOKEN");
        assertEq(token.symbol(), "TKN");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.isMinter(alice), false);
    }

    function test_addMinter_success() public {
        assertEq(token.isMinter(alice), false);
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(token));
        emit AddedMinter(alice);
        token.addMinter(alice);
        assertEq(token.isMinter(alice), true);
    }

    function test_removeMinter_success() public {
        vm.startPrank(origamiMultisig);
        token.addMinter(alice);
        assertEq(token.isMinter(alice), true);

        vm.expectEmit(address(token));
        emit RemovedMinter(alice);
        token.removeMinter(alice);
        assertEq(token.isMinter(alice), false);
    }

    function test_recoverToken() public {
        check_recoverToken(address(token));
    }
}

contract MintableTokenTestAccess is MintableTokenTestBase {
    function test_mint_access() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(MintableToken.CannotMintOrBurn.selector, unauthorizedUser));
        token.mint(alice, 10);
    }

    function test_burn_access() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(MintableToken.CannotMintOrBurn.selector, unauthorizedUser));
        token.burn(alice, 10);
    }

    function test_addMinter_access() public {
        expectElevatedAccess();
        token.addMinter(alice);
    }

    function test_removeMinter_access() public {
        expectElevatedAccess();
        token.removeMinter(alice);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        token.recoverToken(alice, alice, 100e18);
    }
}

contract MintableTokenTestMintAndBurn is MintableTokenTestBase {
    function test_mint_success() public {
        vm.startPrank(origamiMultisig);
        token.addMinter(origamiMultisig);

        token.mint(alice, 10);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.totalSupply(), 10);

        vm.expectRevert("ERC20: mint to the zero address");
        token.mint(address(0), 10);
    }

    function test_burn_success() public {
        vm.startPrank(origamiMultisig);
        token.addMinter(origamiMultisig);

        token.mint(alice, 100);
        token.burn(alice, 10);
        assertEq(token.balanceOf(alice), 90);
        assertEq(token.totalSupply(), 90);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.burn(alice, 100);
    }
}

contract MintableTokenTestPermit is MintableTokenTestBase {

    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function buildDomainSeparator() internal view returns (bytes32) {
        bytes32 _hashedName = keccak256(bytes(token.name()));
        bytes32 _hashedVersion = keccak256(bytes("1"));
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(token)));
    }

    function signedPermit(
        address signer, 
        uint256 signerPk, 
        address spender, 
        uint256 amount, 
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = buildDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, signer, spender, amount, token.nonces(signer), deadline));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        return vm.sign(signerPk, typedDataHash);
    }

    function test_permit() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");
        address spender = makeAddr("spender");
        uint256 amount = 123;

        uint256 allowanceBefore = token.allowance(signer, spender);

        // Check for expired deadlines
        uint256 deadline = block.timestamp-1;
        (uint8 v, bytes32 r, bytes32 s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vm.expectRevert("ERC20Permit: expired deadline");
        token.permit(signer, spender, amount, deadline, v, r, s);

        // Permit successfully increments the allowance
        deadline = block.timestamp + 3600;
        (v, r, s) = signedPermit(signer, signerPk, spender, amount, deadline);
        token.permit(signer, spender, amount, deadline, v, r, s);
        assertEq(token.allowance(signer, spender), allowanceBefore+amount);

        // Can't re-use the same signature for another permit (the nonce was incremented)
        vm.expectRevert("ERC20Permit: invalid signature");
        token.permit(signer, spender, amount, deadline, v, r, s);
    }
}