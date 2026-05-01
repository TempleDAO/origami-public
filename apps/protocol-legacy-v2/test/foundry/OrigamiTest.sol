pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Test, StdChains } from "forge-std/Test.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRecoverToken {
    function recoverToken(address token, address to, uint256 amount) external;
}

/// @notice A forge test base class which can setup to use a fork, deploy UUPS proxies, etc
abstract contract OrigamiTest is Test {
    uint256 internal forkId;
    uint256 internal blockNumber;
    StdChains.Chain internal chain;

    address public unauthorizedUser = makeAddr("unauthorizedUser");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public origamiMultisig = makeAddr("origamiMultisig");
    address public overlord = makeAddr("overlord");
    address public feeCollector = makeAddr("feeCollector");

    constructor() {
        setChain("berachain_bartio_testnet", StdChains.ChainData({
            name: "berachain_bartio_testnet",
            chainId: 80084,
            rpcUrl: "https://bartio.rpc.berachain.com/"
        }));
        setChain("berachain_bepolia_testnet", StdChains.ChainData({
            name: "berachain_bepolia_testnet",
            chainId: 80069,
            rpcUrl: "https://bepolia.rpc.berachain.com/"
        }));
        string memory defaultUrl = "https://rpc.berachain.com/";
        setChain("berachain_mainnet", StdChains.ChainData({
            name: "berachain_mainnet",
            chainId: 80094,
            rpcUrl: vm.envOr("BERACHAIN_RPC_URL", defaultUrl)
        }));
    }
    
    bytes32 private constant _EIP712_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Fork using .env $<CHAIN_ALIAS>_RPC_URL (or the default RPC URL), and a specified blockNumber.
    function fork(string memory chainAlias, uint256 _blockNumber) internal {
        blockNumber = _blockNumber;
        chain = getChain(chainAlias);
        try vm.createSelectFork(chain.rpcUrl, _blockNumber) returns (uint256 _forkId) {
            // worked ok
            forkId = _forkId;
        } catch {
            // Try one more time - sometimes there's transient network issues depending on connection
            forkId = vm.createSelectFork(chain.rpcUrl, _blockNumber);
        }
    }

    /// @dev Deploy a new UUPS Proxy, given an implementation.
    /// There is no checking that the implmentation is a valid proxy here
    /// so until foundry has better utilities for this, best to deploy & test upgrades
    /// using hardhat/upgrades (which has really good sanity checks)
    function deployUUPSProxy(address _implementation) internal returns (address) {
        return address(new ERC1967Proxy(_implementation, ""));
    }

    function expectElevatedAccess() internal {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
    }

    function setExplicitAccess(
        IOrigamiElevatedAccess theContract, 
        address allowedCaller, 
        bytes4 fnSelector, 
        bool value
    ) internal {
        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](1);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector, value);
        theContract.setExplicitAccess(allowedCaller, access);
    }

    function setExplicitAccess(
        IOrigamiElevatedAccess theContract, 
        address allowedCaller, 
        bytes4 fnSelector1, 
        bytes4 fnSelector2, 
        bool value
    ) internal {
        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](2);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector1, value);
        access[1] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector2, value);
        theContract.setExplicitAccess(allowedCaller, access);
    }

    function doMint(IERC20 token, address account, uint256 amount) internal {
        deal(address(token), account, token.balanceOf(account) + amount, true);
    }

    function doBurn(IERC20 token, address account, uint256 amount) internal {
        deal(address(token), account, token.balanceOf(account) - amount, true);
    }

    function check_recoverToken(address testContract) public {
        uint256 amount = 100 ether;
        DummyMintableToken token = new DummyMintableToken(origamiMultisig, "fake", "fake", 18);

        vm.startPrank(origamiMultisig);
        token.addMinter(origamiMultisig);
        token.mint(testContract, amount);

        vm.expectEmit();
        emit CommonEventsAndErrors.TokenRecovered(alice, address(token), amount);
        IRecoverToken(testContract).recoverToken(address(token), alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(testContract), 0);
    }

    function buildDomainSeparator(IERC20Permit erc20) private view returns (bytes32) {
        bytes32 _hashedName = keccak256(bytes(IERC20Metadata(address(erc20)).name()));
        bytes32 _hashedVersion = keccak256(bytes("1"));
        return keccak256(abi.encode(_EIP712_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(erc20)));
    }

    function signedPermit(
        IERC20Permit erc20,
        address signer, 
        uint256 signerPk, 
        address spender, 
        uint256 amount, 
        uint256 deadline
    ) private view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = buildDomainSeparator(erc20);
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, signer, spender, amount, erc20.nonces(signer), deadline));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        return vm.sign(signerPk, typedDataHash);
    }

    function check_permit(IERC20Permit erc20) internal {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");
        address spender = makeAddr("spender");
        uint256 amount = 123;

        assertEq(erc20.nonces(signer), 0);
        uint256 allowanceBefore = IERC20(address(erc20)).allowance(signer, spender);

        // Check for expired deadlines
        uint256 deadline = block.timestamp-1;
        (uint8 v, bytes32 r, bytes32 s) = signedPermit(erc20, signer, signerPk, spender, amount, deadline);
        vm.expectRevert("ERC20Permit: expired deadline");

        erc20.permit(signer, spender, amount, deadline, v, r, s);

        // Permit successfully increments the allowance
        deadline = block.timestamp + 3600;
        (v, r, s) = signedPermit(erc20, signer, signerPk, spender, amount, deadline);
        erc20.permit(signer, spender, amount, deadline, v, r, s);
        assertEq(IERC20(address(erc20)).allowance(signer, spender), allowanceBefore+amount);
        assertEq(erc20.nonces(signer), 1);

        // Can't re-use the same signature for another permit (the nonce was incremented)
        vm.expectRevert("ERC20Permit: invalid signature");

        erc20.permit(signer, spender, amount, deadline, v, r, s);
    }
}
