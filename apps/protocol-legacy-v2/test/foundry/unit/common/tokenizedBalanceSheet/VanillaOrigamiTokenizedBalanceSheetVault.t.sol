pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { MockTokenizedBalanceSheetVaultWithFees } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockTokenizedBalanceSheetVaultWithFees.m.sol";
import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";

contract VanillaOrigamiTokenizedBalanceSheetVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableTokenPermissionless internal asset1;
    DummyMintableTokenPermissionless internal asset2;
    DummyMintableTokenPermissionless internal debt1;
    DummyMintableTokenPermissionless internal debt2;
    MockTokenizedBalanceSheetVaultWithFees internal vault;
    MockBorrowLend internal borrowLend;

    uint256 internal constant MAX_TOTAL_SUPPLY = type(uint256).max;
    uint16 internal immutable JOIN_FEE = 0;
    uint16 internal immutable EXIT_FEE = 0;

    uint256 internal constant SEED_SHARES = 100e18;
    uint256 internal constant SEED_ASSET1 = 1e18;
    uint256 internal constant SEED_ASSET2 = 50e6;
    uint256 internal constant SEED_LIABILITY1 = 2e18;
    uint256 internal constant SEED_LIABILITY2 = 25e6;

    event Join(
        address indexed sender,
        address indexed owner,
        uint256[] assets,
        uint256[] liabilities,
        uint256 shares
    );

    event Exit(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256[] assets,
        uint256[] liabilities,
        uint256 shares
    );

    event InKindFees(IOrigamiTokenizedBalanceSheetVault.FeeType feeType, uint256 feeBps, uint256 feeAmount);

    error PRBMath_MulDiv_Overflow(uint256 x, uint256 y, uint256 denominator);

    function setUpWithNoFees() internal {
        asset1 = new DummyMintableTokenPermissionless("ASSET1_18dp", "ASSET1_18dp", 18);
        asset2 = new DummyMintableTokenPermissionless("ASSET2_6dp", "ASSET2_6", 6);
        address[] memory _assets = new address[](2);
        (_assets[0], _assets[1]) = (address(asset1), address(asset2));

        debt1 = new DummyMintableTokenPermissionless("DEBT1_18dp", "DEBT1_18dp", 18);
        debt2 = new DummyMintableTokenPermissionless("DEBT2_6dp", "DEBT2_6dp", 6);
        
        vm.label(address(asset1), "ASSET1");
        vm.label(address(asset2), "ASSET2");
        vm.label(address(debt1), "DEBT1");
        vm.label(address(debt2), "DEBT2");

        address[] memory _liabilities = new address[](2);
        (_liabilities[0], _liabilities[1]) = (address(debt1), address(debt2));

        borrowLend = new MockBorrowLend(_assets, _liabilities);

        vault = new MockTokenizedBalanceSheetVaultWithFees(
            origamiMultisig, 
            "TokenizedBalanceSheet",
            "TBSV",
            _assets,
            _liabilities,
            0,
            0,
            borrowLend
        );
        
        vm.warp(100000000);

        asset1.deal(address(this), type(uint168).max);
        asset2.deal(address(this), type(uint168).max);
        asset1.approve(address(borrowLend), type(uint168).max);
        asset2.approve(address(borrowLend), type(uint168).max);
    }

    function setUp() public virtual {
        setUpWithNoFees();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
    }

    function _checkInputTokenAmount(
        IERC20 token,
        uint256 tokenAmount,
        uint256[] memory assetAmounts,
        uint256[] memory liabilityAmounts
    ) private view {
        if (address(token) == address(asset1)) assertEq(assetAmounts[0], tokenAmount, "asset1 input tokenAmount not matching derived output amount");
        if (address(token) == address(asset2)) assertEq(assetAmounts[1], tokenAmount, "asset2 input tokenAmount not matching derived output amount");
        if (address(token) == address(debt1)) assertEq(liabilityAmounts[0], tokenAmount, "debt1 input tokenAmount not matching derived output amount");
        if (address(token) == address(debt2)) assertEq(liabilityAmounts[1], tokenAmount, "debt2 input tokenAmount not matching derived output amount");
    }

    function seedDeposit(address account, uint256 maxSupply) internal {
        uint256[] memory assetAmounts = new uint256[](2);
        (assetAmounts[0], assetAmounts[1]) = (SEED_ASSET1, SEED_ASSET2);

        uint256[] memory liabilityAmounts = new uint256[](2);
        (liabilityAmounts[0], liabilityAmounts[1]) = (SEED_LIABILITY1, SEED_LIABILITY2);

        vm.startPrank(account);
        asset1.deal(account, assetAmounts[0]);
        asset1.approve(address(vault), assetAmounts[0]);
        asset2.deal(account, assetAmounts[1]);
        asset2.approve(address(vault), assetAmounts[1]);
        vault.seed(assetAmounts, liabilityAmounts, SEED_SHARES, account, maxSupply);

        vm.stopPrank();
    }

    function joinWithToken(address user, address receiver, IERC20 token, uint256 tokenAmount) internal {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        _checkInputTokenAmount(token, tokenAmount, assets, liabilities);

        asset1.deal(user, assets[0]);
        asset2.deal(user, assets[1]);
        vm.startPrank(user);
        asset1.approve(address(vault), assets[0]);
        asset2.approve(address(vault), assets[1]);

        {
            (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
            uint256 expectedFeeAmout = sharesNoFees - shares;
            if (expectedFeeAmout > 0) {
                vm.expectEmit(address(vault));
                emit InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.JOIN_FEE, 
                    JOIN_FEE, 
                    expectedFeeAmout
                );
            }
        }

        vm.expectEmit(address(vault));
        emit Join(user, receiver, assets, liabilities, shares);
        (
            uint256 actualShares,
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.joinWithToken(address(token), tokenAmount, receiver);
        vm.stopPrank();

        assertEq(actualShares, shares);
        assertEq(actualAssets.length, assets.length);
        assertEq(actualAssets[0], assets[0]);
        assertEq(actualAssets[1], assets[1]);
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);

        _checkInputTokenAmount(token, tokenAmount, actualAssets, actualLiabilities);
    }

    function joinWithShares(address user, address receiver, uint256 shares) internal {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithShares(shares);
        asset1.deal(user, assets[0]);
        asset2.deal(user, assets[1]);
        vm.startPrank(user);
        asset1.approve(address(vault), assets[0]);
        asset2.approve(address(vault), assets[1]);
        
        {
            uint256 expectedFees = shares.inverseSubtractBps(JOIN_FEE, OrigamiMath.Rounding.ROUND_UP) - shares;
            if (expectedFees > 0) {
                vm.expectEmit(address(vault));
                emit InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.JOIN_FEE, 
                    JOIN_FEE, 
                    expectedFees
                );
            }
        }

        vm.expectEmit(address(vault));
        emit Join(user, receiver, assets, liabilities, shares);
        (
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.joinWithShares(shares, receiver);
        vm.stopPrank();

        assertEq(actualAssets.length, assets.length);
        assertEq(actualAssets[0], assets[0]);
        assertEq(actualAssets[1], assets[1]);
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);
    }

    function exitWithToken(address caller, address sharesOwner, address receiver, IERC20 token, uint256 tokenAmount) internal {
        (
            uint256 expectedShares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithToken(address(token), tokenAmount);

        _checkInputTokenAmount(token, tokenAmount, assets, liabilities);

        // Assume the caller already has the debt tokens to repay.
        vm.startPrank(caller);
        debt1.approve(address(vault), liabilities[0]);
        debt2.approve(address(vault), liabilities[1]);
        
        {
            (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
            uint256 expectedFeeAmout = sharesNoFees > expectedShares ? sharesNoFees - expectedShares : 0;
            if (expectedFeeAmout > 0) {
                vm.expectEmit(address(vault));
                emit InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.EXIT_FEE, 
                    EXIT_FEE,
                    expectedFeeAmout
                );
            }
        }

        vm.expectEmit(address(vault));
        emit Exit(caller, receiver, sharesOwner, assets, liabilities, expectedShares);
        (
            uint256 actualShares,
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithToken(address(token), tokenAmount, receiver, sharesOwner);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
        assertEq(actualAssets.length, assets.length);
        assertEq(actualAssets[0], assets[0]);
        assertEq(actualAssets[1], assets[1]);
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);

        _checkInputTokenAmount(token, tokenAmount, actualAssets, actualLiabilities);
    }

    function exitWithShares(address caller, address sharesOwner, address receiver, uint256 shares) internal {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithShares(shares);

        // Assume the caller already has the debt tokens to repay.
        vm.startPrank(caller);
        debt1.approve(address(vault), liabilities[0]);
        debt2.approve(address(vault), liabilities[1]);

        {
            (, uint256 expectedFeeAmout) = shares.splitSubtractBps(EXIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);
            if (expectedFeeAmout > 0) {
                vm.expectEmit(address(vault));
                emit InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.EXIT_FEE, 
                    EXIT_FEE,
                    expectedFeeAmout
                );
            }
        }

        vm.expectEmit(address(vault));
        emit Exit(caller, receiver, sharesOwner, assets, liabilities, shares);
        (
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithShares(shares, receiver, sharesOwner);
        vm.stopPrank();

        assertEq(actualAssets.length, assets.length);
        assertEq(actualAssets[0], assets[0]);
        assertEq(actualAssets[1], assets[1]);
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);
    }

    function checkConvertFromShares(uint256 shares, uint256 a1, uint256 a2, uint256 l1, uint256 l2) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = vault.convertFromShares(shares);
        assertEq(assets.length, 2, "convertFromShares::assets::length");
        assertEq(assets[0], a1, "convertFromShares::assets[0]");
        assertEq(assets[1], a2, "convertFromShares::assets[1]");
        assertEq(liabilities.length, 2, "convertFromShares::liabilities::length");
        assertEq(liabilities[0], l1, "convertFromShares::liabilities[0]");
        assertEq(liabilities[1], l2, "convertFromShares::liabilities[1]");
    }

    function checkBalanceSheet(uint256 a1, uint256 a2, uint256 l1, uint256 l2) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = vault.balanceSheet();
        assertEq(assets.length, 2, "balanceSheet::assets::length");
        assertEq(assets[0], a1, "balanceSheet::assets[0]");
        assertEq(assets[1], a2, "balanceSheet::assets[1]");
        assertEq(liabilities.length, 2, "balanceSheet::liabilities::length");
        assertEq(liabilities[0], l1, "balanceSheet::liabilities[0]");
        assertEq(liabilities[1], l2, "balanceSheet::liabilities[1]");
    }

    function checkConvertFromToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256 expectedAsset1,
        uint256 expectedAsset2,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.convertFromToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "convertFromToken::shares");
        assertEq(assets.length, 2, "convertFromToken::assets::length");
        assertEq(assets[0], expectedAsset1, "convertFromToken::assets[0]");
        assertEq(assets[1], expectedAsset2, "convertFromToken::assets[1]");
        assertEq(liabilities.length, 2, "convertFromToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "convertFromToken::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "convertFromToken::liabilities[1]");
    }

    function checkPreviewJoinWithShares(
        uint256 shares,
        uint256 expectedAsset1,
        uint256 expectedAsset2,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithShares(shares);

        assertEq(assets.length, 2, "previewJoinWithShares::assets::length");
        assertEq(assets[0], expectedAsset1, "previewJoinWithShares::assets[0]");
        assertEq(assets[1], expectedAsset2, "previewJoinWithShares::assets[1]");
        assertEq(liabilities.length, 2, "previewJoinWithShares::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewJoinWithShares::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewJoinWithShares::liabilities[1]");
    }

    function checkPreviewJoinWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256 expectedAsset1,
        uint256 expectedAsset2,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewJoinWithToken::shares");
        assertEq(assets.length, 2, "previewJoinWithToken::assets::length");
        assertEq(assets[0], expectedAsset1, "previewJoinWithToken::assets[0]");
        assertEq(assets[1], expectedAsset2, "previewJoinWithToken::assets[1]");
        assertEq(liabilities.length, 2, "previewJoinWithToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewJoinWithToken::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewJoinWithToken::liabilities[1]");
    }

    function checkPreviewExitWithShares(
        uint256 shares,
        uint256 expectedAsset1,
        uint256 expectedAsset2,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithShares(shares);

        assertEq(assets.length, 2, "previewExitWithShares::assets::length");
        assertEq(assets[0], expectedAsset1, "previewExitWithShares::assets[0]");
        assertEq(assets[1], expectedAsset2, "previewExitWithShares::assets[1]");
        assertEq(liabilities.length, 2, "previewExitWithShares::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewExitWithShares::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewExitWithShares::liabilities[1]");
    }

    function checkPreviewExitWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256 expectedAsset1,
        uint256 expectedAsset2,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewExitWithToken::shares");
        assertEq(assets.length, 2, "previewExitWithToken::assets::length");
        assertEq(assets[0], expectedAsset1, "previewExitWithToken::assets[0]");
        assertEq(assets[1], expectedAsset2, "previewExitWithToken::assets[1]");
        assertEq(liabilities.length, 2, "previewExitWithToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewExitWithToken::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewExitWithToken::liabilities[1]");
    }

    function increaseSharePrice(uint256 asset1Amount, uint256 asset2Amount, uint256 debt1Amount, uint256 debt2Amount) internal {
        uint256[] memory collaterals = new uint256[](2);
        (collaterals[0], collaterals[1]) = (asset1Amount, asset2Amount);

        uint256[] memory debts = new uint256[](2);
        (debts[0], debts[1]) = (debt1Amount, debt2Amount);

        borrowLend.addCollateralAndBorrow(collaterals, debts, origamiMultisig);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestAdminWithFees is VanillaOrigamiTokenizedBalanceSheetVaultTestBase {
    event MaxTotalSupplySet(uint256 maxTotalSupply);

    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "TokenizedBalanceSheet");
        assertEq(vault.symbol(), "TBSV");
        assertEq(vault.decimals(), 18);
        
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
        assertEq(vault.totalSupply(), SEED_SHARES); // No fees taken on the seed

        checkBalanceSheet(SEED_ASSET1, SEED_ASSET2, SEED_LIABILITY1, SEED_LIABILITY2);

        checkConvertFromToken(asset1, SEED_ASSET1*2, 200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromToken(asset2, SEED_ASSET2*2, 200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromToken(debt1, SEED_LIABILITY1*2, 200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromToken(debt2, SEED_LIABILITY2*2, 200e18, 2e18, 100e6, 4e18, 50e6);

        checkConvertFromShares(200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);

        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0x8e94348257374cb09c47bcff70260033661aa70e7bee9e4d426a32434a09d3ce));
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
    }

    function test_recoverToken_assetsAndLiablities() public {
        // The assets and liability tokens are recoverable since they are in the 3rd party borrow lend, not the vault
        asset1.deal(address(vault), 100e18);
        asset2.deal(address(vault), 100e6);
        debt1.deal(address(vault), 100e18);
        debt2.deal(address(vault), 100e6);

        vm.startPrank(origamiMultisig);
        vault.recoverToken(address(asset1), alice, 100e18);
        assertEq(asset1.balanceOf(alice), 100e18);
        vault.recoverToken(address(asset2), alice, 100e6);
        assertEq(asset2.balanceOf(alice), 100e6);
        vault.recoverToken(address(debt1), alice, 100e18);
        assertEq(debt1.balanceOf(alice), 100e18);
        vault.recoverToken(address(debt2), alice, 100e6);
        assertEq(debt2.balanceOf(alice), 100e6);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(vault));
    }

    function test_setMaxTotalSupply_failure_zeroSupply() public {
        address[] memory _assets = new address[](2);
        (_assets[0], _assets[1]) = (address(asset1), address(asset2));
        address[] memory _liabilities = new address[](2);
        (_liabilities[0], _liabilities[1]) = (address(debt1), address(debt2));

        vault = new MockTokenizedBalanceSheetVaultWithFees(
            origamiMultisig, 
            "TokenizedBalanceSheet",
            "TBSV",
            _assets,
            _liabilities,
            0,
            0,
            borrowLend
        );
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.setMaxTotalSupply(100e18);
    }

    function test_setMaxTotalSupply_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit MaxTotalSupplySet(123_456e18);
        vault.setMaxTotalSupply(123_456e18);
        assertEq(vault.maxTotalSupply(), 123_456e18);
    }

    function test_seed_failure_alreadySeeded() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        vault.seed(new uint256[](0), new uint256[](0), 0, alice, 0);
    }

    function test_seedDeposit_failure_maxTooLow() public {
        setUpWithNoFees();
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithShares.selector, origamiMultisig, 100e18+1, 100e18));
        vault.seed(new uint256[](2), new uint256[](2), 100e18+1, origamiMultisig, 100e18);
    }

    function test_seedDeposit_failure_badParams() public {
        setUpWithNoFees();
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.seed(new uint256[](0), new uint256[](2), 1e18, origamiMultisig, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.seed(new uint256[](2), new uint256[](0), 1e18, origamiMultisig, 100e18);
    }

    function test_seedDeposit_success() public {
        setUpWithNoFees();
        vm.startPrank(origamiMultisig);

        uint256[] memory assetAmounts = new uint256[](2);
        (assetAmounts[0], assetAmounts[1]) = (SEED_ASSET1, SEED_ASSET2);

        uint256[] memory liabilityAmounts = new uint256[](2);
        (liabilityAmounts[0], liabilityAmounts[1]) = (SEED_LIABILITY1, SEED_LIABILITY2);

        asset1.deal(origamiMultisig, assetAmounts[0]);
        asset1.approve(address(vault), assetAmounts[0]);
        asset2.deal(origamiMultisig, assetAmounts[1]);
        asset2.approve(address(vault), assetAmounts[1]);
        vm.expectEmit(address(vault));
        emit MaxTotalSupplySet(123e18);
        vm.expectEmit(address(vault));
        emit Join(origamiMultisig, alice, assetAmounts, liabilityAmounts, 69e18);
        vault.seed(assetAmounts, liabilityAmounts, 69e18, alice, 123e18);

        assertEq(vault.totalSupply(), 69e18);
        checkBalanceSheet(SEED_ASSET1, SEED_ASSET2, SEED_LIABILITY1, SEED_LIABILITY2);
        assertEq(vault.balanceOf(alice), 69e18);

        // What's the share price for each (how many tokens for each share)
        checkConvertFromShares(1e18, 0.014492753623188405e18, 0.724637e6, 0.028985507246376811e18, 0.362318e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestAccess is VanillaOrigamiTokenizedBalanceSheetVaultTestBase {
    function test_recoverToken_access() public {
        expectElevatedAccess();
        vault.recoverToken(alice, alice, 100e18);
    }

    function test_seed_access() public {
        expectElevatedAccess();
        vault.seed(new uint256[](0), new uint256[](0), 0, alice, 0);
    }

    function test_setMaxTotalSupply_access() public {
        expectElevatedAccess();
        vault.setMaxTotalSupply(123);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestAdminNoFees is VanillaOrigamiTokenizedBalanceSheetVaultTestBase {
    function setUp() public override {
        setUpWithNoFees();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
    }

    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "TokenizedBalanceSheet");
        assertEq(vault.symbol(), "TBSV");
        assertEq(vault.decimals(), 18);
        
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
        assertEq(vault.totalSupply(), SEED_SHARES); // No fees taken on the seed

        checkBalanceSheet(SEED_ASSET1, SEED_ASSET2, SEED_LIABILITY1, SEED_LIABILITY2);

        checkConvertFromToken(asset1, SEED_ASSET1*2, 200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromToken(asset2, SEED_ASSET2*2, 200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromToken(debt1, SEED_LIABILITY1*2, 200e18, 2e18, 100e6, 4e18, 50e6);
        checkConvertFromToken(debt2, SEED_LIABILITY2*2, 200e18, 2e18, 100e6, 4e18, 50e6);

        checkConvertFromShares(200e18, 2e18, 100e6, 4e18, 50e6);

        assertEq(vault.joinFeeBps(), 0);
        assertEq(vault.exitFeeBps(), 0);

        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0x8e94348257374cb09c47bcff70260033661aa70e7bee9e4d426a32434a09d3ce));
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
    }
}
contract OrigamiTokenizedBalanceSheetVaultTestViewsNoFees is VanillaOrigamiTokenizedBalanceSheetVaultTestBase {
    function setUp() public override {
        setUpWithNoFees();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
    }
    
    function test_maxJoin() public view {
        assertEq(vault.maxJoinWithShares(alice), type(uint256).max); // 100 already minted in seed

        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxJoinWithToken(address(asset1), alice), type(uint256).max);
        assertEq(vault.maxJoinWithToken(address(asset2), alice), type(uint256).max);
        assertEq(vault.maxJoinWithToken(address(debt1), alice), type(uint256).max);
        assertEq(vault.maxJoinWithToken(address(debt2), alice), type(uint256).max);
    }

    function test_maxExit() public view {
        assertEq(vault.maxExitWithShares(alice), 0);
        assertEq(vault.maxExitWithShares(address(0)), type(uint256).max);
        assertEq(vault.maxExitWithShares(origamiMultisig), SEED_SHARES);

        assertEq(vault.maxExitWithToken(address(asset1), alice), 0);
        assertEq(vault.maxExitWithToken(address(asset2), alice), 0);
        assertEq(vault.maxExitWithToken(address(debt1), alice), 0);
        assertEq(vault.maxExitWithToken(address(debt2), alice), 0);
        assertEq(vault.maxExitWithToken(address(asset1), address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(address(asset2), address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(address(debt1), address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(address(debt2), address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(address(asset1), origamiMultisig), 1e18);
        assertEq(vault.maxExitWithToken(address(asset2), origamiMultisig), 50e6);
        assertEq(vault.maxExitWithToken(address(debt1), origamiMultisig), 2e18);
        assertEq(vault.maxExitWithToken(address(debt2), origamiMultisig), 25e6);
    }

    function test_previewJoin() public view {
        checkPreviewJoinWithShares(100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(asset1, 1e18, 100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(asset2, 50e6, 100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 100e18, 1e18, 50e6, 2e18, 25e6);
    }

    function test_previewExit() public view {
        checkPreviewExitWithShares(100e18, 1e18, 50e6, 2e18, 25e6);

        checkPreviewExitWithToken(asset1, 1e18, 100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewExitWithToken(asset2, 50e6, 100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewExitWithToken(debt1, 2e18, 100e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 100e18, 1e18, 50e6, 2e18, 25e6);
    }

    function test_noFees() public {
        setUpWithNoFees();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
        
        joinWithToken(alice, alice, asset1, 123e18);
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        checkBalanceSheet(
            123e18 + SEED_ASSET1, 
            6_150e6 + SEED_ASSET2, 
            246e18 + SEED_LIABILITY1, 
            3_075e6 + SEED_LIABILITY2
        );

        exitWithToken(alice, alice, alice, asset1, 61.5e18);
        checkBalanceSheet(
            123e18 - 61.5e18 + SEED_ASSET1, 
            6_150e6 - 3_075e6 + SEED_ASSET2, 
            246e18 - 123e18 + SEED_LIABILITY1, 
            3_075e6 - 1_537.5e6 + SEED_LIABILITY2
        );
        assertEq(vault.totalSupply(), 12_300e18 - 6_150e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 6_150e18);
        assertEq(asset1.balanceOf(alice), 61.5e18);
        assertEq(asset2.balanceOf(alice), 3_075e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 123e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_537.5e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestJoinWithToken is VanillaOrigamiTokenizedBalanceSheetVaultTestBase { 

    function test_joinWithToken_overflows_on_weird_tokens_that_perform_maxBalance_transfer_on_uint256Max() public {
        asset1.deal(alice, 100_000_000_000e18);
        asset2.deal(alice, 100_000_000_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000_000_000e18);
        asset2.approve(address(vault), 100_000_000_000e6);

        uint256 tokens = vault.maxJoinWithToken(address(asset1), alice);
        assertEq(tokens, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(PRBMath_MulDiv_Overflow.selector, type(uint256).max, 1e20, 1e18));
        vault.joinWithToken(address(asset1), tokens, alice);
    }

    function test_joinWithToken_badTokenAddress_cappedTotalSupply() public {
        DummyMintableTokenPermissionless donationAsset = new DummyMintableTokenPermissionless("DONATION", "DONATION", 18);
        donationAsset.deal(address(borrowLend), 1_000_000e18);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(0), 123e18, 0));
        vault.joinWithToken(address(0), 123e18, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(123), 123e18, 0));
        vault.joinWithToken(address(123), 123e18, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(donationAsset), 123e18, 0));
        vault.joinWithToken(address(donationAsset), 123e18, alice);
    }

    function test_joinWithToken_badTokenAddress_unlimitedTotalSupply() public {
        DummyMintableTokenPermissionless donationAsset = new DummyMintableTokenPermissionless("DONATION", "DONATION", 18);
        donationAsset.deal(address(borrowLend), 1_000_000e18);

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(0), 123e18, 0));
        vault.joinWithToken(address(0), 123e18, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(123), 123e18, 0));
        vault.joinWithToken(address(123), 123e18, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(donationAsset), 123e18, 0));
        vault.joinWithToken(address(donationAsset), 123e18, alice);
    }

    function test_joinWithToken_badReceiver() public {
        asset1.deal(alice, 100_000_000_000e18);
        asset2.deal(alice, 100_000_000_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000_000_000e18);
        asset2.approve(address(vault), 100_000_000_000e6);

        vm.startPrank(alice);
        vm.expectRevert("ERC20: mint to the zero address");
        vault.joinWithToken(address(asset1), 123e18, address(0));
    }

    function test_joinWithToken_basic_asset1() public {
        joinWithToken(alice, alice, asset1, 123e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_differentReceiver() public {
        joinWithToken(alice, bob, asset1, 123e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        assertEq(vault.balanceOf(bob), 12_300e18);
        assertEq(asset1.balanceOf(bob), 0);
        assertEq(asset2.balanceOf(bob), 0);
        assertEq(debt1.balanceOf(bob), 246e18);
        assertEq(debt2.balanceOf(bob), 3_075e6);
    }

    function test_joinWithToken_basic_asset2() public {
        joinWithToken(alice, alice, asset2, 6_150e6);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_basic_debt1() public {
        joinWithToken(alice, alice, debt1, 246e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_basic_debt2() public {
        joinWithToken(alice, alice, debt2, 3_075e6);
        checkBalanceSheet(
            123e18 + SEED_ASSET1, 
            6_150e6 + SEED_ASSET2, 
            246e18 + SEED_LIABILITY1, 
            3_075e6 + SEED_LIABILITY2
        );
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_multiple() public {
        joinWithToken(alice, alice, asset1, 61.5e18); // half of asset1 from the `test_joinWithToken_basic_debt2` test
        joinWithToken(alice, alice, debt2, 1_537.5e6); // half of debt2 from the `test_joinWithToken_basic_debt2` test
        checkBalanceSheet(
            123e18 + SEED_ASSET1, 
            6_150e6 + SEED_ASSET2, 
            246e18 + SEED_LIABILITY1, 
            3_075e6 + SEED_LIABILITY2
        );

        // Less shares are minted to Alice -- this is expected because the first join increases
        // the share price, prior to the second join being executed.
        // It's benefifical for users to do large joins upfront rather than stagger them - TRUE only for Vault with Fees (check test with same name in OTBSV file)

        uint256 expectedSharesMinted = 6150e18 + 6150e18;
        assertEq(expectedSharesMinted, 12300e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_zeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.joinWithToken(address(asset1), 0, alice);
    }

    struct ExpValues {
    uint256 A1;
    uint256 A2;
    uint256 L1;
    uint256 L2;
    }

    function test_joinWithToken_beforeShareIncrease_asset() public {
        ExpValues memory expBefore = ExpValues({
            A1: 0.01e18,
            A2: 0.5e6,
            L1: 0.02e18,
            L2: 0.25e6
        });

        ExpValues memory expAfter = ExpValues({
            A1: 0.018064516129032258e18,
            A2: 0.508064e6,
            L1: 0.02e18,
            L2: 0.266129e6
        });

        joinWithToken(alice, alice, asset1, 123e18);

        checkConvertFromShares(1e18, expBefore.A1, expBefore.A2, expBefore.L1, expBefore.L2);

        (uint256[] memory totalAssetsBefore, uint256[] memory totalLiabilitiesBefore) = vault.balanceSheet();

        increaseSharePrice(100e18, 100e6, 0, 200e6);

        (uint256[] memory totalAssetsAfter, uint256[] memory totalLiabilitiesAfter) = vault.balanceSheet();

        checkConvertFromShares(1e18, expAfter.A1, expAfter.A2, expAfter.L1, expAfter.L2);

        uint256[] memory totalPercentageIncrease = new uint256[](4);
        totalPercentageIncrease[0] = (((totalAssetsAfter[0] - totalAssetsBefore[0]) * 1e18) / totalAssetsBefore[0]) * 100;
        totalPercentageIncrease[1] = (((totalAssetsAfter[1] - totalAssetsBefore[1]) * 1e18) / totalAssetsBefore[1]) * 100;
        totalPercentageIncrease[2] = (((totalLiabilitiesAfter[0] - totalLiabilitiesBefore[0]) * 1e18) / totalLiabilitiesBefore[0]) * 100;
        totalPercentageIncrease[3] = (((totalLiabilitiesAfter[1] - totalLiabilitiesBefore[1]) * 1e18) / totalLiabilitiesBefore[1]) * 100;

        uint256[] memory vaultPercentageIncrease = new uint256[](4);
        vaultPercentageIncrease[0] = (((expAfter.A1 - expBefore.A1) * 1e18) / expBefore.A1) * 100;
        vaultPercentageIncrease[1] = (((expAfter.A2 - expBefore.A2) * 1e18) / expBefore.A2) * 100;
        vaultPercentageIncrease[2] = (((expAfter.L1 - expBefore.L1) * 1e18) / expBefore.L1) * 100;
        vaultPercentageIncrease[3] = (((expAfter.L2 - expBefore.L2) * 1e18) / expBefore.L2) * 100;

        assertEq(vaultPercentageIncrease[0], 80645161290322580000); // 80.65%
        assertEq(vaultPercentageIncrease[1], 1612800000000000000);  // 1.61%
        assertEq(vaultPercentageIncrease[2], 0);
        assertEq(vaultPercentageIncrease[3], 6451600000000000000);  // 6.45%

        for (uint256 i = 0; i < 4; i++) {
            assertApproxEqAbs(totalPercentageIncrease[i], vaultPercentageIncrease[i], 0.001e18);
        }

        checkBalanceSheet(123e18 + 100e18 + SEED_ASSET1, 6_150e6 + 100e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + 200e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }


    function test_joinWithToken_afterShareIncrease() public {
        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 1.01e18, 1.500000e6, 0.02e18, 2.250000e6);

        joinWithToken(alice, alice, asset1, 123e18);
        checkBalanceSheet(123e18 + 100e18 + SEED_ASSET1, 182.673268e6 + 100e6 + SEED_ASSET2, 2.435643564356435643e18 + SEED_LIABILITY1, 274.009900e6 + 200e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 121.173267326732673267e18 + SEED_SHARES + 608910891089108911);//more ts because of no fees, compared to the test with same name from OTBSV file.
        assertEq(vault.balanceOf(alice),  121.173267326732673267e18 + 608910891089108911);//more shares for Alice because of no fees
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 2.435643564356435643e18);
        assertEq(debt2.balanceOf(alice), 274.009900e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestJoinWithShares is VanillaOrigamiTokenizedBalanceSheetVaultTestBase { 
    function test_joinWithShares_unlimited_shares_capacity() public {
        asset1.deal(alice, 100_000_000_000e18);
        asset2.deal(alice, 100_000_000_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000_000_000e18);
        asset2.approve(address(vault), 100_000_000_000e6);

        uint256 shares = vault.maxJoinWithShares(alice);
        assertEq(shares, type(uint256).max);
        vault.joinWithShares(10_000_000e18, alice);
    }

    function test_joinWithShares_exactlyOneShare() public {
        joinWithShares(alice, alice, 1e18);
        checkBalanceSheet(SEED_ASSET1 + 0.01e18, SEED_ASSET2 + 0.5e6, SEED_LIABILITY1 + 0.02e18, SEED_LIABILITY2 + 0.25e6);
        assertEq(vault.totalSupply(), 1e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 1e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 0.02e18);
        assertEq(debt2.balanceOf(alice), 0.25e6);
    }

    function test_joinWithShares_partialShare() public {
        // Share price of each is less than one
        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);

        joinWithShares(alice, alice, 0.9e18);
        checkBalanceSheet(SEED_ASSET1 + 0.009e18, SEED_ASSET2 + 0.450000e6, SEED_LIABILITY1 + 0.018e18, SEED_LIABILITY2 + 0.225e6);
        assertEq(vault.totalSupply(), 0.9e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 0.9e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 0.018e18);
        assertEq(debt2.balanceOf(alice), 0.225000e6);
    }

    function test_joinWithShares_basic() public {
        joinWithShares(alice, alice, 12_238.5e18);
        checkBalanceSheet(122.385e18 + SEED_ASSET1, 6119.25e6 + SEED_ASSET2, 244.77e18 + SEED_LIABILITY1, 3059.625e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 244.77e18);
        assertEq(debt2.balanceOf(alice), 3059.625e6);
    }

    function test_joinWithShares_differentReceiver() public {
        joinWithShares(alice, bob, 12_238.5e18);
        checkBalanceSheet(122.385e18 + SEED_ASSET1, 6_119.25e6 + SEED_ASSET2, 244.77e18 + SEED_LIABILITY1, 3059.625e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(bob), 12_238.5e18);
        assertEq(asset1.balanceOf(bob), 0);
        assertEq(asset2.balanceOf(bob), 0);
        assertEq(debt1.balanceOf(bob), 244.77e18);
        assertEq(debt2.balanceOf(bob), 3059.625e6);
    }

    function test_joinWithShares_badReceiver() public {
        asset1.deal(alice, 100_000_000_000e18);
        asset2.deal(alice, 100_000_000_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000_000_000e18);
        asset2.approve(address(vault), 100_000_000_000e6);

        vm.startPrank(alice);
        vm.expectRevert("ERC20: mint to the zero address");
        vault.joinWithShares(123e18, address(0));
    }

    function test_joinWithShares_multiple() public {
        joinWithShares(alice, alice, 12_238.5e18);
        joinWithShares(alice, alice, 12_238.5e18);
        checkBalanceSheet(
            122.385e18 + 122.385e18 + SEED_ASSET1,//less a1 in vault compared to fee variant, check with the same test name in OTBSV file
            6119.25e6 + 6119.25e6 + SEED_ASSET2,//less a2 in vault compared to fee variant, check with the same test name in OTBSV file
            244.77e18 + 244.77e18 + SEED_LIABILITY1,//less l1 in vault compared to fee variant
            3059.625e6 + 3059.625e6 + SEED_LIABILITY2//less l2 
        );
        assertEq(vault.totalSupply(), 12_238.5e18*2 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18*2);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 244.77e18 + 244.77e18);
        assertEq(debt2.balanceOf(alice), 3059.625e6 + 3059.625e6);
    }

    function test_joinWithShares_zeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.joinWithShares(0, alice);
    }

    function test_joinWithShares_beforeShareIncrease_asset() public {
        joinWithShares(alice, alice, 12_238.5e18);

        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018104712890545852e18, 0.508104e6, 0.02e18, 0.266209e6);
        //NOTE: this is slightly wrong since these increases won't be applied directly, but sufficient for now ;).
        checkBalanceSheet(122.385e18 + 100e18 + SEED_ASSET1, 6119.25e6 + 100e6 + SEED_ASSET2, 244.77e18 + SEED_LIABILITY1, 3059.625e6 + 200e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 244.77e18);
        assertEq(debt2.balanceOf(alice), 3059.625e6);
    }

    function test_joinWithShares_afterShareIncrease() public {
        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkBalanceSheet(
            100e18 + SEED_ASSET1,
            100e6 + SEED_ASSET2,
            0 + SEED_LIABILITY1,
            200e6 + SEED_LIABILITY2
        );
        checkConvertFromShares(1e18, 1.01e18, 1.500000e6, 0.02e18, 2.250000e6);

        joinWithShares(alice, alice, 12_238.5e18);
        checkBalanceSheet(
            12_360.885e18 + 100e18 + SEED_ASSET1,
            18_357.75e6 + 100e6 + SEED_ASSET2,
            244.77e18 + 0 + SEED_LIABILITY1,
            27_536.625e6 + 200e6 + SEED_LIABILITY2
        );
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 244.77e18);
        assertEq(debt2.balanceOf(alice), 27_536.625e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestExitWithToken is VanillaOrigamiTokenizedBalanceSheetVaultTestBase { 

    function test_exitWithToken_basic_asset1() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset1, 50e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1, 3_075e6 - 1_250e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_differentReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, bob, asset1, 50e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1, 3_075e6 - 1_250e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);

        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset1.balanceOf(bob), 50e18);
        assertEq(asset2.balanceOf(bob), 2_500e6);
        assertEq(debt1.balanceOf(bob), 0);
        assertEq(debt2.balanceOf(bob), 0);
    }

    function test_exitWithToken_badReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.exitWithToken(address(asset1), 1e18, address(0), alice);
    }

    function test_exitWithToken_onBehalfOf() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        vault.approve(bob, 50e18);
        assertEq(vault.allowance(alice, bob), 50e18);

        vm.startPrank(origamiMultisig);
        vm.expectRevert("ERC20: insufficient allowance");
        vault.exitWithToken(address(asset1), 1e18, origamiMultisig, alice);

        vm.startPrank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        vault.exitWithToken(address(asset1), 1e18, origamiMultisig, alice);

        vm.startPrank(alice);
        vault.approve(bob, 500e18);

        debt1.deal(bob, 1_000_000e18);
        debt2.deal(bob, 1_000_000e6);
        exitWithToken(bob, alice, bob, asset1, 1e18);
        assertEq(vault.allowance(alice, bob), 400e18);

        vm.startPrank(alice);
        vault.approve(bob, type(uint256).max);
        exitWithToken(bob, alice, bob, asset1, 0.1e18);
        assertEq(vault.allowance(alice, bob), type(uint256).max);

        {
            checkBalanceSheet(
                123e18 - 1e18 - 0.1e18 + SEED_ASSET1,
                6_145e6,
                245.8e18,
                3_072.5e6
            );

            assertEq(vault.totalSupply(), 12_290e18);
            assertEq(vault.balanceOf(alice), 12_290e18 - SEED_SHARES);
            assertEq(asset1.balanceOf(alice), 0);
            assertEq(asset2.balanceOf(alice), 0);
            assertEq(debt1.balanceOf(alice), 246e18);
            assertEq(debt2.balanceOf(alice), 3_075e6);

            assertEq(vault.balanceOf(bob), 0);
            assertEq(asset1.balanceOf(bob), 1.1e18);
            assertEq(asset2.balanceOf(bob), 55e6);
            assertEq(debt1.balanceOf(bob), 1_000_000e18 - 2.2e18);
            assertEq(debt2.balanceOf(bob), 1_000_000e6 - 27.5e6);
        }
    }

    function test_exitWithToken_basic_asset2() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset2, 2_500e6);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1, 3_075e6 - 1_250e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5000e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_basic_debt1() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, debt1, 100e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1, 3_075e6 - 1_250e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 - 5000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5000e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 );
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_basic_debt2() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, debt2, 1_250e6);
        checkBalanceSheet(
            123e18 - 50e18 + SEED_ASSET1,
            6_150e6 - 2_500e6 + SEED_ASSET2,
            246e18 - 100e18 + SEED_LIABILITY1,
            3_075e6 - 1_250e6 + SEED_LIABILITY2
        );

        uint256 expectedSharesBurned = 5_000e18;
        assertEq(vault.totalSupply(), 12_300e18 - expectedSharesBurned + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - expectedSharesBurned);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_multiple() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset2, 1_250e6); // half of the asset2 from the `test_exitWithToken_basic_debt2` test
        exitWithToken(alice, alice, alice, debt2, 625e6);    // half of the debt2 from the `test_exitWithToken_basic_debt2` test
        checkBalanceSheet(
            123e18 - 50e18 + SEED_ASSET1,
            6_150e6 - 2_500e6 + SEED_ASSET2, 
            246e18 - 100e18 + SEED_LIABILITY1, 
            3_075e6 - 1_250e6 + SEED_LIABILITY2
        );

        // Less shares are burned from Alice -- this is expected because the first exit increases
        // the share price, prior to the second exit being executed.
        // It's benefifical for users to stagger exits - note not true for no-fee vault
        uint256 expectedSharesBurned = 2_500e18 + 2_500e18;
        assertEq(expectedSharesBurned, 5_000e18);
        assertEq(vault.totalSupply(), 12_300e18 - expectedSharesBurned + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - expectedSharesBurned);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_zeroAmount() public {
        joinWithToken(alice, alice, asset1, 123e18);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.exitWithToken(address(asset1), 0, alice, alice);
    }

    function test_exitWithToken_beforeShareIncrease_asset() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, debt2, 1_250e6);

        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.023513513513513513e18, 0.513513e6, 0.02e18, 0.277027e6);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18,
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6,
            246e18 + SEED_LIABILITY1 - 100e18,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6
        );
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_afterShareIncrease() public {
        joinWithToken(alice, alice, asset1, 123e18);

        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018064516129032258e18, 0.508064e6, 0.02e18, 0.266129e6);

        exitWithToken(alice, alice, alice, debt2, 1_250e6);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18 - 34.848484848484848484e18,
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6 + 113.636364e6,
            246e18 + SEED_LIABILITY1 - 100e18 + 6.060606060606060606e18,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6
        );
        assertEq(vault.totalSupply(), 12_300e18 - 4_696.969696969696969696e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 4_696.969696969696969696e18);
        assertEq(asset1.balanceOf(alice), 84.848484848484848484e18);
        assertEq(asset2.balanceOf(alice), 2_386.363636e6);
        assertEq(debt1.balanceOf(alice), 152.060606060606060606e18);
        assertEq(debt2.balanceOf(alice), 1_825e6);
    }

    function test_exitWithShares_fromExitWithTokenQuote() public {
        joinWithToken(alice, alice, asset1, 123e18);
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithToken(address(asset2), 2_500e6);
        assertEq(shares, 5000e18);
        assertEq(assets[0], 50e18);
        assertEq(assets[1], 2_500e6);
        assertEq(liabilities[0], 100e18);
        assertEq(liabilities[1], 1_250e6);

        // Assume the user already has the debt tokens to repay.
        vm.startPrank(alice);
        debt1.approve(address(vault), liabilities[0]);
        debt2.approve(address(vault), liabilities[1]);

        (
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithShares(shares, alice, alice);

        assertEq(actualAssets.length, assets.length);
        assertEq(actualAssets[0], assets[0]);
        assertEq(actualAssets[1], assets[1]);
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);

        checkBalanceSheet(123e18 - assets[0] + SEED_ASSET1, 6_150e6 - assets[1] + SEED_ASSET2, 246e18 - liabilities[0] + SEED_LIABILITY1, 3_075e6 - liabilities[1] + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18);
        assertEq(asset1.balanceOf(alice), assets[0]);
        assertEq(asset2.balanceOf(alice), assets[1]);
        assertEq(debt1.balanceOf(alice), 246e18 - liabilities[0]);
        assertEq(debt2.balanceOf(alice), 3_075e6 - liabilities[1]);
    }

    function test_exitWithToken_fromExitWithSharesQuote() public {
        joinWithToken(alice, alice, asset1, 123e18);
        
        uint256 sharesToExit = 5_076.736339697169190258e18;
        // Get a preview to exit the exact number of shares 
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithShares(sharesToExit);
        assertEq(assets[0], 50.767363396971691902e18); // Assets returned round down - CORRECT
        assertEq(assets[1], 2538.368169e6);
        assertEq(liabilities[0], 101.534726793943383806e18); // Liabilities required round up
        assertEq(liabilities[1], 1269.184085e6);

        // Going the other way with that number of liabilities (which was rounded up by one)
        // Gives a different result to previewExitWithShares(), due to rounding in favour of the vault.
        (
            uint256 previewShares,
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewExitWithToken(address(debt2), liabilities[1]);
        assertEq(previewShares, 5076.736340000000000000e18);
        assertEq(previewAssets[0], 50.767363400000000000e18);
        assertEq(previewAssets[1], 2538.368170e6);
        assertEq(previewLiabilities[0], 101.534726800000000000e18);
        assertEq(previewLiabilities[1], 1269.184085e6);

        // But doing the same with 1 less liabilities does yield the same result. note: this is not the case anymore in no fee vault
        (
            previewShares,
            previewAssets,
            previewLiabilities
        ) = vault.previewExitWithToken(address(debt2), liabilities[1] - 1);
        //note: no rounding here
        assertEq(previewShares, 5076.736336000000000000e18);
        assertEq(previewAssets[0], 50.767363360000000000e18);
        assertEq(previewAssets[1], assets[1] - 1);
        assertEq(previewLiabilities[0], 101.53472672e18);//exact 1:50 ratio shares:liab0
        assertEq(previewLiabilities[1], liabilities[1] - 1);//exact 1:25 ratio shares:liab (dismiss the decimals)

        // Assume the user already has the debt tokens to repay.
        vm.startPrank(alice);
        debt1.approve(address(vault), liabilities[0]);
        debt2.approve(address(vault), liabilities[1]);

        (
            uint256 actualShares,
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithToken(address(debt2), liabilities[1] - 1, alice, alice);

        checkBalanceSheet(123e18 - previewAssets[0] + SEED_ASSET1, 6_150e6 - previewAssets[1] + SEED_ASSET2, 246e18 - previewLiabilities[0] + SEED_LIABILITY1, 3_075e6 - previewLiabilities[1] + SEED_LIABILITY2);
        assertEq(actualShares, sharesToExit - 3697169190258);
        assertEq(vault.totalSupply(), 12_300e18 - sharesToExit + SEED_SHARES + 3697169190258);
        assertEq(vault.balanceOf(alice), 12_300e18 - sharesToExit + 3697169190258);
        assertEq(asset1.balanceOf(alice), 50.767363360000000000e18);
        assertEq(asset2.balanceOf(alice), assets[1] - 1);
        assertEq(debt1.balanceOf(alice), 246e18 - 101.53472672e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - liabilities[1] + 1);
        assertEq(previewAssets[0], actualAssets[0]);
        assertEq(previewAssets[1], actualAssets[1]);
        assertEq(previewLiabilities[0], actualLiabilities[0]);
        assertEq(previewLiabilities[1], actualLiabilities[1]);
    }

    function test_exitWithShares_fullUnwind() public {
        joinWithShares(alice, alice, 100e18);

        exitWithShares(origamiMultisig, origamiMultisig, origamiMultisig, vault.balanceOf(origamiMultisig));
        assertEq(vault.balanceOf(origamiMultisig), 0);
        assertEq(vault.balanceOf(alice), 100e18);
        assertEq(vault.totalSupply(), 100e18);
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);

        exitWithShares(alice, alice, alice, 100e18);
        assertEq(vault.balanceOf(origamiMultisig), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);

        // Gets reset to zero such that a seed is required again.
        assertEq(vault.maxTotalSupply(), 0);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestExitWithShares is VanillaOrigamiTokenizedBalanceSheetVaultTestBase { 

    function test_exitWithShares_basic() public {
        joinWithToken(alice, alice, asset1, 123e18);//6150 l1 6200 in total
        exitWithShares(alice, alice, alice, 5_076.736339697169190258e18);
        //a1 = 123e18 + SEED_ASSET1 - 50.76736339697169190258e18 (+1 at the end, proper rounding)
        //a2 = 6_150e6 - 2538.368169848584595129e6 + SEED_ASSET2 (+1 at the end, proper rounding)
        //l1 = 246e18 - 101.534726793943383805e18 + SEED_LIABILITY - 1 
        //l2 = 3_075e6 - 1269.184084e6 + SEED_LIABILITY2 - 1
        checkBalanceSheet(73.232636603028308098e18, 3661.631831e6, 146.465273206056616194e18, 1830.815915e6);
        assertEq(vault.totalSupply(), 12_300e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50767363396971691902);
        assertEq(asset2.balanceOf(alice), 2538368169);
        assertEq(debt1.balanceOf(alice), 246e18 - 101.534726793943383805e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1269.184084e6 - 1);
    }

    function test_exitWithShares_differentReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, bob, 5_076.736339697169190258e18);
        //a1 = 123e18 + SEED_ASSET1 - 50.76736339697169190258e18 (+1 at the end, proper rounding)
        //a2 = 6_150e6 - 2538.368169848584595129e6 + SEED_ASSET2 (+1 at the end, proper rounding)
        //l1 = 246e18 - 101.534726793943383805e18 + SEED_LIABILITY - 1 
        //l2 = 3_075e6 - 1269.184084e6 + SEED_LIABILITY2 - 1
        checkBalanceSheet(73.232636603028308098e18, 3661.631831e6, 146.465273206056616194e18, 1830.815915e6);
        assertEq(vault.totalSupply(), 12_300e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 - 101.534726793943383806e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1269.184085e6);

        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset1.balanceOf(bob), 50767363396971691902);
        assertEq(asset2.balanceOf(bob), 2538368169);
        assertEq(debt1.balanceOf(bob), 0);
        assertEq(debt2.balanceOf(bob), 0);
    }

    function test_exitWithShares_badReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.exitWithShares(1e18, address(0), alice);
    }

    function test_exitWithShares_onBehalfOf() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        vault.approve(bob, 50e18);
        assertEq(vault.allowance(alice, bob), 50e18);

        vm.startPrank(origamiMultisig);
        vm.expectRevert("ERC20: insufficient allowance");
        vault.exitWithShares(50e18 + 1, origamiMultisig, alice);
        
        debt1.deal(bob, 1_000_000e18);
        debt2.deal(bob, 1_000_000e6);
        vm.startPrank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        vault.exitWithShares(50e18 + 1, origamiMultisig, alice);

        exitWithShares(bob, alice, bob, 10e18);
        assertEq(vault.allowance(alice, bob), 40e18);

        vm.startPrank(alice);
        vault.approve(bob, type(uint256).max);
        exitWithShares(bob, alice, bob, 50e18);

        {
            checkBalanceSheet(
                123e18 - 0.10e18 - 0.50e18 + SEED_ASSET1,
                6_150e6 - 5e6 - 25e6 + SEED_ASSET2,
                246e18 - 0.2e18 - 1e18 + SEED_LIABILITY1,
                3_075e6 - 2.5e6 - 12.5e6 + SEED_LIABILITY2
            );

            assertEq(vault.totalSupply(), 12_300e18 - 10e18 - 50e18 + SEED_SHARES);
            assertEq(vault.balanceOf(alice), 12_300e18 - 10e18 - 50e18);
            assertEq(asset1.balanceOf(alice), 0);
            assertEq(asset2.balanceOf(alice), 0);
            assertEq(debt1.balanceOf(alice), 246e18);
            assertEq(debt2.balanceOf(alice), 3_075e6);

            assertEq(vault.balanceOf(bob), 0);
            assertEq(asset1.balanceOf(bob), 0.1e18 + 0.5e18);
            assertEq(asset2.balanceOf(bob), 5e6 + 25e6);
            assertEq(debt1.balanceOf(bob), 1_000_000e18 - (0.2e18 + 1e18));
            assertEq(debt2.balanceOf(bob), 1_000_000e6 - (2.5e6 + 12.5e6));
        }
    }

    function test_exitWithShares_multiple() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, alice, 2_538.368169848584595129e18); // half of the shares from the `test_exitWithShares_basic` test
        exitWithShares(alice, alice, alice, 2_538.368169848584595129e18); // and again
        // The multiple exits burn more fees than the single one.
        //a1 = 123e18 - 25.383681698485845951e18 - 25.383681698485845951e18 + SEED_ASSET1
        //a2 = 6_150e6 - 1269.184084e6 - 1269.184085e6 + SEED_ASSET2
        //l1 = 246e18 - 50.767363396971691903e18 - 50.767363396971691903e18 + SEED_LIABILITY1
        //l2 = 3_075e6 - 634.592043e6 - 634.592043e6 + SEED_LIABILITY2
        checkBalanceSheet(
            73.232636603028308098e18,
            3661.631831e6,//note: this rounds in favor of the user in the second exit?
            146.465273206056616194e18, 
            1830.815914e6
        );

        uint256 expectedSharesBurned = 2_538.368169848584595129e18 * 2;
        assertEq(vault.totalSupply(), 12_300e18 - expectedSharesBurned + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - expectedSharesBurned);
        assertEq(asset1.balanceOf(alice), 25.383681698485845951e18 + 25.383681698485845951e18);
        assertEq(asset2.balanceOf(alice), 1269.184084e6 + 1269.184085e6);//note: then here he receives 1 wei more
        assertEq(debt1.balanceOf(alice), 246e18 - 50.767363396971691903e18 - 50.767363396971691903e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 634.592043e6 - 634.592043e6);
    }

    function test_exitWithShares_zeroAmount() public {
        joinWithToken(alice, alice, asset1, 123e18);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.exitWithShares(0, alice, alice);
    }

    function test_exitWithShares_beforeShareIncrease_asset() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, alice, 5_076.736339697169190258e18);

        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.019999999999999999e18, 0.249999e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.023655113981771456e18, 0.513655e6, 0.019999999999999999e18, 0.277310e6);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18 - 0.767363396971691902e18,//take fees
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6 - 38.36817e6 + 1, 
            246e18 + SEED_LIABILITY1 - 100e18 - 1 - 1.534726793943383805e18,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6 - 1 - 19.184084e6
        );
        assertEq(vault.totalSupply(), 12_300e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18 + 0.767363396971691902e18);
        assertEq(asset2.balanceOf(alice), 2_500e6 + 38.36817e6 - 1);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1 - 1.534726793943383805e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1 - 19.184084e6);
    }

    function test_exitWithShares_afterShareIncrease() public {
        joinWithToken(alice, alice, asset1, 123e18);

        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018064516129032258e18, 0.508064e6, 0.02e18, 0.266129e6);

        exitWithShares(alice, alice, alice, 5_076.736339697169190258e18);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18 - 40.322580645161290322e18 - 1.386204846142411179e18, //subtract the fee that should have been collected
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6 - 40.322580e6 - 38.987011e6,
            246e18 + SEED_LIABILITY1 - 100e18 - 1 - 1.534726793943383805e18,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6 - 80.645162e6 - 20.421768e6
        );
        assertEq(vault.totalSupply(), 12_300e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18 + 40.322580645161290322e18 + 1.386204846142411179e18); //add the fee
        assertEq(asset2.balanceOf(alice), 2_500e6 + 40.322580e6 + 38.987011e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1 - 1.534726793943383805e18);//subtract the fee
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 80.645162e6 - 20.421768e6);
    }

    function test_roundTrip_checkAssetRounding() public {
        increaseSharePrice(495032, 1359, 15, 4294967293);

        uint256[] memory ratiosBefore = new uint256[](4);

        {
            (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = vault.balanceSheet();
            uint256 totalSupply = vault.totalSupply();

            ratiosBefore[0] = totalAssets[0] * 1e18 / totalSupply;
            ratiosBefore[1] = totalAssets[1] * 1e18 / totalSupply;
            ratiosBefore[2] = totalLiabilities[0] * 1e18 / totalSupply;
            ratiosBefore[3] = totalLiabilities[1] * 1e18 / totalSupply;
        }
        
        address token = address(debt2);
        uint256 tokenAmount = 4809252306;

        (, uint256[] memory assets,) = vault.previewJoinWithToken(address(token), tokenAmount);

        asset1.deal(bob, assets[0]);
        asset2.deal(bob, assets[1]);
        vm.startPrank(bob);
        asset1.approve(address(vault), assets[0]);
        asset2.approve(address(vault), assets[1]);

        (
            uint256 actualSharesJoin,
            uint256[] memory actualAssetsJoin,
            uint256[] memory actualLiabilitiesJoin
        ) = vault.joinWithToken(address(token), tokenAmount, bob);
        vm.stopPrank();

        uint256[] memory liabilitiesExit;
        uint256 actualSharesExit;
        uint256[] memory actualAssetsExit;
        {
            tokenAmount = actualLiabilitiesJoin[1] - 1;
            (,,liabilitiesExit) = vault.previewExitWithToken(address(token), tokenAmount);

            vm.startPrank(bob);
            debt1.approve(address(vault), liabilitiesExit[0]);
            debt2.approve(address(vault), liabilitiesExit[1]);
            (
                actualSharesExit,
                actualAssetsExit,
            ) = vault.exitWithToken(address(token), tokenAmount, bob, bob);
            vm.stopPrank();
        }

        {
            (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = vault.balanceSheet();
            uint256 totalSupply = vault.totalSupply();

            // Ratios remain untouched
            assertEq((totalAssets[0] * 1e18 / totalSupply), ratiosBefore[0]);
            assertEq((totalAssets[1] * 1e18 / totalSupply), ratiosBefore[1]);
            assertEq((totalLiabilities[0] * 1e18 / totalSupply), ratiosBefore[2]);
            assertEq((totalLiabilities[1] * 1e18 / totalSupply), ratiosBefore[3]);

            // Shares on exit get rounded down - so should be ever so slightly less than the shares from the join
            assertApproxEqAbs(actualSharesExit, actualSharesJoin, 0.0000001e18);
            assertLe(actualSharesExit, actualSharesJoin);

            // Dust from rounding of the debt may be left
            assertApproxEqAbs(debt1.balanceOf(bob), 0, 0.0000001e18);
            assertApproxEqAbs(debt2.balanceOf(bob), 0, 0.0000001e18);
            
            assertGe(actualAssetsJoin[0], actualAssetsExit[0]);
            assertApproxEqAbs(actualAssetsJoin[0], actualAssetsExit[0], 0.0000001e18);
            assertGe(actualAssetsJoin[1], actualAssetsExit[1]);
            assertApproxEqAbs(actualAssetsJoin[1], actualAssetsExit[1], 0.0000001e18);
        }
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestPermit is VanillaOrigamiTokenizedBalanceSheetVaultTestBase {
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function buildDomainSeparator() internal view returns (bytes32) {
        bytes32 _hashedName = keccak256(bytes(vault.name()));
        bytes32 _hashedVersion = keccak256(bytes("1"));
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(vault)));
    }

    function signedPermit(
        address signer, 
        uint256 signerPk, 
        address spender, 
        uint256 amount, 
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = buildDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, signer, spender, amount, vault.nonces(signer), deadline));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        return vm.sign(signerPk, typedDataHash);
    }

    function test_permit() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");
        address spender = makeAddr("spender");
        uint256 amount = 123;

        assertEq(vault.nonces(signer), 0);
        uint256 allowanceBefore = vault.allowance(signer, spender);

        // Check for expired deadlines
        uint256 deadline = block.timestamp-1;
        (uint8 v, bytes32 r, bytes32 s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vm.expectRevert("ERC20Permit: expired deadline");

        vault.permit(signer, spender, amount, deadline, v, r, s);

        // Permit successfully increments the allowance
        deadline = block.timestamp + 3600;
        (v, r, s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vault.permit(signer, spender, amount, deadline, v, r, s);
        assertEq(vault.allowance(signer, spender), allowanceBefore+amount);
        assertEq(vault.nonces(signer), 1);

        // Can't re-use the same signature for another permit (the nonce was incremented)
        vm.expectRevert("ERC20Permit: invalid signature");

        vault.permit(signer, spender, amount, deadline, v, r, s);
    }
}
