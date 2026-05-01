pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { Test } from "forge-std/Test.sol";

contract TestUtilsLib is Test {
    function mkArray(uint256 v1) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = v1;
    }

    function mkArray(uint256 v1, uint256 v2) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = v1;
        arr[1] = v2;
    }

    function mkArray(uint256 v1, uint256 v2, uint256 v3) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = v1;
        arr[1] = v2;
        arr[2] = v3;
    }

    function mkArray(address v1) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = v1;
    }

    function mkArray(address v1, address v2) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = v1;
        arr[1] = v2;
    }

    function mkArray(address v1, address v2, address v3) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = v1;
        arr[1] = v2;
        arr[2] = v3;
    }

    function mkArray(address v1, address v2, address v3, address v4) internal pure returns (address[] memory arr) {
        arr = new address[](4);
        arr[0] = v1;
        arr[1] = v2;
        arr[2] = v3;
        arr[3] = v4;
    }

    function mkArray(address v1, address v2, address v3, address v4, address v5)
        internal
        pure
        returns (address[] memory arr)
    {
        arr = new address[](5);
        arr[0] = v1;
        arr[1] = v2;
        arr[2] = v3;
        arr[3] = v4;
        arr[4] = v5;
    }

    function mkBsData(uint256[] memory assetBalances, uint256[] memory liabilityBalances, bytes memory perAdapterBS)
        internal
        pure
        returns (IOpalManager.BalanceSheetData memory bsd)
    {
        return IOpalManager.BalanceSheetData({
            aggregatedBalanceSheet: IOpalManager.AssetsAndLiabilities(assetBalances, liabilityBalances),
            perAdapterBS: perAdapterBS
        });
    }

    function expectArr(address[] memory arr1, address[] memory arr2) internal pure {
        assertEq(arr1.length, arr2.length);
        for (uint256 i; i < arr1.length; ++i) {
            assertEq(arr1[i], arr2[i]);
        }
    }

    function expectArr(address[] memory arr) internal pure {
        assertEq(arr.length, 0);
    }

    function expectArr(address[] memory arr, address v1) internal pure {
        assertEq(arr.length, 1);
        assertEq(arr[0], v1);
    }

    function expectArr(address[] memory arr, address v1, address v2) internal pure {
        assertEq(arr.length, 2);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
    }

    function expectArr(address[] memory arr, address v1, address v2, address v3) internal pure {
        assertEq(arr.length, 3);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
    }

    function expectArr(address[] memory arr, address v1, address v2, address v3, address v4) internal pure {
        assertEq(arr.length, 4);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
        assertEq(arr[3], v4);
    }

    function expectArr(address[] memory arr, address v1, address v2, address v3, address v4, address v5) internal pure {
        assertEq(arr.length, 5);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
        assertEq(arr[3], v4);
        assertEq(arr[4], v5);
    }

    function expectArr(uint256[] memory arr1, uint256[] memory arr2) internal pure {
        assertEq(arr1.length, arr2.length);
        for (uint256 i; i < arr1.length; ++i) {
            assertEq(arr1[i], arr2[i]);
        }
    }

    function expectArr(uint256[] memory arr) internal pure {
        assertEq(arr.length, 0);
    }

    function expectArr(uint256[] memory arr, uint256 v1) internal pure {
        assertEq(arr.length, 1);
        assertEq(arr[0], v1);
    }

    function expectArr(uint256[] memory arr, uint256 v1, uint256 v2) internal pure {
        assertEq(arr.length, 2);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
    }

    function expectArr(uint256[] memory arr, uint256 v1, uint256 v2, uint256 v3) internal pure {
        assertEq(arr.length, 3);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
    }

    function expectArr(uint256[] memory arr, uint256 v1, uint256 v2, uint256 v3, uint256 v4) internal pure {
        assertEq(arr.length, 4);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
        assertEq(arr[3], v4);
    }

    function expectArr(uint256[] memory arr, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5) internal pure {
        assertEq(arr.length, 5);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
        assertEq(arr[3], v4);
        assertEq(arr[4], v5);
    }

    function expectArr(IOpalManager.AdapterToCombinedIndexMapItem[] memory arr) internal pure {
        assertEq(arr.length, 0);
    }

    function expectArr(
        IOpalManager.AdapterToCombinedIndexMapItem[] memory arr,
        address token1,
        uint256 combinedIndex1,
        address token2,
        uint256 combinedIndex2
    ) internal pure {
        assertEq(arr.length, 2);
        assertEq(arr[0].token, token1);
        assertEq(arr[0].combinedIndex, combinedIndex1);
        assertEq(arr[1].token, token2);
        assertEq(arr[1].combinedIndex, combinedIndex2);
    }

    function expectArr(bytes32[] memory arr) internal pure {
        assertEq(arr.length, 0);
    }

    function expectArr(bytes32[] memory arr, bytes32 v1) internal pure {
        assertEq(arr.length, 1);
        assertEq(arr[0], v1);
    }

    function expectArr(bytes32[] memory arr, bytes32 v1, bytes32 v2) internal pure {
        assertEq(arr.length, 2);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
    }

    function expectArr(bytes32[] memory arr, bytes32 v1, bytes32 v2, bytes32 v3) internal pure {
        assertEq(arr.length, 3);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
        assertEq(arr[2], v3);
    }
}
