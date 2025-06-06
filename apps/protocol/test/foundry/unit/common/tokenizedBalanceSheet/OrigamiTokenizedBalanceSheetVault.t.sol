pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { MockTokenizedBalanceSheetVaultWithFees } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockTokenizedBalanceSheetVaultWithFees.m.sol";
import { OrigamiTokenizedBalanceSheetVaultCommon } from "test/foundry/unit/common/tokenizedBalanceSheet/OrigamiTokenizedBalanceSheetVaultCommon.t.sol";
import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";

contract OrigamiTokenizedBalanceSheetVaultTestBase is OrigamiTokenizedBalanceSheetVaultCommon {
    using OrigamiMath for uint256;

    function setUp() public virtual {
        setUpWithFees(JOIN_FEE, EXIT_FEE);
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

    function joinWithToken(address user, address receiver, IERC20 token, uint256 tokenAmount) internal {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        // Check that the input token amount matches the result
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

        // Check that the input token amount matches the result
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

        // Check that the input token amount matches the result
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

        // Check that the input token amount matches the result
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
        asset1.deal(address(this), asset1Amount);
        asset1.approve(address(borrowLend), asset1Amount);
        asset2.deal(address(this), asset2Amount);
        asset2.approve(address(borrowLend), asset2Amount);

        uint256[] memory collaterals = new uint256[](2);
        (collaterals[0], collaterals[1]) = (asset1Amount, asset2Amount);

        uint256[] memory debts = new uint256[](2);
        (debts[0], debts[1]) = (debt1Amount, debt2Amount);

        borrowLend.addCollateralAndBorrow(collaterals, debts, origamiMultisig);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestAdminWithFees is OrigamiTokenizedBalanceSheetVaultTestBase {
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

        assertEq(vault.joinFeeBps(), JOIN_FEE);
        assertEq(vault.exitFeeBps(), EXIT_FEE);

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
        setUpWithFees(JOIN_FEE, EXIT_FEE);
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithShares.selector, origamiMultisig, 100e18+1, 100e18));
        vault.seed(new uint256[](2), new uint256[](2), 100e18+1, origamiMultisig, 100e18);
    }

    function test_seedDeposit_failure_badParams() public {
        setUpWithFees(JOIN_FEE, EXIT_FEE);
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.seed(new uint256[](0), new uint256[](2), 1e18, origamiMultisig, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.seed(new uint256[](2), new uint256[](0), 1e18, origamiMultisig, 100e18);
    }

    function test_seedDeposit_success() public {
        setUpWithFees(JOIN_FEE, EXIT_FEE);
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

contract OrigamiTokenizedBalanceSheetVaultTestAccess is OrigamiTokenizedBalanceSheetVaultTestBase {
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

contract OrigamiTokenizedBalanceSheetVaultTestAdminNoFees is OrigamiTokenizedBalanceSheetVaultTestBase {
    function setUp() public override {
        setUpWithFees(0, 0);
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

contract OrigamiTokenizedBalanceSheetVaultTestViewsWithFees is OrigamiTokenizedBalanceSheetVaultTestBase {
    function test_supportsInterface() public view {
        assertEq(vault.supportsInterface(type(IOrigamiTokenizedBalanceSheetVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(ITokenizedBalanceSheetVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(vault.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(vault.supportsInterface(type(IOrigamiInvestment).interfaceId), false);
        assertEq(vault.supportsInterface(type(IERC4626).interfaceId), false);
    }

    function test_tokens() public view {
        (address[] memory assetTokens, address[] memory liabilityTokens) = vault.tokens();
        assertEq(assetTokens.length, 2);
        assertEq(assetTokens[0], address(asset1));
        assertEq(assetTokens[1], address(asset2));
        assertEq(liabilityTokens.length, 2);
        assertEq(liabilityTokens[0], address(debt1));
        assertEq(liabilityTokens[1], address(debt2));
    }

    function test_assetTokens() public view {
        address[] memory assetTokens = vault.assetTokens();
        assertEq(assetTokens.length, 2);
        assertEq(assetTokens[0], address(asset1));
        assertEq(assetTokens[1], address(asset2));
    }

    function test_liabilityTokens() public view {
        address[] memory liabilityTokens = vault.liabilityTokens();
        assertEq(liabilityTokens.length, 2);
        assertEq(liabilityTokens[0], address(debt1));
        assertEq(liabilityTokens[1], address(debt2));
    }

    function test_isBalanceSheetToken() public view {
        (bool isAsset, bool isLiability) = vault.isBalanceSheetToken(address(asset1));
        assertEq(isAsset, true);
        assertEq(isLiability, false);
        (isAsset, isLiability) = vault.isBalanceSheetToken(address(asset2));
        assertEq(isAsset, true);
        assertEq(isLiability, false);
        (isAsset, isLiability) = vault.isBalanceSheetToken(address(debt1));
        assertEq(isAsset, false);
        assertEq(isLiability, true);
        (isAsset, isLiability) = vault.isBalanceSheetToken(address(debt2));
        assertEq(isAsset, false);
        assertEq(isLiability, true);
        (isAsset, isLiability) = vault.isBalanceSheetToken(alice);
        assertEq(isAsset, false);
        assertEq(isLiability, false);
    }

    function test_maxJoin() public {
        assertEq(vault.maxJoinWithShares(alice), 99_999_900e18); // 100 already minted in seed

        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxJoinWithToken(address(asset1), alice), 1_005_024.120603015075376884e18);
        assertEq(vault.maxJoinWithToken(address(asset2), alice), 50_251_206.030150e6);
        assertEq(vault.maxJoinWithToken(address(debt1), alice), 2_010_048.241206030150753768e18);
        assertEq(vault.maxJoinWithToken(address(debt2), alice), 25_125_603.015075e6);

        // Under the max join with shares
        (uint256 shares,,) = vault.previewJoinWithToken(address(asset1), 1_005_024.120603015075376884e18);
        assertEq(shares, 99_999_899.999999999999999958e18);
        (shares,,) = vault.previewJoinWithToken(address(asset2), 50_251_206.030150e6);
        assertEq(shares, 99_999_899.999998500000000000e18);
        (shares,,) = vault.previewJoinWithToken(address(debt1), 2_010_048.241206030150753768e18);
        assertEq(shares, 99_999_899.999999999999999958e18);
        (shares,,) = vault.previewJoinWithToken(address(debt2), 25_125_603.015075e6);
        assertEq(shares, 99_999_899.999998500000000000e18);
        
        assertEq(vault.maxJoinWithToken(address(0), alice), 0);
        assertEq(vault.maxJoinWithToken(address(123), alice), 0);

        vault.setPaused(true, false);
        assertEq(vault.maxJoinWithToken(address(asset1), address(0)), 0);
        assertEq(vault.maxJoinWithShares(address(0)), 0);
    }

    function test_maxExit() public {
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
        assertEq(vault.maxExitWithToken(address(asset1), origamiMultisig), 0.98e18);
        assertEq(vault.maxExitWithToken(address(asset2), origamiMultisig), 49e6);
        assertEq(vault.maxExitWithToken(address(debt1), origamiMultisig), 1.96e18);
        assertEq(vault.maxExitWithToken(address(debt2), origamiMultisig), 24.5e6);

        // Under the max exit with shares
        (uint256 shares,,) = vault.previewExitWithToken(address(asset1), 0.98e18);
        assertEq(shares, SEED_SHARES);
        (shares,,) = vault.previewExitWithToken(address(asset2), 49e6);
        assertEq(shares, SEED_SHARES);
        (shares,,) = vault.previewExitWithToken(address(debt1), 1.96e18);
        assertEq(shares, SEED_SHARES);
        (shares,,) = vault.previewExitWithToken(address(debt2), 24.5e6);
        assertEq(shares, SEED_SHARES);

        assertEq(vault.maxExitWithToken(address(0), origamiMultisig), 0);
        assertEq(vault.maxExitWithToken(address(123), origamiMultisig), 0);

        vault.setPaused(false, true);
        assertEq(vault.maxExitWithToken(address(asset1), address(0)), 0);
        assertEq(vault.maxExitWithShares(address(0)), 0);
    }

    function test_previewJoin() public view {
        checkPreviewJoinWithShares(0, 0, 0, 0, 0);
        checkPreviewJoinWithShares(100e18, 1.005025125628140704e18, 50.251257e6, 2.010050251256281407e18, 25.125628e6);

        checkPreviewJoinWithToken(asset1, 1e18, 99.5e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(asset2, 50e6, 99.5e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 99.5e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 99.5e18, 1e18, 50e6, 2e18, 25e6);

        checkPreviewJoinWithToken(debt2, 0, 0, 0, 0, 0, 0);
        checkPreviewJoinWithToken(IERC20(address(0)), 1e18, 0, 0, 0, 0, 0);
        checkPreviewJoinWithToken(IERC20(address(0)), 1e18, 0, 0, 0, 0, 0);
    }

    function test_previewExit() public view {
        checkPreviewExitWithShares(0, 0, 0, 0, 0);
        checkPreviewExitWithShares(100e18, 0.98e18, 49e6, 1.96e18, 24.5e6);

        checkPreviewExitWithToken(asset1, 1e18, 102.040816326530612245e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewExitWithToken(asset2, 50e6, 102.040816326530612245e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewExitWithToken(debt1, 2e18, 102.040816326530612245e18, 1e18, 50e6, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 102.040816326530612245e18, 1e18, 50e6, 2e18, 25e6);

        checkPreviewExitWithToken(debt2, 0, 0, 0, 0, 0, 0);
        checkPreviewExitWithToken(IERC20(address(0)), 1e18, 0, 0, 0, 0, 0);
        checkPreviewExitWithToken(IERC20(address(0)), 1e18, 0, 0, 0, 0, 0);
    }

    function test_availableSharesCapacity() public {
        assertEq(vault.availableSharesCapacity(), MAX_TOTAL_SUPPLY-SEED_SHARES);

        vm.startPrank(origamiMultisig);
        vault.setMaxTotalSupply(0.01e18);
        assertEq(vault.totalSupply(), SEED_SHARES);
        assertEq(vault.maxTotalSupply(), 0.01e18);
        assertEq(vault.availableSharesCapacity(), 0);

        vault.setMaxTotalSupply(type(uint256).max);
        assertEq(vault.availableSharesCapacity(), type(uint256).max);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestViewsNoFees is OrigamiTokenizedBalanceSheetVaultTestBase {
    function setUp() public override {
        setUpWithFees(0, 0);
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
    }
    
    function test_maxJoin() public view {
        assertEq(vault.maxJoinWithShares(alice), 99_999_900e18); // 100 already minted in seed

        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxJoinWithToken(address(asset1), alice), 999_999e18);
        assertEq(vault.maxJoinWithToken(address(asset2), alice), 49_999_950e6);
        assertEq(vault.maxJoinWithToken(address(debt1), alice), 1_999_998e18);
        assertEq(vault.maxJoinWithToken(address(debt2), alice), 24_999_975e6);
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
        setUpWithFees(0, 0);
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

contract OrigamiTokenizedBalanceSheetVaultTestJoinWithToken is OrigamiTokenizedBalanceSheetVaultTestBase { 
    function test_join_fail_paused() public {
        assertEq(vault.maxJoinWithToken(address(asset1), alice), 1_005_024.120603015075376884e18);
        vault.setPaused(true, false);
        assertEq(vault.maxJoinWithToken(address(asset1), alice), 0);

        vm.startPrank(alice);
        asset1.deal(alice, 100_000e18);
        asset2.deal(alice, 100_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000e18);
        asset2.approve(address(vault), 100_000e6);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(asset1), 10e18, 0));
        vault.joinWithToken(address(asset1), 10e18, alice);
    }
    
    function test_exit_fail_paused() public {
        joinWithToken(alice, alice, asset1, 100e18);
        assertEq(vault.maxExitWithToken(address(asset1), alice), 97.995124378109452736e18);

        vault.setPaused(false, true);
        assertEq(vault.maxExitWithToken(address(asset1), address(0)), 0);

        asset1.deal(alice, 100_000e18);
        asset2.deal(alice, 100_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000e18);
        asset2.approve(address(vault), 100_000e6);
        vault.joinWithToken(address(asset1), 10e18, alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(asset1), 1e18, 0));
        vault.exitWithToken(address(asset1), 1e18, alice, alice);
    }

    function test_joinWithToken_fail_tooMuch() public {
        asset1.deal(alice, 100_000_000_000e18);
        asset2.deal(alice, 100_000_000_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000_000_000e18);
        asset2.approve(address(vault), 100_000_000_000e6);

        uint256 tokens = vault.maxJoinWithToken(address(asset1), alice)+1;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(asset1), tokens, tokens-1));
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

        vm.prank(origamiMultisig);
        vault.setMaxTotalSupply(type(uint256).max);

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
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_differentReceiver() public {
        joinWithToken(alice, bob, asset1, 123e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(bob), 12_238.5e18);
        assertEq(asset1.balanceOf(bob), 0);
        assertEq(asset2.balanceOf(bob), 0);
        assertEq(debt1.balanceOf(bob), 246e18);
        assertEq(debt2.balanceOf(bob), 3_075e6);
    }

    function test_joinWithToken_basic_asset2() public {
        joinWithToken(alice, alice, asset2, 6_150e6);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithToken_basic_debt1() public {
        joinWithToken(alice, alice, debt1, 246e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
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
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
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
        // It's benefifical for users to do large joins upfront rather than stagger them
        uint256 expectedSharesMinted = 6_119.25e18 + 6_089.14329e18;
        assertEq(expectedSharesMinted, 12_208.39329e18);

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

    function test_joinWithToken_noAssetLeft() public {
        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(asset1)),
            abi.encode(0)
        );
        checkBalanceSheet(0, SEED_ASSET2, SEED_LIABILITY1, SEED_LIABILITY2);

        checkPreviewJoinWithToken(asset1, 1e18, 0, 0, 0, 0, 0);
        checkPreviewJoinWithToken(asset2, 50e6, 99.5e18, 0, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 99.5e18, 0, 50e6, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 99.5e18, 0, 50e6, 2e18, 25e6);

        assertEq(vault.maxJoinWithToken(address(asset1), alice), 0);
        assertEq(vault.maxJoinWithToken(address(asset2), alice), 50_251_206.030150e6);
        assertEq(vault.maxJoinWithToken(address(debt1), alice), 2_010_048.241206030150753768e18);
        assertEq(vault.maxJoinWithToken(address(debt2), alice), 25_125_603.015075e6);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(asset1), 1e18, 0));
        vault.joinWithToken(address(asset1), 1e18, alice);
    }

    function test_joinWithToken_noLiabilitiesLeft() public {
        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(debt2)),
            abi.encode(0)
        );
        checkBalanceSheet(SEED_ASSET1, SEED_ASSET2, SEED_LIABILITY1, 0);

        checkPreviewJoinWithToken(asset1, 1e18, 99.5e18, 1e18, 50e6, 2e18, 0);
        checkPreviewJoinWithToken(asset2, 50e6, 99.5e18, 1e18, 50e6, 2e18, 0);
        checkPreviewJoinWithToken(debt1, 2e18, 99.5e18, 1e18, 50e6, 2e18, 0);
        checkPreviewJoinWithToken(debt2, 25e6, 0, 0, 0, 0, 0);

        assertEq(vault.maxJoinWithToken(address(asset1), alice), 1_005_024.120603015075376884e18);
        assertEq(vault.maxJoinWithToken(address(asset2), alice), 50_251_206.030150e6);
        assertEq(vault.maxJoinWithToken(address(debt1), alice), 2_010_048.241206030150753768e18);
        assertEq(vault.maxJoinWithToken(address(debt2), alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(debt2), 25e6, 0));
        vault.joinWithToken(address(debt2), 25e6, alice);
    }

    function test_joinWithToken_beforeShareIncrease_asset() public {
        joinWithToken(alice, alice, asset1, 123e18);

        checkConvertFromShares(1e18, 0.010049843984276856e18, 0.502492e6, 0.020099687968553713e18, 0.251246e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018154556874822709e18, 0.510596e6, 0.020099687968553713e18, 0.267455e6);

        checkBalanceSheet(123e18 + 100e18 + SEED_ASSET1, 6_150e6 + 100e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + 200e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
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
        assertEq(vault.totalSupply(), 121.173267326732673267e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 121.173267326732673267e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 2.435643564356435643e18);
        assertEq(debt2.balanceOf(alice), 274.009900e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestJoinWithShares is OrigamiTokenizedBalanceSheetVaultTestBase { 
    function test_joinWithShares_fail_tooMuch() public {
        asset1.deal(alice, 100_000_000_000e18);
        asset2.deal(alice, 100_000_000_000e6);
        vm.startPrank(alice);
        asset1.approve(address(vault), 100_000_000_000e18);
        asset2.approve(address(vault), 100_000_000_000e6);

        uint256 shares = vault.maxJoinWithShares(alice)+1;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithShares.selector, alice, MAX_TOTAL_SUPPLY - SEED_SHARES + 1, MAX_TOTAL_SUPPLY - SEED_SHARES));
        vault.joinWithShares(shares, alice);
    }

    function test_joinWithShares_exactlyOneShare() public {
        joinWithShares(alice, alice, 1e18);
        checkBalanceSheet(SEED_ASSET1 + 0.010050251256281408e18, SEED_ASSET2 + 0.502513e6, SEED_LIABILITY1 + 0.020100502512562814e18, SEED_LIABILITY2 + 0.251256e6);
        assertEq(vault.totalSupply(), 1e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 1e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 0.020100502512562814e18);
        assertEq(debt2.balanceOf(alice), 0.251256e6);
    }

    function test_joinWithShares_partialShare() public {
        // Share price of each is less than one
        checkConvertFromShares(1e18, 0.01e18, 0.5e6, 0.02e18, 0.25e6);

        joinWithShares(alice, alice, 0.9e18);
        checkBalanceSheet(SEED_ASSET1 + 0.009045226130653267e18, SEED_ASSET2 + 0.452262e6, SEED_LIABILITY1 + 0.018090452261306532e18, SEED_LIABILITY2 + 0.226130e6);
        assertEq(vault.totalSupply(), 0.9e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 0.9e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 0.018090452261306532e18);
        assertEq(debt2.balanceOf(alice), 0.226130e6);
    }

    function test_joinWithShares_basic() public {
        joinWithShares(alice, alice, 12_238.5e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
    }

    function test_joinWithShares_differentReceiver() public {
        joinWithShares(alice, bob, 12_238.5e18);
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(bob), 12_238.5e18);
        assertEq(asset1.balanceOf(bob), 0);
        assertEq(asset2.balanceOf(bob), 0);
        assertEq(debt1.balanceOf(bob), 246e18);
        assertEq(debt2.balanceOf(bob), 3_075e6);
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
            123.613081006605341006e18 + 123e18 + SEED_ASSET1,
            6_180.654051e6 + 6_150e6 + SEED_ASSET2,
            247.226162013210682011e18 + 246e18 + SEED_LIABILITY1,
            3_090.327025e6 + 3_075e6 + SEED_LIABILITY2
        );
        assertEq(vault.totalSupply(), 12_238.5e18*2 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18*2);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 247.226162013210682011e18 + 246e18);
        assertEq(debt2.balanceOf(alice), 3_090.327025e6 + 3_075e6);
    }

    function test_joinWithShares_zeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.joinWithShares(0, alice);
    }

    function test_joinWithShares_noAssetLeft() public {
        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(asset1)),
            abi.encode(0)
        );
        checkBalanceSheet(0, SEED_ASSET2, SEED_LIABILITY1, SEED_LIABILITY2);

        checkPreviewJoinWithShares(100e18, 0, 50.251257e6, 2.010050251256281407e18, 25.125628e6);
        assertEq(vault.maxJoinWithShares(alice), 99_999_900e18); // 100 already minted in seed

        joinWithShares(alice, alice, 100e18);
        checkBalanceSheet(0, SEED_ASSET2+50.251257e6, SEED_LIABILITY1+2.010050251256281407e18, SEED_LIABILITY2+25.125628e6);
    }

    function test_joinWithShares_noLiabilitiesLeft() public {
        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(debt2)),
            abi.encode(0)
        );
        checkBalanceSheet(SEED_ASSET1, SEED_ASSET2, SEED_LIABILITY1, 0);

        checkPreviewJoinWithShares(100e18, 1.005025125628140704e18, 50.251257e6, 2.010050251256281407e18, 0);
        assertEq(vault.maxJoinWithShares(alice), 99_999_900e18); // 100 already minted in seed

        joinWithShares(alice, alice, 100e18);
        checkBalanceSheet(SEED_ASSET1+1.005025125628140704e18, SEED_ASSET2+50.251257e6, SEED_LIABILITY1+2.010050251256281407e18, 0);
    }

    function test_joinWithShares_beforeShareIncrease_asset() public {
        joinWithShares(alice, alice, 12_238.5e18);

        checkConvertFromShares(1e18, 0.010049843984276856e18, 0.502492e6, 0.020099687968553713e18, 0.251246e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018154556874822709e18, 0.510596e6, 0.020099687968553713e18, 0.267455e6);

        checkBalanceSheet(123e18 + 100e18 + SEED_ASSET1, 6_150e6 + 100e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + 200e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);
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
            12_423e18 + 100e18 + SEED_ASSET1,
            18_450e6 + 100e6 + SEED_ASSET2,
            246e18 + 0 + SEED_LIABILITY1,
            27_675e6 + 200e6 + SEED_LIABILITY2
        );
        assertEq(vault.totalSupply(), 12_238.5e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 27_675e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestExitWithToken is OrigamiTokenizedBalanceSheetVaultTestBase { 
    function test_exitWithToken_fail_exitTooMuch() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        asset1.approve(address(vault), asset1.balanceOf(alice));
        asset2.approve(address(vault), asset2.balanceOf(alice));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(asset1), 123e18, 120.535115289540868014e18));
        vault.exitWithToken(address(asset1), 123e18, alice, alice);
    }

    function test_exitWithToken_badTokenAddress_cappedTotalSupply() public {
        joinWithToken(alice, alice, asset1, 123e18);

        DummyMintableTokenPermissionless donationAsset = new DummyMintableTokenPermissionless("DONATION", "DONATION", 18);
        donationAsset.deal(address(borrowLend), 1_000_000e18);
        
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(0), 123e18, 0));
        vault.exitWithToken(address(0), 123e18, alice, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(123), 123e18, 0));
        vault.exitWithToken(address(123), 123e18, alice, alice);
        
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(donationAsset), 123e18, 0));
        vault.exitWithToken(address(donationAsset), 123e18, alice, alice);
    }

    function test_exitWithToken_badTokenAddress_unlimitedTotalSupply() public {
        vm.prank(origamiMultisig);
        vault.setMaxTotalSupply(type(uint256).max);

        DummyMintableTokenPermissionless donationAsset = new DummyMintableTokenPermissionless("DONATION", "DONATION", 18);
        donationAsset.deal(address(borrowLend), 1_000_000e18);
        
        joinWithToken(alice, alice, asset1, 123e18);
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(0), 123e18, 0));
        vault.exitWithToken(address(0), 123e18, alice, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(123), 123e18, 0));
        vault.exitWithToken(address(123), 123e18, alice, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(donationAsset), 123e18, 0));
        vault.exitWithToken(address(donationAsset), 123e18, alice, alice);
    }

    function test_exitWithToken_basic_asset1() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset1, 50e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1 - 1, 3_075e6 - 1_250e6 + SEED_LIABILITY2 - 1);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);
    }

    function test_exitWithToken_differentReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, bob, asset1, 50e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1 - 1, 3_075e6 - 1_250e6 + SEED_LIABILITY2 - 1);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);

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

    function test_exitWithToken_zeroSharesOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.exitWithToken(address(asset1), 1e18, alice, address(0));
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
        assertEq(vault.allowance(alice, bob), 398.465273206056616193e18);

        vm.startPrank(alice);
        vault.approve(bob, type(uint256).max);
        exitWithToken(bob, alice, bob, asset1, 0.1e18);
        assertEq(vault.allowance(alice, bob), type(uint256).max);

        {
            checkBalanceSheet(
                123e18 - 1e18 - 0.1e18 + SEED_ASSET1,
                6_145e6,
                245.8e18 - 2,
                3_072.5e6 - 1
            );

            assertEq(vault.totalSupply(), 12_226.813485191118789233e18);
            assertEq(vault.balanceOf(alice), 12_226.813485191118789233e18 - SEED_SHARES);
            assertEq(asset1.balanceOf(alice), 0);
            assertEq(asset2.balanceOf(alice), 0);
            assertEq(debt1.balanceOf(alice), 246e18);
            assertEq(debt2.balanceOf(alice), 3_075e6);

            assertEq(vault.balanceOf(bob), 0);
            assertEq(asset1.balanceOf(bob), 1.1e18);
            assertEq(asset2.balanceOf(bob), 55e6);
            assertEq(debt1.balanceOf(bob), 1_000_000e18 - 2.2e18 - 2);
            assertEq(debt2.balanceOf(bob), 1_000_000e6 - 27.5e6 - 1);
        }
    }

    function test_exitWithToken_basic_asset2() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset2, 2_500e6);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1 - 1, 3_075e6 - 1_250e6 + SEED_LIABILITY2 - 1);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);
    }

    function test_exitWithToken_basic_debt1() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, debt1, 100e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1 + 1, 6_150e6 - 2_500e6 + SEED_ASSET2 + 1, 246e18 - 100e18 + SEED_LIABILITY1, 3_075e6 - 1_250e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190257e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190257e18);
        assertEq(asset1.balanceOf(alice), 50e18 - 1);
        assertEq(asset2.balanceOf(alice), 2_500e6 - 1);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_basic_debt2() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, debt2, 1_250e6);
        checkBalanceSheet(
            123e18 - 50e18 + SEED_ASSET1 + 1,
            6_150e6 - 2_500e6 + SEED_ASSET2 + 1,
            246e18 - 100e18 + SEED_LIABILITY1,
            3_075e6 - 1_250e6 + SEED_LIABILITY2
        );

        uint256 expectedSharesBurned = 5_076.736339697169190257e18;
        assertEq(vault.totalSupply(), 12_238.5e18 - expectedSharesBurned + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - expectedSharesBurned);
        assertEq(asset1.balanceOf(alice), 50e18 - 1);
        assertEq(asset2.balanceOf(alice), 2_500e6 - 1);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_multiple() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset2, 1_250e6); // half of the asset2 from the `test_exitWithToken_basic_debt2` test
        exitWithToken(alice, alice, alice, debt2, 625e6);    // half of the debt2 from the `test_exitWithToken_basic_debt2` test
        // Some expected rounding diffs when exiting twice with different tokens vs doing in one hit
        checkBalanceSheet(
            123e18 - 50e18 + SEED_ASSET1 - 10101010105,
            6_150e6 - 2_500e6 + SEED_ASSET2, 
            246e18 - 100e18 + SEED_LIABILITY1 - 20202020211, 
            3_075e6 - 1_250e6 + SEED_LIABILITY2 - 1
        );

        // Less shares are burned from Alice -- this is expected because the first exit increases
        // the share price, prior to the second exit being executed.
        // It's benefifical for users to stagger exits
        uint256 expectedSharesBurned = 2_538.368169848584595129e18 + 2_525.286496111900801581e18;
        assertEq(expectedSharesBurned, 5_063.654665960485396710e18);
        assertEq(vault.totalSupply(), 12_238.5e18 - expectedSharesBurned + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - expectedSharesBurned);
        assertEq(asset1.balanceOf(alice), 50e18 + 10101010105);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 20202020211);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);
    }

    function test_exitWithToken_zeroAmount() public {
        joinWithToken(alice, alice, asset1, 123e18);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.exitWithToken(address(asset1), 0, alice, alice);
    }

    function test_exitWithToken_noAssetLeft() public {
        joinWithToken(alice, alice, asset1, 123e18);

        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(asset1)),
            abi.encode(0)
        );
        checkBalanceSheet(0, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);

        checkPreviewExitWithToken(asset1, 1e18, 0, 0, 0, 0, 0);
        checkPreviewExitWithToken(asset2, 50e6, 101.534726793943383807e18, 0, 50e6, 2e18+1, 25e6+1);
        checkPreviewExitWithToken(debt1, 2e18, 101.534726793943383806e18, 0, 50e6-1, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 101.534726793943383806e18, 0, 50e6-1, 2e18, 25e6);

        assertEq(vault.maxExitWithToken(address(asset1), alice), 0);
        assertEq(vault.maxExitWithToken(address(asset2), alice), 6_026.755764e6);
        assertEq(vault.maxExitWithToken(address(debt1), alice), 241.070230579081736029e18);
        assertEq(vault.maxExitWithToken(address(debt2), alice), 3_013.377882e6);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(asset1), 1e18, 0));
        vault.exitWithToken(address(asset1), 1e18, alice, alice);
    }

    function test_exitWithToken_noLiabilitiesLeft() public {
        joinWithToken(alice, alice, asset1, 123e18);

        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(debt2)),
            abi.encode(0)
        );
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 0);

        checkPreviewExitWithToken(asset1, 1e18, 101.534726793943383807e18, 1e18, 50e6, 2e18 + 1, 0);
        checkPreviewExitWithToken(asset2, 50e6, 101.534726793943383807e18, 1e18, 50e6, 2e18 + 1, 0);
        checkPreviewExitWithToken(debt1, 2e18, 101.534726793943383806e18, 1e18 - 1, 50e6 - 1, 2e18, 0);
        checkPreviewExitWithToken(debt2, 25e6, 0, 0, 0, 0, 0);

        assertEq(vault.maxExitWithToken(address(asset1), alice), 120.535115289540868014e18);
        assertEq(vault.maxExitWithToken(address(asset2), alice), 6_026.755764e6);
        assertEq(vault.maxExitWithToken(address(debt1), alice), 241.070230579081736029e18);
        assertEq(vault.maxExitWithToken(address(debt2), alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(debt2), 25e6, 0));
        vault.exitWithToken(address(debt2), 25e6, alice, alice);
    }

    function test_exitWithToken_beforeShareIncrease_asset() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, debt2, 1_250e6);

        checkConvertFromShares(1e18, 0.010190361937077148e18, 0.509518e6, 0.020380723874154297e18, 0.254759e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.023961121311505727e18, 0.523288e6, 0.020380723874154297e18, 0.282300e6);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18 + 1,
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6 + 1,
            246e18 + SEED_LIABILITY1 - 100e18,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6
        );
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190257e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190257e18);
        assertEq(asset1.balanceOf(alice), 50e18 - 1);
        assertEq(asset2.balanceOf(alice), 2_500e6 - 1);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);
    }

    function test_exitWithToken_afterShareIncrease() public {
        joinWithToken(alice, alice, asset1, 123e18);

        checkConvertFromShares(1e18, 0.010049843984276856e18, 0.502492e6, 0.020099687968553713e18, 0.251246e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018154556874822709e18, 0.510596e6, 0.020099687968553713e18, 0.267455e6);

        exitWithToken(alice, alice, alice, debt2, 1_250e6);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18 - 34.848484848484848484e18,
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6 + 113.636364e6,
            246e18 + SEED_LIABILITY1 - 100e18 + 6.060606060606060606e18,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6
        );
        assertEq(vault.totalSupply(), 12_238.5e18 - 4_769.055349412492269635e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 4_769.055349412492269635e18);
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
        assertEq(shares, 5_076.736339697169190258e18);
        assertEq(assets[0], 50e18);
        assertEq(assets[1], 2_500e6);
        assertEq(liabilities[0], 100e18 + 1);
        assertEq(liabilities[1], 1_250e6 + 1);

        // Assume the user already has the debt tokens to repay.
        uint256 liabilities0Exit = liabilities[0];
        uint256 liabilities1Exit = liabilities[1];
        vm.startPrank(alice);
        debt1.approve(address(vault), liabilities0Exit);
        debt2.approve(address(vault), liabilities1Exit);

        (
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithShares(shares, alice, alice);

        assertEq(actualAssets.length, assets.length);
        assertEq(actualAssets[0], assets[0]);
        assertEq(actualAssets[1], assets[1]);
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities0Exit);
        assertEq(actualLiabilities[1], liabilities1Exit);

        checkBalanceSheet(123e18 - assets[0] + SEED_ASSET1, 6_150e6 - assets[1] + SEED_ASSET2, 246e18 - liabilities0Exit + SEED_LIABILITY1, 3_075e6 - liabilities1Exit + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), assets[0]);
        assertEq(asset2.balanceOf(alice), assets[1]);
        assertEq(debt1.balanceOf(alice), 246e18 - liabilities0Exit);
        assertEq(debt2.balanceOf(alice), 3_075e6 - liabilities1Exit);
    }

    function test_exitWithToken_fromExitWithSharesQuote() public {
        joinWithToken(alice, alice, asset1, 123e18);

        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);

        uint256 sharesToExit = 5_076.736339697169190258e18;

        // Get a preview to exit the exact number of shares 
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithShares(sharesToExit);

        assertEq(assets[0], 50e18); // Assets returned round down
        assertEq(assets[1], 2_500e6);
        assertEq(liabilities[0], 100e18 + 1); // Exiting with shares rounds liabilities up
        assertEq(liabilities[1], 1_250e6 + 1);

        // Going the other way with that number of liabilities (which was rounded up by one)
        // Gives a different result to previewExitWithShares(), due to rounding in favour of the vault.
        (
            uint256 previewShares,
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewExitWithToken(address(debt2), liabilities[1]);
        assertEq(previewShares, 5_076.736343758558262015e18);
        assertEq(previewAssets[0], 50.000000039999999999e18);
        assertEq(previewAssets[1], 2_500.000001e6);
        assertEq(previewLiabilities[0], 100.00000008e18);
        assertEq(previewLiabilities[1], 1_250.000001e6);

        // But doing the same with 1 less liabilities does yield the same result as the initial previewExitWithShares()
        (
            previewShares,
            previewAssets,
            previewLiabilities
        ) = vault.previewExitWithToken(address(debt2), liabilities[1] - 1);
        assertEq(previewShares, sharesToExit - 1);
        assertEq(previewAssets[0], assets[0] - 1);
        assertEq(previewAssets[1], assets[1] - 1);
        assertEq(previewLiabilities[0], liabilities[0] - 1);
        assertEq(previewLiabilities[1], liabilities[1] - 1);

        // Assume the user already has the debt tokens to repay.
        vm.startPrank(alice);
        debt1.approve(address(vault), liabilities[0] - 1);
        debt2.approve(address(vault), liabilities[1] - 1);

        (
            uint256 actualShares,
            uint256[] memory actualAssets,
            uint256[] memory acualLiabilities
        ) = vault.exitWithToken(address(debt2), liabilities[1] - 1, alice, alice);

        checkBalanceSheet(123e18 - assets[0] + SEED_ASSET1 + 1, 6_150e6 - assets[1] + SEED_ASSET2 + 1, 246e18 - liabilities[0] + 1 + SEED_LIABILITY1, 3_075e6 - liabilities[1] + 1 + SEED_LIABILITY2);
        assertEq(actualShares, sharesToExit - 1);
        assertEq(vault.totalSupply(), 12_238.5e18 - sharesToExit + SEED_SHARES + 1);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - sharesToExit + 1);
        assertEq(asset1.balanceOf(alice), assets[0] - 1);
        assertEq(asset2.balanceOf(alice), assets[1] - 1);
        assertEq(debt1.balanceOf(alice), 246e18 - liabilities[0] + 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - liabilities[1] + 1);
        assertEq(previewAssets[0], actualAssets[0]);
        assertEq(previewAssets[1], actualAssets[1]);
        assertEq(previewLiabilities[0], acualLiabilities[0]);
        assertEq(previewLiabilities[1], acualLiabilities[1]);

        // Full exit
        // Because of the fees on the shares, Alice has less assets then when she started, but also has more liabilities
        // The relative differences are the same
        {
            uint256 expectedRelativeDiff = 0.012021589185638703e18;

            // Originally started with:
            // assets: [123e18, 6_150e6], liabilities: [246e18, 3_075e6], shares: 12238.5e18)
            vm.startPrank(alice);
            debt1.approve(address(vault), type(uint256).max);
            debt2.approve(address(vault), type(uint256).max);
            (
                uint256[] memory fullRedeemAssets,
                uint256[] memory fullRedeemLiabilities
            ) = vault.exitWithShares(vault.balanceOf(alice), alice, alice);
            assertEq(fullRedeemAssets[0], 71.521344530166439436e18);
            assertEq(fullRedeemAssets[1], 3576.067227e6);
            assertEq(fullRedeemLiabilities[0], 143.042689060332878872e18);
            assertEq(fullRedeemLiabilities[1], 1_788.033614e6);

            assertEq(asset1.balanceOf(alice), 121.521344530166439435e18);
            uint256 diff = 123e18 - 121.521344530166439435e18;
            assertEq(diff * 1e18 / 123e18, expectedRelativeDiff);

            assertEq(asset2.balanceOf(alice), 6076.067226e6);
            diff = 6_150e6 - 6_076.067226e6;
            assertEq(diff*1e6/6_150e6, expectedRelativeDiff/1e12);

            assertEq(debt1.balanceOf(alice), 2.957310939667121128e18);
            assertEq(uint256(2.957310939667121128e18) * 1e18 / 246e18, expectedRelativeDiff);

            assertEq(debt2.balanceOf(alice), 36.966386e6);
            assertEq(uint256(36.966386e6) * 1e6 / 3_075e6, expectedRelativeDiff/1e12);

            assertEq(vault.balanceOf(alice), 0);
        }
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

contract OrigamiTokenizedBalanceSheetVaultTestExitWithShares is OrigamiTokenizedBalanceSheetVaultTestBase { 
    function test_exitWithShares_fail_exitTooMuch() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        asset1.approve(address(vault), asset1.balanceOf(alice));
        asset2.approve(address(vault), asset2.balanceOf(alice));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithShares.selector, alice, 12_238.5e18 + 1, 12_238.5e18));
        vault.exitWithShares(12_238.5e18 + 1, alice, alice);
    }

    function test_exitWithShares_basic() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, alice, 5_076.736339697169190258e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1 - 1, 3_075e6 - 1_250e6 + SEED_LIABILITY2 - 1);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);
    }

    function test_exitWithShares_differentReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, bob, 5_076.736339697169190258e18);
        checkBalanceSheet(123e18 - 50e18 + SEED_ASSET1, 6_150e6 - 2_500e6 + SEED_ASSET2, 246e18 - 100e18 + SEED_LIABILITY1 - 1, 3_075e6 - 1_250e6 + SEED_LIABILITY2 - 1);
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);

        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset1.balanceOf(bob), 50e18);
        assertEq(asset2.balanceOf(bob), 2_500e6);
        assertEq(debt1.balanceOf(bob), 0);
        assertEq(debt2.balanceOf(bob), 0);
    }

    function test_exitWithShares_badReceiver() public {
        joinWithToken(alice, alice, asset1, 123e18);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.exitWithShares(1e18, address(0), alice);
    }

    function test_exitWithShares_zeroSharesOwner() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.exitWithShares(1e18, alice, address(0));
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
        assertEq(vault.allowance(alice, bob), type(uint256).max);

        {
            checkBalanceSheet(
                123e18 - 0.098488471045913198e18 - 0.492450343911972279e18 + SEED_ASSET1,
                6_150e6 - 4.924423e6 - 24.622517e6 + SEED_ASSET2,
                246e18 - 0.196976942091826398e18 - 0.984900687823944560e18 + SEED_LIABILITY1,
                3_075e6 - 2.462212e6 - 12.311259e6 + SEED_LIABILITY2
            );

            assertEq(vault.totalSupply(), 12_238.5e18 - 10e18 - 50e18 + SEED_SHARES);
            assertEq(vault.balanceOf(alice), 12_238.5e18 - 10e18 - 50e18);
            assertEq(asset1.balanceOf(alice), 0);
            assertEq(asset2.balanceOf(alice), 0);
            assertEq(debt1.balanceOf(alice), 246e18);
            assertEq(debt2.balanceOf(alice), 3_075e6);

            assertEq(vault.balanceOf(bob), 0);
            assertEq(asset1.balanceOf(bob), 0.098488471045913198e18 + 0.492450343911972279e18);
            assertEq(asset2.balanceOf(bob), 4.924423e6 + 24.622517e6);
            assertEq(debt1.balanceOf(bob), 1_000_000e18 - (0.196976942091826398e18 + 0.984900687823944560e18));
            assertEq(debt2.balanceOf(bob), 1_000_000e6 - (2.462212e6 + 12.311259e6));
        }
    }

    function test_exitWithShares_multiple() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, alice, 2_538.368169848584595129e18); // half of the shares from the `test_exitWithShares_basic` test
        exitWithShares(alice, alice, alice, 2_538.368169848584595129e18); // and again
        // The multiple exits burn more fees than the single one.
        checkBalanceSheet(
            123e18 - 25e18 - 25.129506837961044343e18 + SEED_ASSET1,
            6_150e6 - 1_250e6 - 1_256.475341e6 + SEED_ASSET2, 
            246e18 - 50e18 - 1 - 50.259013675922088687e18 + SEED_LIABILITY1, 
            3_075e6 - 625e6 - 1 - 628.237671e6 + SEED_LIABILITY2
        );

        uint256 expectedSharesBurned = 2_538.368169848584595129e18 * 2;
        assertEq(vault.totalSupply(), 12_238.5e18 - expectedSharesBurned + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - expectedSharesBurned);
        assertEq(asset1.balanceOf(alice), 25e18 + 25.129506837961044343e18);
        assertEq(asset2.balanceOf(alice), 1_250e6 + 1_256.475341e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 50e18 - 1 - 50.259013675922088687e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 625e6 - 1 - 628.237671e6);
    }

    function test_exitWithShares_zeroAmount() public {
        joinWithToken(alice, alice, asset1, 123e18);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vault.exitWithShares(0, alice, alice);
    }

    function test_exitWithShares_noAssetLeft() public {
        joinWithToken(alice, alice, asset1, 123e18);

        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(asset1)),
            abi.encode(0)
        );
        checkBalanceSheet(0, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);

        checkPreviewExitWithShares(101.534726793943383807e18, 0, 50e6, 2e18 + 1, 25e6 + 1);
        assertEq(vault.maxExitWithShares(alice), 12_238.5e18);

        exitWithShares(alice, alice, alice, 101.534726793943383807e18);
        checkBalanceSheet(0, 6_150e6 + SEED_ASSET2 - 50e6, 246e18 + SEED_LIABILITY1 - (2e18 + 1), 3_075e6 + SEED_LIABILITY2 - (25e6 + 1));
    }

    function test_exitWithShares_noLiabilitiesLeft() public {
        joinWithToken(alice, alice, asset1, 123e18);

        // Mock that there are no assets left
        vm.mockCall(
            address(borrowLend),
            abi.encodeWithSelector(MockBorrowLend.balanceOfToken.selector, address(debt2)),
            abi.encode(0)
        );
        checkBalanceSheet(123e18 + SEED_ASSET1, 6_150e6 + SEED_ASSET2, 246e18 + SEED_LIABILITY1, 0);

        checkPreviewExitWithShares(101.534726793943383807e18, 1e18, 50e6, 2e18 + 1, 0);
        assertEq(vault.maxExitWithShares(alice), 12_238.5e18);

        exitWithShares(alice, alice, alice, 101.534726793943383807e18);
        checkBalanceSheet(123e18 + SEED_ASSET1 - 1e18, 6_150e6 + SEED_ASSET2 - 50e6, 246e18 + SEED_LIABILITY1 - (2e18 + 1), 0);
    }

    function test_exitWithShares_beforeShareIncrease_asset() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithShares(alice, alice, alice, 5_076.736339697169190258e18);

        checkConvertFromShares(1e18, 0.010190361937077148e18, 0.509518e6, 0.020380723874154297e18, 0.254759e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.023961121311505727e18, 0.523288e6, 0.020380723874154297e18, 0.282300e6);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18,
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6,
            246e18 + SEED_LIABILITY1 - 100e18 - 1,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6 - 1
        );
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 1);
    }

    function test_exitWithShares_afterShareIncrease() public {
        joinWithToken(alice, alice, asset1, 123e18);

        checkConvertFromShares(1e18, 0.010049843984276856e18, 0.502492e6, 0.020099687968553713e18, 0.251246e6);
        increaseSharePrice(100e18, 100e6, 0, 200e6);
        checkConvertFromShares(1e18, 0.018154556874822709e18, 0.510596e6, 0.020099687968553713e18, 0.267455e6);

        exitWithShares(alice, alice, alice, 5_076.736339697169190258e18);

        checkBalanceSheet(
            123e18 + 100e18 + SEED_ASSET1 - 50e18 - 40.322580645161290322e18,
            6_150e6 + 100e6 + SEED_ASSET2 - 2_500e6 - 40.322580e6,
            246e18 + SEED_LIABILITY1 - 100e18 - 1,
            3_075e6 + 200e6 + SEED_LIABILITY2 - 1_250e6 - 80.645162e6
        );
        assertEq(vault.totalSupply(), 12_238.5e18 - 5_076.736339697169190258e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_238.5e18 - 5_076.736339697169190258e18);
        assertEq(asset1.balanceOf(alice), 50e18 + 40.322580645161290322e18);
        assertEq(asset2.balanceOf(alice), 2_500e6 + 40.322580e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18 - 1);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6 - 80.645162e6);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestPermitAndBurn is OrigamiTokenizedBalanceSheetVaultTestBase {
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Transfer(address indexed from, address indexed to, uint256 amount);

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

    function test_burn() public {
        joinWithShares(alice, alice, 1e18);
        checkConvertFromShares(1e18, 0.010000497537190905e18, 0.500024e6, 0.020000995074381810e18, 0.250012e6);

        vm.startPrank(alice);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vault.burn(1e18+1);
        
        vm.expectEmit(address(vault));
        emit Transfer(alice, address(0), 0.5e18);
        vault.burn(0.5e18);
        checkConvertFromShares(1e18, 0.010050251256281407e18, 0.502512e6, 0.020100502512562814e18, 0.251256e6);
        assertEq(vault.balanceOf(alice), 0.5e18);

        vm.expectEmit(address(vault));
        emit Transfer(alice, address(0), 0.5e18);
        vault.burn(0.5e18);
        checkConvertFromShares(1e18, 0.010100502512562814e18, 0.505025e6, 0.020201005025125628e18, 0.252512e6);
        assertEq(vault.balanceOf(alice), 0);
    }
}

contract OrigamiTokenizedBalanceSheetVaultTestViewsReplicateMaxExitIssue is OrigamiTokenizedBalanceSheetVaultTestBase {
    function setUp() public override {
        setUpWithFees(0, 0);

        uint256[] memory assetAmounts = new uint256[](2);
        (assetAmounts[0], assetAmounts[1]) = (1000000000016983031, 2196543925);

        uint256[] memory liabilityAmounts = new uint256[](2);
        (liabilityAmounts[0], liabilityAmounts[1]) = (2000000000033956459, 25014183);

        vm.startPrank(origamiMultisig);
        asset1.deal(origamiMultisig, assetAmounts[0]);
        asset1.approve(address(vault), assetAmounts[0]);
        asset2.deal(origamiMultisig, assetAmounts[1]);
        asset2.approve(address(vault), assetAmounts[1]);
        vault.seed(assetAmounts, liabilityAmounts, 100000000001697725363, origamiMultisig, type(uint256).max);

        vm.stopPrank();
    }

    function test_maxExit_nearEmpty_debt2() public {
        // Mock that alice has 3167 shares (near zero)
        deal(address(vault), alice, 3167);

        // max exit for alice shares == 3167 ✅
        assertEq(vault.maxExitWithShares(alice), 3167);

        // preview for a complete exit for all Alice's shares:
        //  - receive: 31 asset1 
        //  - receive: 0  asset2
        //  - pay in:  64 debt1
        //  - pay in:  1 debt2
        checkPreviewExitWithShares(3167, 31, 0, 64, 1);

        // max exit for alice with debt2 == 0
        assertEq(vault.maxExitWithToken(address(debt2), alice), 0);
        checkPreviewExitWithToken(debt2, 0, 0, 0, 0, 0, 0);

        // That's because a preview exit with 1 debt2 would:
        //  - burn 3997732006745 (❌ more shares than Alice has!)
        //  - receive: 39977320067 asset1
        //  - receive: 87 asset2
        //  - pay in:  79954640135 debt1
        //  - pay in:  1 debt2
        checkPreviewExitWithToken(debt2, 1, 3997732006745, 39977320067, 87, 79954640135, 1);

        // ^^^ This would try and burn more shares than Alice has ❌
        // 3997732006745 >> 3167
        // So it's correct that the maxExitWithToken() only shows zero
    }

    function test_maxExit_nearEmpty_asset1() public {
        // Mock that alice has 3167 shares (near zero)
        deal(address(vault), alice, 3167);

        // max exit for alice shares == 3167 ✅
        assertEq(vault.maxExitWithShares(alice), 3167);

        // preview for a complete exit for all Alice's shares:
        //  - receive: 31 asset1 
        //  - receive: 0  asset2
        //  - pay in:  64 debt1
        //  - pay in:  1 debt2
        checkPreviewExitWithShares(3167, 31, 0, 64, 1);

        // max exit for alice with asset1 == 31
        assertEq(vault.maxExitWithToken(address(asset1), alice), 31);

        // A preview exit with 31 asset1:
        //  - burn 3100 (✅ less shares than Alice has!)
        //  - receive: 31 asset1
        //  - receive: 0 asset2
        //  - pay in:  62 debt1
        //  - pay in:  1 debt2
        checkPreviewExitWithToken(asset1, 31, 3100, 31, 0, 63, 1);

        // A preview for one more would try and burn more shares than Alice has ❌
        checkPreviewExitWithToken(asset1, 32, 3200, 32, 0, 65, 1);
    }
}
