pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

abstract contract OrigamiTokenizedBalanceSheetTestUtils is OrigamiTest {
    function getVault() internal view virtual returns (IOrigamiTokenizedBalanceSheetVault);

    function checkBalanceSheet(uint256[] memory expectedAssets, uint256[] memory expectedLiabilities) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = getVault().balanceSheet();
        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }

    function checkConvertFromToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256[] memory expectedAssets,
        uint256[] memory expectedLiabilities
    ) internal view {
        (uint256 shares, uint256[] memory assets, uint256[] memory liabilities) =
            getVault().convertFromToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "convertFromToken::shares");
        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }

    function checkConvertFromShares(
        uint256 shares,
        uint256[] memory expectedAssets,
        uint256[] memory expectedLiabilities
    ) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = getVault().convertFromShares(shares);
        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }

    function checkPreviewJoinWithShares(
        uint256 shares,
        uint256[] memory expectedAssets,
        uint256[] memory expectedLiabilities
    ) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = getVault().previewJoinWithShares(shares);
        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }

    function checkPreviewJoinWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256[] memory expectedAssets,
        uint256[] memory expectedLiabilities
    ) internal view {
        (uint256 shares, uint256[] memory assets, uint256[] memory liabilities) =
            getVault().previewJoinWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewJoinWithToken::shares");
        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }

    function checkPreviewExitWithShares(
        uint256 shares,
        uint256[] memory expectedAssets,
        uint256[] memory expectedLiabilities
    ) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = getVault().previewExitWithShares(shares);

        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }

    function checkPreviewExitWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256[] memory expectedAssets,
        uint256[] memory expectedLiabilities
    ) internal view {
        (uint256 shares, uint256[] memory assets, uint256[] memory liabilities) =
            getVault().previewExitWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewExitWithToken::shares");
        expectArr(assets, expectedAssets);
        expectArr(liabilities, expectedLiabilities);
    }
}
