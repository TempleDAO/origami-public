pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { Call } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { Test } from "forge-std/Test.sol";

contract OrigamiBundlerTestUtils is Test {
    function checkInvalidBundler(address user) internal {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, user));
    }

    function createCall(IOrigamiBundlerPlugin to, bytes memory data) internal pure returns (Call memory) {
        return Call({ to: address(to), data: data, value: 0, skipRevert: false, callbackHash: bytes32(0) });
    }

    function createCall(IOrigamiBundlerPlugin to, bytes memory data, bytes32 callbackHash)
        internal
        pure
        returns (Call memory)
    {
        return Call({ to: address(to), data: data, value: 0, skipRevert: false, callbackHash: callbackHash });
    }

    function mkArray(Call memory call1) internal pure returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = call1;
    }

    function mkArray(Call memory call1, Call memory call2) internal pure returns (Call[] memory calls) {
        calls = new Call[](2);
        calls[0] = call1;
        calls[1] = call2;
    }

    function mkArray(Call memory call1, Call memory call2, Call memory call3)
        internal
        pure
        returns (Call[] memory calls)
    {
        calls = new Call[](3);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
    }

    function mkArray(Call memory call1, Call memory call2, Call memory call3, Call memory call4)
        internal
        pure
        returns (Call[] memory calls)
    {
        calls = new Call[](4);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
        calls[3] = call4;
    }

    function mkArray(Call memory call1, Call memory call2, Call memory call3, Call memory call4, Call memory call5)
        internal
        pure
        returns (Call[] memory calls)
    {
        calls = new Call[](5);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
        calls[3] = call4;
        calls[4] = call5;
    }

    function mkArray(
        Call memory call1,
        Call memory call2,
        Call memory call3,
        Call memory call4,
        Call memory call5,
        Call memory call6
    ) internal pure returns (Call[] memory calls) {
        calls = new Call[](6);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
        calls[3] = call4;
        calls[4] = call5;
        calls[5] = call6;
    }
}
