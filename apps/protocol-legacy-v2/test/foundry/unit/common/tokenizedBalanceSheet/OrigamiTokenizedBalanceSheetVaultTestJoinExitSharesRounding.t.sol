pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { OrigamiTokenizedBalanceSheetVaultTestBase } from "test/foundry/unit/common/tokenizedBalanceSheet/OrigamiTokenizedBalanceSheetVault.t.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

/*
Test join and exit with shares and tokens

The invariant that must be satisfied for any join or exit operation is as following:
The vault's balance must not decrease after any operation. 
Since assets are positive and liabilities are negative for the balance, the following conditions must be satisfied:
1) Assets per share must not decrease
2) Liabilities per share must not increase

This translates to the following math (for the vault total assets, liabilities and shares):
1) assets_after / shares_after >= assets_before / shares_before
assets_after * shares_before >= assets_before * shares_after
2) liabilities_after / shares_after <= liabilities_before / shares_before
liabilities_after * shares_before <= liabilities_before * shares_after

Additional invariant should be satisfied:
- the amount of shares, assets or liability specified by the user must match the actual amount sent to or pulled from the user

The following cases are possible:
- join with shares
- join with assets
- join with liabilities
- exit with shares
- exit with assets
- exit with liabilities

There are also 2 possible comparisions between shares and assets (liabilities):

1) A lot more shares than assets (liabilities)
Example: shares = 100, assets = 2, liabilities = 2

In this case many different amounts of shares lead to the same amount of assets (liabilities), making inverse calculation 
(shares from assets or liabilities) ambiguous, example with exit amounts:
0 shares -> 0 assets, 0 liabilities
1 shares -> 0 assets, 1 liabilities
2 shares -> 0 assets, 1 liabilities
...
49 shares -> 0 assets, 1 liabilities
50 shares -> 1 assets, 1 liabilities
51 shares -> 1 assets, 2 liabilities
..
99 shares -> 1 assets, 2 liabilities
100 shares -> 2 assets, 2 liabilities

When joining, the best choice for the user here which satisfies the invariant above is:
- choose the largest possible amount of shares with the assets (mint max shares for assets token sent by user)
- choose the smallest possible amount of shares with the liabilities (mint min shares for debt token sent to user)

When exiting, the best choice for the user here which satisfies the invariant above is:
- choose the largest possible amount of shares with the liabilities (burn max shares for debt token sent by user)
- choose the smallest possible amount of shares with the assets (burn min shares for assets token sent to user)

Note: Since preview functions must choose some shares value, we choose the default ones (for exits in token: the
 smallest amount of shares for assets, the largest amount of shares for liabilities), but when exiting with liability 
 this amount can exceed user's shares balance, so this should be treated accordingly.

2) A lot more assets (liabilities) than shares

Example: shares = 2, assets = 99, liabilities = 99
In this case many different amounts of assets (liabilities) lead to the same amount of shares, making direct calculation 
(shares to assets and liabilities) ambiguous, example with join amounts:
0 shares -> [0..49] assets, 0 liabilities
1 shares -> [50..99] assets, [1..49] liabilities
2 shares -> [99..148] assets, [50..99] liabilities

When joining with shares, the best choice for the user here which satisfies the invariant above is:
- choose the largest possible amount of liabilities (send max debt token to user)
- choose the smallest possible amount of assets (user sends min asset token to vault)

When exiting, the best choice for the user here which satisfies the invariant above is:
- choose the largest possible amount of assets (send max asset token to user)
- choose the smallest possible amount of liabilities (user sends min debt token to vault)

Note: since preview functions must choose some asset/liability value, we choose the default ones, but unlike the 1st case,
 we don't care about user balance of assets/liabilities as there is no "fixed" user balance of tokens when he exits, 
 and we don't care about the balance of his tokens when he joins with shares. There is, however, a special case when 
 user joins with assets or liabilities amount, then amount must match what user specified, e.g.:
- User wants to join with 74 assets:
 * he is minted 1 share
 * 74 assets pulled from user (not 50 assets if we calculate default amount for 1 share!)
 * 49 liabilities are sent to user

*/

contract OrigamiTokenizedBalanceSheetVaultTestJoinExitSharesRounding is OrigamiTokenizedBalanceSheetVaultTestBase {

    uint256 public constant MAX_AMOUNT = 10_000_000;

    uint256 public sharesBefore;
    uint256 public asset1Before;
    uint256 public asset2Before;
    uint256 public liability1Before;
    uint256 public liability2Before;

    function setUp() public override {
    }

    function createVault(
        uint256 _sharesBefore,
        uint256 _asset1Before,
        uint256 _asset2Before,
        uint256 _liability1Before,
        uint256 _liability2Before
    ) internal {
        setUpWithFees(0, 0);

        debt1.deal(address(borrowLend), type(uint200).max);
        debt2.deal(address(borrowLend), type(uint200).max);

        sharesBefore = _sharesBefore;
        asset1Before = _asset1Before;
        asset2Before = _asset2Before;
        liability1Before = _liability1Before;
        liability2Before = _liability2Before;

        uint256[] memory assetAmounts = new uint256[](2);
        (assetAmounts[0], assetAmounts[1]) = (asset1Before, asset2Before);

        uint256[] memory liabilityAmounts = new uint256[](2);
        (liabilityAmounts[0], liabilityAmounts[1]) = (liability1Before, liability2Before);

        vm.startPrank(origamiMultisig);
        asset1.deal(origamiMultisig, assetAmounts[0]);
        asset1.approve(address(vault), assetAmounts[0]);
        asset2.deal(origamiMultisig, assetAmounts[1]);
        asset2.approve(address(vault), assetAmounts[1]);
        vault.seed(assetAmounts, liabilityAmounts, sharesBefore, origamiMultisig, type(uint256).max);

        vm.stopPrank();
    }

    function checkInvariant1(uint256 sharesAfter, uint256[] memory assetsAfter, uint256[] memory liabilitiesAfter) view internal {
        assertGe(assetsAfter[0] * sharesBefore, asset1Before * sharesAfter, "Asset1 / share decreased");
        assertGe(assetsAfter[1] * sharesBefore, asset2Before * sharesAfter, "Asset2 / share decreased");
        assertLe(liabilitiesAfter[0] * sharesBefore, liability1Before * sharesAfter, "Liability1 / share increased");
        assertLe(liabilitiesAfter[1] * sharesBefore, liability2Before * sharesAfter, "Liability2 / share increased");
    }

    function checkInvariant1() view internal {
        uint256 sharesAfter = vault.totalSupply();
        (uint256[] memory assetsAfter, uint256[] memory liabilitiesAfter) = vault.balanceSheet();

        checkInvariant1(sharesAfter, assetsAfter, liabilitiesAfter);
    }

    function checkInvariant2Join(uint shares, uint assets1, uint assets2, uint liability1, uint liability2) view internal {
        uint256 sharesAfter = vault.totalSupply();
        (uint256[] memory assetsAfter, uint256[] memory liabilitiesAfter) = vault.balanceSheet();

        assertEq(sharesAfter - sharesBefore, shares, "Actual join shares mismatch");
        assertEq(assetsAfter[0] - asset1Before, assets1, "Actual join asset1 mismatch");
        assertEq(assetsAfter[1] - asset2Before, assets2, "Actual join asset2 mismatch");
        assertEq(liabilitiesAfter[0] - liability1Before, liability1, "Actual join liability1 mismatch");
        assertEq(liabilitiesAfter[1] - liability2Before, liability2, "Actual join liability2 mismatch");
    }

    function checkInvariant2Exit(uint shares, uint assets1, uint assets2, uint liability1, uint liability2) view internal {
        uint256 sharesAfter = vault.totalSupply();
        (uint256[] memory assetsAfter, uint256[] memory liabilitiesAfter) = vault.balanceSheet();

        assertEq(sharesBefore - sharesAfter, shares, "Actual exit shares mismatch");
        assertEq(asset1Before - assetsAfter[0], assets1, "Actual exit asset1 mismatch");
        assertEq(asset2Before - assetsAfter[1], assets2, "Actual exit asset2 mismatch");
        assertEq(liability1Before - liabilitiesAfter[0], liability1, "Actual exit liability1 mismatch");
        assertEq(liability2Before - liabilitiesAfter[1], liability2, "Actual exit liability2 mismatch");
    }

    function checkInvariant1Exit(uint256 shares, uint256[] memory assets, uint256[] memory liabilities) view internal {
        assertGe(vault.totalSupply(), shares, "Trying to exit more shares than vault has");
        uint256 sharesAfter = vault.totalSupply() - shares;
        (uint256[] memory assetsAfter, uint256[] memory liabilitiesAfter) = vault.balanceSheet();
        for (uint i = 0; i < assetsAfter.length; i++) {
            assertGe(assetsAfter[i], assets[i], "Trying to exit more assets than vault has");
            assetsAfter[i] -= assets[i];
            assertGe(liabilitiesAfter[i], liabilities[i], "Trying to exit more liability than vault has");
            liabilitiesAfter[i] -= liabilities[i];
        }

        checkInvariant1(sharesAfter, assetsAfter, liabilitiesAfter);
    }

    function checkInvariant1Join(uint256 shares, uint256[] memory assets, uint256[] memory liabilities) view internal {
        uint256 sharesAfter = vault.totalSupply() + shares;
        (uint256[] memory assetsAfter, uint256[] memory liabilitiesAfter) = vault.balanceSheet();
        for (uint i = 0; i < assetsAfter.length; i++) {
            assetsAfter[i] += assets[i];
            liabilitiesAfter[i] += liabilities[i];
        }

        checkInvariant1(sharesAfter, assetsAfter, liabilitiesAfter);
    }

    function test_previewJoinExit_fuzz(
        uint256 i, 
        uint96 _sharesBefore,
        uint96 _asset1Before, 
        uint96 _asset2Before, 
        uint96 _liability1Before,
        uint96 _liability2Before,
        uint96 _amount
    ) public {
        i = _bound(i, 0, 9);
        _sharesBefore = uint96(_bound(_sharesBefore, 1, MAX_AMOUNT * 1e18));
        _asset1Before = uint96(_bound(_asset1Before, 1, MAX_AMOUNT * 1e18));
        _asset2Before = uint96(_bound(_asset2Before, 1, MAX_AMOUNT * 1e6));
        _liability1Before = uint96(_bound(_liability1Before, 1, MAX_AMOUNT * 1e18));
        _liability2Before = uint96(_bound(_liability2Before, 1, MAX_AMOUNT * 1e6));
        _amount = uint96(_bound(_amount, 1, MAX_AMOUNT * 1e18));

        createVault(_sharesBefore, _asset1Before, _asset2Before, _liability1Before, _liability2Before);
        testJoinExit(i, _amount);
    }

    function test_previewJoinExit1() public {
        for (uint i; i < 10; i++) {
            createVault(21, 11, 11000001, 11, 11000001);
            testJoinExit(i, 1);
        }
    }

    function test_previewJoinExit2() public {
        for (uint i; i < 10; i++) {
            createVault(1, 1, 100, 1, 100);
            testJoinExit(i, 1);
        }
    }

    function test_previewJoinExit3() public {
        createVault(1, 1, 100, 1, 100);
        testJoinExit(4, 50); // join with liability2 = 50 (send token to user)

        createVault(1, 1, 100, 1, 100);
        testJoinExit(2, 50); // join with asset2 = 50 (mint 0 shares)
    }

    // default shares amount exceeds user balance
    function test_previewExit1() public {
        createVault(100, 1, 1000, 1, 1000);
        
        uint256 sharesDelta;
        uint256[] memory assetsDelta;
        uint256[] memory liabilitiesDelta;

        prepare(alice);

        // give alice only 1 share
        deal(address(vault), alice, 1);

        assertEq(vault.maxExitWithToken(address(debt1), alice), 0);

        (sharesDelta, assetsDelta, liabilitiesDelta) = vault.previewExitWithToken(address(debt1), 1);
        checkInvariant1Exit(sharesDelta, assetsDelta, liabilitiesDelta);

        // actual exit
        vm.prank(alice);
        // will revert trying to burn shares exceeding user shares balance
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(debt1), 1, 0));
        vault.exitWithToken(address(debt1), 1, address(alice), address(alice));
    }

    function prepare(address who) internal {
        asset1.deal(who, type(uint200).max);
        asset2.deal(who, type(uint200).max);
        debt1.deal(who, type(uint200).max);
        debt2.deal(who, type(uint200).max);

        deal(address(vault), alice, vault.totalSupply());

        vm.startPrank(who);
        asset1.approve(address(vault), type(uint256).max);
        asset2.approve(address(vault), type(uint256).max);
        debt1.approve(address(vault), type(uint256).max);
        debt2.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function testJoinExit(uint what, uint amount) internal {
        uint256 sharesDelta;
        uint256[] memory assetsDelta;
        uint256[] memory liabilitiesDelta;

        prepare(alice);

        if (what == 0) {
            sharesDelta = amount;
            (assetsDelta, liabilitiesDelta) = vault.previewJoinWithShares(sharesDelta);
            checkInvariant1Join(sharesDelta, assetsDelta, liabilitiesDelta);

            // actual join
            vm.prank(alice);
            vault.joinWithShares(amount, address(alice));
            checkInvariant1();
            checkInvariant2Join(amount, assetsDelta[0], assetsDelta[1], liabilitiesDelta[0], liabilitiesDelta[1]);
        }

        if (what == 1 || what == 2) {
            address asset = address(what == 1 ? asset1 : asset2);
            uint8 decimals = asset == address(asset1) ? 18 : 6;
            amount = _bound(amount, 1, MAX_AMOUNT * (10**decimals));
            (sharesDelta, assetsDelta, liabilitiesDelta) = vault.previewJoinWithToken(asset, amount);
            if (sharesDelta == 0) return;

            checkInvariant1Join(sharesDelta, assetsDelta, liabilitiesDelta);

            // actual join
            vm.prank(alice);
            vault.joinWithToken(asset, amount, address(alice));
            checkInvariant1();
            checkInvariant2Join(sharesDelta, what == 1 ? amount : assetsDelta[0], what == 2 ? amount : assetsDelta[1], liabilitiesDelta[0], liabilitiesDelta[1]);
        }

        if (what == 3 || what == 4) {
            address asset = address(what == 3 ? debt1 : debt2);
            uint8 decimals = asset == address(debt1) ? 18 : 6;
            amount = _bound(amount, 1, MAX_AMOUNT * (10**decimals));
            (sharesDelta, assetsDelta, liabilitiesDelta) = vault.previewJoinWithToken(asset, amount);
            if (sharesDelta == 0) return;

            checkInvariant1Join(sharesDelta, assetsDelta, liabilitiesDelta);

            // actual join
            vm.prank(alice);
            vault.joinWithToken(asset, amount, address(alice));
            checkInvariant1();
            checkInvariant2Join(sharesDelta, assetsDelta[0], assetsDelta[1], what == 3 ? amount : liabilitiesDelta[0], what == 4 ? amount : liabilitiesDelta[1]);
        }

        if (what == 5) {
            amount = _bound(amount, 1, vault.maxExitWithShares(alice));
            sharesDelta = amount;
            (assetsDelta, liabilitiesDelta) = vault.previewExitWithShares(sharesDelta);
            checkInvariant1Exit(sharesDelta, assetsDelta, liabilitiesDelta);

            // actual exit
            vm.prank(alice);
            vault.exitWithShares(amount, address(alice), address(alice));
            checkInvariant1();
            checkInvariant2Exit(amount, assetsDelta[0], assetsDelta[1], liabilitiesDelta[0], liabilitiesDelta[1]);
        }

        if (what == 6 || what == 7) {
            address asset = address(what == 6 ? asset1 : asset2);
            uint8 decimals = asset == address(asset1) ? 18 : 6;
            amount = _bound(amount, 0, MAX_AMOUNT * (10**decimals));
            amount = _bound(amount, 1, vault.maxExitWithToken(asset, alice));

            (sharesDelta, assetsDelta, liabilitiesDelta) = vault.previewExitWithToken(asset, amount);
            if (sharesDelta == 0) return;

            checkInvariant1Exit(sharesDelta, assetsDelta, liabilitiesDelta);

            // actual exit
            vm.prank(alice);
            vault.exitWithToken(asset, amount, address(alice), address(alice));
            checkInvariant1();
            checkInvariant2Exit(sharesDelta, what == 6 ? amount : assetsDelta[0], what == 7 ? amount : assetsDelta[1], liabilitiesDelta[0], liabilitiesDelta[1]);
        }

        if (what == 8 || what == 9) {
            address asset = address(what == 8 ? debt1 : debt2);
            uint8 decimals = asset == address(debt1) ? 18 : 6;
            amount = _bound(amount, 1, MAX_AMOUNT * (10**decimals));
            amount = _bound(amount, 1, vault.maxExitWithToken(asset, alice));

            (sharesDelta, assetsDelta, liabilitiesDelta) = vault.previewExitWithToken(asset, amount);
            if (sharesDelta == 0) return;

            checkInvariant1Exit(sharesDelta, assetsDelta, liabilitiesDelta);

            // actual exit1
            vm.prank(alice);
            vault.exitWithToken(asset, amount, address(alice), address(alice));
            checkInvariant1();
            checkInvariant2Exit(sharesDelta, assetsDelta[0], assetsDelta[1], what == 8 ? amount : liabilitiesDelta[0], what == 9 ? amount : liabilitiesDelta[1]);
        }
    }

}