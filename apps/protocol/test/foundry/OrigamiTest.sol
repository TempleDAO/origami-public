pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Test, StdChains } from "forge-std/Test.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

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

    // Fork using .env $<CHAIN_ALIAS>_RPC_URL (or the default RPC URL), and a specified blockNumber.
    function fork(string memory chainAlias, uint256 _blockNumber) internal {
        blockNumber = _blockNumber;
        chain = getChain(chainAlias);
        forkId = vm.createSelectFork(chain.rpcUrl, _blockNumber);
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

}
