pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { MockDynamicTokensTokenizedBalanceSheetVault } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockDynamicTokensTokenizedBalanceSheetVault.m.sol";
import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";

//TODO: combine all the common functionalities into one contract, just make sure to give freedom on the vault implementation
//TODO: rename to DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBASE
contract DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    struct Rollover {
        address[] tokensRenewed;
        uint256[] amountsRenewedMin;

        address[] tokensExpired;
        uint256[] amountsExpired;
    }

    DummyMintableTokenPermissionless internal asset1;
    DummyMintableTokenPermissionless internal asset2;
    DummyMintableTokenPermissionless internal debt1;
    DummyMintableTokenPermissionless internal debt2;
    MockDynamicTokensTokenizedBalanceSheetVault internal vault;
    MockBorrowLend internal borrowLend;

    uint256 internal constant MAX_TOTAL_SUPPLY = type(uint256).max;
    uint16 internal immutable JOIN_FEE = 0;
    uint16 internal immutable EXIT_FEE = 0;

    uint256 internal constant SEED_SHARES = 100e18;
    uint256 internal constant SEED_ASSET1 = 1e18;
    uint256 internal constant SEED_ASSET2 = 50e6;
    uint256 internal constant SEED_LIABILITY1 = 2e18;
    uint256 internal constant SEED_LIABILITY2 = 25e6;

    uint256 internal constant SEED_ASSET1_NEW = 0.5e18;
    uint256 internal constant SEED_ASSET2_NEW = 40e6;

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

    function setUp() public virtual {
        setUpVault(0, 0);
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
    }

    function setUpVault(uint16 joinFeeBps, uint16 exitFeeBps) internal {
        asset1 = new DummyMintableTokenPermissionless("ASSET1_18dp", "ASSET1_18dp", 18);
        vm.label(address(asset1), asset1.symbol());
        asset2 = new DummyMintableTokenPermissionless("ASSET2_6dp", "ASSET2_6", 6);
        vm.label(address(asset2), asset2.symbol());
        address[] memory _assets = new address[](2);
        (_assets[0], _assets[1]) = (address(asset1), address(asset2));

        debt1 = new DummyMintableTokenPermissionless("DEBT1_18dp", "DEBT1_18dp", 18);
        vm.label(address(debt1), debt1.symbol());
        debt2 = new DummyMintableTokenPermissionless("DEBT2_6dp", "DEBT2_6dp", 6);
        vm.label(address(debt2), debt2.symbol());
        address[] memory _liabilities = new address[](2);
        (_liabilities[0], _liabilities[1]) = (address(debt1), address(debt2));

        borrowLend = new MockBorrowLend(_assets, _liabilities);

        vault = new MockDynamicTokensTokenizedBalanceSheetVault(origamiMultisig, 
            "DynamicTokenizedBalanceSheet",
            "DTBSV",
            _assets,
            _liabilities,
            joinFeeBps,
            exitFeeBps,
            borrowLend
        );
        vm.label(address(vault), vault.symbol());
        vm.warp(100000000);

        asset1.deal(address(this), type(uint168).max);
        asset1.approve(address(borrowLend), type(uint168).max);
        asset2.deal(address(this), type(uint168).max);
        asset2.approve(address(borrowLend), type(uint168).max);
        debt1.deal(address(borrowLend), type(uint168).max);
        debt2.deal(address(borrowLend), type(uint168).max);
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
        address[] memory assetTokens = vault.assetTokens();

        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        _checkInputTokenAmount(token, tokenAmount, assetTokens, assets, liabilities);

        vm.startPrank(user);

        for(uint256 i; i < assets.length; i++) {
            if(assets[i] != 0) {
                DummyMintableTokenPermissionless(assetTokens[i]).deal(user, assets[i]); 
                IERC20(assetTokens[i]).approve(address(vault), assets[i]);
            }
        }

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

        for(uint256 i; i < actualAssets.length; i++) {
            assertEq(actualAssets[i], assets[i]);
        }
        
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);

        _checkInputTokenAmount(token, tokenAmount, assetTokens, actualAssets, actualLiabilities);
    }

    function joinWithShares(address user, address receiver, uint256 shares) internal {
        address[] memory assetTokens = vault.assetTokens();

        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithShares(shares);
        
        vm.startPrank(user);

        for(uint256 i; i < assets.length; i++) {
            if(assets[i] != 0) {
                DummyMintableTokenPermissionless(assetTokens[i]).deal(user, assets[i]); 
                IERC20(assetTokens[i]).approve(address(vault), assets[i]);
            }
        }
        
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

        for(uint256 i; i < actualAssets.length; i++) {
            assertEq(actualAssets[i], assets[i]);
        }
        
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);
    }

    function exitWithToken(address caller, address sharesOwner, address receiver, IERC20 token, uint256 tokenAmount) internal {
        address[] memory assetTokens = vault.assetTokens();

        (
            uint256 expectedShares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithToken(address(token), tokenAmount);

        _checkInputTokenAmount(token, tokenAmount, assetTokens, assets, liabilities);

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

        for(uint256 i; i < actualAssets.length; i++) {
            assertEq(actualAssets[i], assets[i]);
        }
        
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);

        _checkInputTokenAmount(token, tokenAmount, assetTokens, actualAssets, actualLiabilities);
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

        for(uint256 i; i < actualAssets.length; i++) {
            assertEq(actualAssets[i], assets[i]);
        }
        
        assertEq(actualLiabilities.length, liabilities.length);
        assertEq(actualLiabilities[0], liabilities[0]);
        assertEq(actualLiabilities[1], liabilities[1]);
    }

    //NOTE: MUST always pass the assets in the order of the vault
    function checkConvertFromShares(uint256 shares, uint256[] memory expectedAssets, uint256 expectedLiabilities1, uint256 expectedLiabilities2) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = vault.convertFromShares(shares);

        for(uint256 i; i < expectedAssets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("convertFromShares::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "convertFromShares::liabilities::length");
        assertEq(liabilities[0], expectedLiabilities1, "convertFromShares::liabilities[0]");
        assertEq(liabilities[1], expectedLiabilities2, "convertFromShares::liabilities[1]");
    }

    function checkBalanceSheet(uint256[] memory expectedAssets, uint256 expectedLiabilities1, uint256 expectedLiabilities2) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = vault.balanceSheet();

        for(uint256 i; i < assets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("balanceSheet::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "balanceSheet::liabilities::length");
        assertEq(liabilities[0], expectedLiabilities1, "balanceSheet::liabilities[0]");
        assertEq(liabilities[1], expectedLiabilities2, "balanceSheet::liabilities[1]");
    }

    function checkConvertFromToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256[] memory expectedAssets,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.convertFromToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "convertFromToken::shares");

        for(uint256 i; i < assets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("convertFromToken::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "convertFromToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "convertFromToken::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "convertFromToken::liabilities[1]");
    }

    function checkPreviewJoinWithShares(
        uint256 shares,
        uint256[] memory expectedAssets,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithShares(shares);

        for(uint256 i; i < assets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("previewJoinWithShares::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "previewJoinWithShares::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewJoinWithShares::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewJoinWithShares::liabilities[1]");
    }

    function checkPreviewJoinWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256[] memory expectedAssets,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewJoinWithToken::shares");
        
        for(uint256 i; i < assets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("previewJoinWithToken::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "previewJoinWithToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewJoinWithToken::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewJoinWithToken::liabilities[1]");
    }

    function checkPreviewExitWithShares(
        uint256 shares,
        uint256[] memory expectedAssets,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithShares(shares);

        for(uint256 i; i < assets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("previewExitWithShares::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "previewExitWithShares::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewExitWithShares::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewExitWithShares::liabilities[1]");
    }

    function checkPreviewExitWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256[] memory expectedAssets,
        uint256 expectedLiability1,
        uint256 expectedLiability2
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewExitWithToken::shares");

        for(uint256 i; i < assets.length; i++) {
            assertEq(assets[i], expectedAssets[i], string.concat("previewExitWithToken::", DummyMintableTokenPermissionless(address(vault.assetTokens()[i])).name()));
        }

        assertEq(liabilities.length, 2, "previewExitWithToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewExitWithToken::liabilities[0]");
        assertEq(liabilities[1], expectedLiability2, "previewExitWithToken::liabilities[1]");
    }

    //NOTE: always take care not to increase the expired assets, as they're not removed from the arrays in the borrowLend
    function increaseSharePrice(uint256[] memory assetsAmounts, uint256 debt1Amount, uint256 debt2Amount) internal {
        uint256[] memory debts = new uint256[](2);
        (debts[0], debts[1]) = (debt1Amount, debt2Amount);

        borrowLend.addCollateralAndBorrow(assetsAmounts, debts, origamiMultisig);
    }

    function createRollover(
        address[] memory _tokensRenewed,
        uint256[] memory _amountsRenewedMin,
        address[] memory _tokensExpired,
        uint256[] memory _amountsExpired
    ) public pure returns(MockDynamicTokensTokenizedBalanceSheetVault.Rollover memory) {
        return MockDynamicTokensTokenizedBalanceSheetVault.Rollover({
            tokensRenewed: _tokensRenewed,
            amountsRenewedMin: _amountsRenewedMin,
            tokensExpired: _tokensExpired,
            amountsExpired: _amountsExpired
        });
    }

    function createToken(string memory name, string memory symbol, uint8 dp) public returns (address) {
        DummyMintableTokenPermissionless token = new DummyMintableTokenPermissionless(name, symbol, dp);

        vm.label(address(token), name);
        token.deal(address(this), type(uint168).max);
        token.approve(address(borrowLend), type(uint168).max);

        return address(token);
    }

    function doRollover(address[] memory assetTokens, uint256[] memory assetsBalances, uint256 rolloverAmount0, uint256 rolloverAmount1) public returns (address asset1New, address asset2New) {        
        asset1New = createToken("Asset1New_18DP", "Asset1New", 18); 
        asset2New = createToken("Asset2New_6DP", "Asset2New", 6); 

        address[] memory rolloverTokens = new address[](2);
        rolloverTokens[0] = asset1New;
        rolloverTokens[1] = asset2New;

        uint256[] memory rolloverAmounts = new uint256[](2);
        rolloverAmounts[0] = rolloverAmount0 == 0 ? SEED_ASSET1_NEW : rolloverAmount0;
        rolloverAmounts[1] = rolloverAmount1 == 0 ? SEED_ASSET2_NEW : rolloverAmount1;

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));
    }

    function _checkInputTokenAmount(
        IERC20 token,
        uint256 tokenAmount,
        address[] memory assetTokens,
        uint256[] memory assetAmounts,
        uint256[] memory liabilityAmounts
    ) private view {
        if (address(token) == address(asset1)) assertEq(assetAmounts[0], tokenAmount, "asset1 input tokenAmount not matching derived output amount");
        if (address(token) == address(asset2)) assertEq(assetAmounts[1], tokenAmount, "asset2 input tokenAmount not matching derived output amount");

        for(uint256 i; i < assetTokens.length; i++) {
            if (address(token) == address(assetTokens[i])) {
                assertEq(assetAmounts[i], tokenAmount, string.concat(DummyMintableTokenPermissionless(address(token)).name(), " input tokenAmount not matching derived output amount"));
            }
        }

        if (address(token) == address(debt1)) assertEq(liabilityAmounts[0], tokenAmount, "debt1 input tokenAmount not matching derived output amount");
        if (address(token) == address(debt2)) assertEq(liabilityAmounts[1], tokenAmount, "debt2 input tokenAmount not matching derived output amount");
    }
}

contract DynamicOrigamiTokenizedBalanceSheetVaultTestRolloverJoinWithToken is DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase {

    using Strings for uint256;
    function test_basic_rollover() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        doRollover(assetTokens, assetsBalances, 0, 0);
 
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = vault.balanceSheet();

        assertEq(totalAssets.length, 4);
        assertEq(totalAssets[0], 0);
        assertEq(totalAssets[1], 0);
        assertEq(totalAssets[2], 0.5e18);
        assertEq(totalAssets[3], 40e6);
        assertEq(totalLiabilities[0], 2e18);
        assertEq(totalLiabilities[1], 25e6);
    }

    function test_maxExit() public {
        assertEq(vault.maxExitWithToken(address(asset1), bob), 0);
        assertEq(vault.maxExitWithToken(address(asset2), bob), 0);
        assertEq(vault.maxExitWithToken(address(debt1), bob), 0);
        assertEq(vault.maxExitWithToken(address(debt2), bob), 0);

        assertEq(vault.maxExitWithToken(address(asset1), origamiMultisig), 1e18);
        assertEq(vault.maxExitWithToken(address(asset2), origamiMultisig), 50e6);
        assertEq(vault.maxExitWithToken(address(debt1), origamiMultisig), 2e18);
        assertEq(vault.maxExitWithToken(address(debt2), origamiMultisig), 25e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (address asset1New, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        assertEq(vault.maxExitWithToken(address(asset1), bob), 0);
        assertEq(vault.maxExitWithToken(address(asset2), bob), 0);
        assertEq(vault.maxExitWithToken(address(debt1), bob), 0);
        assertEq(vault.maxExitWithToken(address(debt2), bob), 0);

        assertEq(vault.maxExitWithToken(address(asset1), origamiMultisig), 0);
        assertEq(vault.maxExitWithToken(address(asset2), origamiMultisig), 0);
        assertEq(vault.maxExitWithToken(address(asset1New), origamiMultisig), 0.5e18);
        assertEq(vault.maxExitWithToken(address(asset2New), origamiMultisig), 40e6);
        assertEq(vault.maxExitWithToken(address(debt1), origamiMultisig), 2e18);
        assertEq(vault.maxExitWithToken(address(debt2), origamiMultisig), 25e6);
    }

    function test_previewJoin_fullRebalance() public {
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 1e18;
        expectedAssets[1] = 50e6;

        checkPreviewJoinWithShares(100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(asset1, 1e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(asset2, 50e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (address asset1New, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 0.5e18;
        expectedAssets[3] = 40e6;

        checkPreviewJoinWithShares(100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(IERC20(asset1New), 0.5e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(IERC20(asset2New), 40e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        expectedAssets[2] = 0;
        expectedAssets[3] = 0;

        checkPreviewJoinWithToken(asset1, 1e18, 0, expectedAssets, 0, 0);
        checkPreviewJoinWithToken(asset2, 50e6, 0, expectedAssets, 0, 0);
    }

    function test_previewJoin_halfRebalance_sharePrice_decreases() public {
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 1e18;
        expectedAssets[1] = 50e6;

        checkPreviewJoinWithShares(100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(asset1, 1e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(asset2, 50e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        assetsBalances[0] = SEED_ASSET1 / 2;
        assetsBalances[1] = SEED_ASSET2 / 2;
        
        (address asset1New, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        expectedAssets[0] = SEED_ASSET1 / 2;
        expectedAssets[1] = SEED_ASSET2 / 2;
        expectedAssets[2] = SEED_ASSET1_NEW;
        expectedAssets[3] = SEED_ASSET2_NEW;

        checkPreviewJoinWithShares(100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(IERC20(asset1New), 0.5e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(IERC20(asset2New), 40e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewJoinWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        expectedAssets[0] = 1e18;
        expectedAssets[1] = 50e6;
        expectedAssets[2] = 1e18;
        expectedAssets[3] = 80e6;

        checkPreviewJoinWithToken(asset1, 1e18, SEED_SHARES * 2, expectedAssets, SEED_LIABILITY1 * 2, SEED_LIABILITY2 * 2);
        checkPreviewJoinWithToken(asset2, 50e6, SEED_SHARES * 2, expectedAssets, SEED_LIABILITY1 * 2, SEED_LIABILITY2 * 2);
    }

    function test_previewExit_fullRebalance() public {
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 1e18;
        expectedAssets[1] = 50e6;

        checkPreviewExitWithShares(100e18, expectedAssets, 2e18, 25e6);

        checkPreviewExitWithToken(asset1, 1e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(asset2, 50e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (address asset1New, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 0.5e18;
        expectedAssets[3] = 40e6;

        checkPreviewExitWithShares(100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(IERC20(asset1New), 0.5e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(IERC20(asset2New), 40e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        expectedAssets[2] = 0;
        expectedAssets[3] = 0;

        checkPreviewExitWithToken(asset1, 1e18, 0, expectedAssets, 0, 0);
        checkPreviewExitWithToken(asset2, 50e6, 0, expectedAssets, 0, 0);
    }

    function test_previewExit_halfRebalance_sharePriceDecreases() public {
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 1e18;
        expectedAssets[1] = 50e6;

        checkPreviewExitWithShares(100e18, expectedAssets, 2e18, 25e6);

        checkPreviewExitWithToken(asset1, 1e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(asset2, 50e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        assetsBalances[0] = SEED_ASSET1 / 2;
        assetsBalances[1] = SEED_ASSET2 / 2;
        
        (address asset1New, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        expectedAssets[0] = SEED_ASSET1 / 2;
        expectedAssets[1] = SEED_ASSET2 / 2;
        expectedAssets[2] = SEED_ASSET1_NEW;
        expectedAssets[3] = SEED_ASSET2_NEW;

        checkPreviewExitWithShares(100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(IERC20(asset1New), 0.5e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(IERC20(asset2New), 40e6, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt1, 2e18, 100e18, expectedAssets, 2e18, 25e6);
        checkPreviewExitWithToken(debt2, 25e6, 100e18, expectedAssets, 2e18, 25e6);

        expectedAssets[0] = 1e18;
        expectedAssets[1] = 50e6;
        expectedAssets[2] = 1e18;
        expectedAssets[3] = 80e6;

        checkPreviewExitWithToken(asset1, 1e18, SEED_SHARES * 2, expectedAssets, SEED_LIABILITY1 * 2, SEED_LIABILITY2 * 2);
        checkPreviewExitWithToken(asset2, 50e6, SEED_SHARES * 2, expectedAssets, SEED_LIABILITY1 * 2, SEED_LIABILITY2 * 2);
    }

    function test_joinWithToken_badTokenAddress_nonSupported_asset() public {
        DummyMintableTokenPermissionless nonSupportedAsset = new DummyMintableTokenPermissionless("WEIRD_18dp", "WEIRD_18dp", 18);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, bob, address(nonSupportedAsset), 10e18, 0));
        vault.joinWithToken(address(nonSupportedAsset), 10e18, bob); 
    }

    function test_joinWithToken_basic_asset1New_fullRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (address asset1New, ) = doRollover(assetTokens, assetsBalances, 0, 0);
        
        joinWithToken(alice, alice, IERC20(asset1New), 123e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 123e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 9840e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 492e18 + SEED_LIABILITY1, 6150e6 + SEED_LIABILITY2);
    }

    function test_joinWithToken_basic_asset1New_randomRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        assetsBalances[0] = SEED_ASSET1 - 0.546431331313123121e18;
        assetsBalances[1] = SEED_ASSET2 - 24234563;
        
        (address asset1New,) = doRollover(assetTokens, assetsBalances, 0, 0);
        
        joinWithToken(alice, alice, IERC20(asset1New), 123e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = (SEED_ASSET1 - 0.453568668686876879e18) + 134.422107503028287766e18;
        expectedAssets[1] = (SEED_ASSET2 - 25.765437e6) + 5961.702498e6;
        expectedAssets[2] = 123e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 9840e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 492e18 + SEED_LIABILITY1, 6150e6 + SEED_LIABILITY2);
    }

    function test_joinWithToken_basic_asset2New_fullRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);
        
        joinWithToken(alice, alice, IERC20(asset2New), 9840e6);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 123e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 9840e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 492e18 + SEED_LIABILITY1, 6150e6 + SEED_LIABILITY2);
    }

    function test_joinWithToken_basic_asset2New_randomRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        assetsBalances[0] = SEED_ASSET1 - 0.546431331313123121e18;
        assetsBalances[1] = SEED_ASSET2 - 24234563;
        
        (, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);
        
        joinWithToken(alice, alice, IERC20(asset2New), 9840e6);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = (SEED_ASSET1 - 0.453568668686876879e18) + 134.422107503028287766e18;
        expectedAssets[1] = (SEED_ASSET2 - 25.765437e6) + 5961.702498e6;
        expectedAssets[2] = 123e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 9840e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 492e18 + SEED_LIABILITY1, 6150e6 + SEED_LIABILITY2);
    }

    function test_joinWithToken_multiple_fullRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (address asset1New,) = doRollover(assetTokens, assetsBalances, 0, 0);

        joinWithToken(alice, alice, IERC20(asset1New), 61.5e18); // half of asset1 from the `test_joinWithToken_basic_asset1New_fullRebalance` test
        joinWithToken(alice, alice, debt2, 3075e6); // half of debt2 from the `test_joinWithToken_basic_debt2` test
        
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 123e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 9840e6 + SEED_ASSET2_NEW;
        
        checkBalanceSheet(expectedAssets, 492e18 + SEED_LIABILITY1, 6150e6 + SEED_LIABILITY2);

        //note: due to rebalance share are twice less expensive
        uint256 expectedSharesMinted = (6150e18 + 6150e18) * 2;
        assertEq(expectedSharesMinted, 24600e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 * 2);
        assertEq(debt2.balanceOf(alice), 3_075e6 * 2);
    }

    function test_joinWithToken_multiple_rebalance_joinWithToken() public {
        joinWithToken(alice, alice, asset1, 61.5e18); // half of asset1 from the `test_joinWithToken_basic_debt2` test
        joinWithToken(alice, alice, debt2, 1_537.5e6); // half of debt2 from the `test_joinWithToken_basic_debt2` test
        
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 123e18 + SEED_ASSET1;
        expectedAssets[1] = 6_150e6 + SEED_ASSET2;
        expectedAssets[2] = 0;
        expectedAssets[3] = 0;

        checkBalanceSheet(expectedAssets, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);

        uint256 expectedSharesMinted = 6150e18 + 6150e18;
        assertEq(expectedSharesMinted, 12300e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (address asset1New, ) = doRollover(assetTokens, assetsBalances, 0, 0);

        joinWithToken(alice, alice, IERC20(asset1New), 61.5e18); // half of asset1 from the `test_joinWithToken_basic_asset1New_fullRebalance` test
        joinWithToken(alice, alice, debt2, 3075e6); // half of debt2 from the `test_joinWithToken_basic_debt2` test

        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = SEED_ASSET1_NEW + 61.5e18 + 0.495967741935483871e18;
        expectedAssets[3] = SEED_ASSET2_NEW + 4920e6 + 39.677420e6;
        
        checkBalanceSheet(
            expectedAssets, 
            SEED_LIABILITY1 + 246e18 + 30504e18 + 246e18,
            SEED_LIABILITY2 + 3075e6 + 381300e6 + 3075e6);

        //note: due to rebalance share are twice less expensive
        expectedSharesMinted = (6150e18 + 6150e18) + 1525200e18 + 12300e18;
        assertEq(expectedSharesMinted, 1549800e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 * 2 + 30504e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 * 2 + 381300e6);
    }

    function test_joinWithToken_before_full_rebalance_exit_after_empties_vault() public {
        joinWithToken(bob, bob, asset1, 1e18);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        (, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        exitWithToken(bob, bob, bob, IERC20(asset2New), vault.maxExitWithToken(asset2New, bob));

        exitWithShares(origamiMultisig, origamiMultisig, origamiMultisig, vault.maxExitWithShares(origamiMultisig));

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 0;
        expectedAssets[3] = 0;

        checkBalanceSheet(expectedAssets, 0, 0);
        assertEq(vault.totalSupply(), 0, "total supply");
    }

    function test_joinWithToken_rebalance_shareIncrease_empties_vault() public {
        joinWithToken(bob, bob, asset1, 1e18);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18); 
        address asset2New = createToken("Asset2New_6DP", "Asset2New", 6); 

        address[] memory rolloverTokens = new address[](2);
        rolloverTokens[0] = asset1New;
        rolloverTokens[1] = asset2New;

        uint256[] memory rolloverAmounts = new uint256[](2);
        rolloverAmounts[0] = 15e18;
        rolloverAmounts[1] = 40e6;

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        uint256[] memory assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 15e18;
        assetsAmounts[3] = 40e6;

        checkBalanceSheet(assetsAmounts, 4e18, 50e6);

        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 12352242353451232;
        assetsAmounts[3] = 51231;

        increaseSharePrice(assetsAmounts, 0, 59942);

        debt2.deal(bob, 25000000 + 29971);//note: this happens due to the share decrease and the ratios change, add appropriate assertions
        
        exitWithToken(bob, bob, bob, IERC20(debt1), vault.maxExitWithToken(address(debt1), bob) - 1);
    }
    
    function test_joinWithToken_singleToken_rollover() public {
        joinWithToken(bob, bob, asset1, 1.231254351265336344e18);

        address[] memory assetTokens = new address[](1);
        assetTokens[0] = address(asset1);
        uint256[] memory assetsBalances = new uint256[](1);
        assetsBalances[0] = 1.231254351265336344e18 + SEED_ASSET1;

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18);

        address[] memory rolloverTokens = new address[](1);
        rolloverTokens[0] = asset1New;

        uint256[] memory rolloverAmounts = new uint256[](1);
        rolloverAmounts[0] = 1.115627175632668172e18;//note: half the asset1 balance

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        assertEq(vault.maxJoinWithToken(address(asset1), bob), 0);

        uint256[] memory expectedAssets = new uint256[](3);
        expectedAssets[0] = 0;
        expectedAssets[1] = 50e6 + 61.562718e6;
        expectedAssets[2] = 1.115627175632668172e18;

        checkBalanceSheet(expectedAssets, 2.462508702530672688e18 + SEED_LIABILITY1, 30.781358e6 + SEED_LIABILITY2);

        expectedAssets[1] = 100e6 + 1;
        expectedAssets[2] = 1e18;

        checkPreviewJoinWithToken(IERC20(asset1New), 1e18, 200e18, expectedAssets, 2e18 * 2, 50e6 - 1);
    }

    function test_joinWithToken_multiple_exitWithShares() public {
        
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            address user = makeAddr(i.toString());
            users[i] = user;
            joinWithToken(user, user, asset1, 1e18 * (i + 1));
        }

        uint256[] memory expectedAssets = new uint256[](2);
        expectedAssets[0] = 120e18 + SEED_ASSET1;
        expectedAssets[1] = 6_000e6 + SEED_ASSET2;

        checkBalanceSheet(expectedAssets, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18);
        address asset2New = createToken("Asset2New_6DP", "Asset2New", 6);

        address[] memory rolloverTokens = new address[](2);
        rolloverTokens[0] = asset1New;
        rolloverTokens[1] = asset2New;

        uint256[] memory rolloverAmounts = new uint256[](2);
        rolloverAmounts[0] = 15e18;
        rolloverAmounts[1] = 40e6;

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        uint256[] memory assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 15e18;
        assetsAmounts[3] = 40e6;

        checkBalanceSheet(assetsAmounts, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

       // User 3 exit with tokens
       exitWithShares(users[2], users[2], users[2], 300e18);

        uint256[] memory expectedAssets2 = new uint256[](4);
        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18;
        expectedAssets2[3] = 40e6 - 991735;
    
        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 - 6e18, 3_000e6 + SEED_LIABILITY2 - 75e6);

        // User 3 exit with tokens
       exitWithShares(users[4], users[4], users[4], 500e18);

        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18 - 0.619834710743801652e18;
        expectedAssets2[3] = 40e6 - 991735 - 1652892;
    
        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 - 6e18 - 10e18, 3_000e6 + SEED_LIABILITY2 - 75e6 - 125e6);
    }
}

contract DynamicOrigamiTokenizedBalanceSheetVaultTestRolloverJoinWithShares is DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase {

    function test_joinWithShares_basic_fullRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        doRollover(assetTokens, assetsBalances, 0, 0);
        joinWithShares(bob, bob, 1e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 0.005e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 0.4e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 0.02e18 + SEED_LIABILITY1, 0.25e6 + SEED_LIABILITY2);
    }

    function test_joinWithShares_basic_randomRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        assetsBalances[0] = SEED_ASSET1 - 0.546431331313123121e18;
        assetsBalances[1] = SEED_ASSET2 - 24234563;
        
        doRollover(assetTokens, assetsBalances, 0, 0);
        joinWithShares(alice, alice, 1e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = (SEED_ASSET1 - 0.453568668686876879e18) + 0.005464313313131232e18;
        expectedAssets[1] = (SEED_ASSET2 - 25.765437e6) + 0.242346e6;
        expectedAssets[2] = 0.005e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 0.4e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 0.02e18 + SEED_LIABILITY1, 0.25e6 + SEED_LIABILITY2);
    }

    function test_joinWithShares_partialShare_fullRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        doRollover(assetTokens, assetsBalances, 0, 0);
        joinWithShares(bob, bob, 0.5e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 0.0025e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 0.2e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 0.01e18 + SEED_LIABILITY1, 0.125e6 + SEED_LIABILITY2);
    }

    function test_joinWithShares_partialShare_randomRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        assetsBalances[0] = SEED_ASSET1 - 0.546431331313123121e18;
        assetsBalances[1] = SEED_ASSET2 - 24234563;
        
        doRollover(assetTokens, assetsBalances, 0, 0);
        joinWithShares(alice, alice, 0.5e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = (SEED_ASSET1 - 0.453568668686876879e18) + 0.002732156656565616e18;
        expectedAssets[1] = (SEED_ASSET2 - 25.765437e6) + 0.121173e6;
        expectedAssets[2] = 0.0025e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 0.2e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(expectedAssets, 0.01e18 + SEED_LIABILITY1, 0.125e6 + SEED_LIABILITY2);
    }

    function test_joinWithShares_multiple_fullRebalance() public {
        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        doRollover(assetTokens, assetsBalances, 0, 0);

        joinWithShares(alice, alice, 12300e18);
        joinWithShares(alice, alice, 12300e18);
        
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 123e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 9840e6 + SEED_ASSET2_NEW;
        
        checkBalanceSheet(expectedAssets, 492e18 + SEED_LIABILITY1, 6150e6 + SEED_LIABILITY2);

        //note: due to rebalance share are twice less expensive
        uint256 expectedSharesMinted = (6150e18 + 6150e18) * 2;
        assertEq(expectedSharesMinted, 24600e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 * 2);
        assertEq(debt2.balanceOf(alice), 3_075e6 * 2);
    }

    function test_joinWithShares_multiple_rebalance_joinWithShares_multiple() public {
        joinWithShares(alice, alice, 6150e18);
        //100e18 + 6150e18
        //1e18 +   61.5e18
        //50e6 +   3075e6
        //2e18 +   123e18
        //25e6 +   1537.5e6

        joinWithShares(alice, alice, 6150e18); // half of debt2 from the `test_joinWithToken_basic_debt2` test
        //100e18 + 6150e18 + 6150e18
        //1e18 +   61.5e18 + 61.5e18
        //50e6 +   3075e6 +  3075e6
        //2e18 +   123e18 +  123e18
        //25e6 +   1537.5e6 +1537.5e6
        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 123e18 + SEED_ASSET1;
        expectedAssets[1] = 6_150e6 + SEED_ASSET2;
        expectedAssets[2] = 0;
        expectedAssets[3] = 0;

        checkBalanceSheet(expectedAssets, 246e18 + SEED_LIABILITY1, 3_075e6 + SEED_LIABILITY2);

        uint256 expectedSharesMinted = 6150e18 + 6150e18;
        assertEq(expectedSharesMinted, 12300e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18);
        assertEq(debt2.balanceOf(alice), 3_075e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        doRollover(assetTokens, assetsBalances, 0, 0);

        joinWithShares(alice, alice, 1525200e18); // half of asset1 from the `test_joinWithToken_basic_asset1New_fullRebalance` test
        joinWithShares(alice, alice, 12300e18); // half of debt2 from the `test_joinWithToken_basic_debt2` test

        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = SEED_ASSET1_NEW + 61.5e18 + 0.495967741935483871e18;
        expectedAssets[3] = SEED_ASSET2_NEW + 4920e6 + 39.677420e6;
        
        checkBalanceSheet(
            expectedAssets, 
            SEED_LIABILITY1 + 246e18 + 30504e18 + 246e18,
            SEED_LIABILITY2 + 3075e6 + 381300e6 + 3075e6);

        //note: due to rebalance share are twice less expensive
        expectedSharesMinted = (6150e18 + 6150e18) + 1525200e18 + 12300e18;
        assertEq(expectedSharesMinted, 1549800e18);

        assertEq(vault.totalSupply(), expectedSharesMinted + SEED_SHARES);
        assertEq(vault.balanceOf(alice), expectedSharesMinted);
        assertEq(asset1.balanceOf(alice), 0);
        assertEq(asset2.balanceOf(alice), 0);
        assertEq(debt1.balanceOf(alice), 246e18 * 2 + 30504e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 * 2 + 381300e6);
    }

    function test_joinWithToken_before_full_rebalance_exitWithShares_after_empties_vault() public {
        joinWithToken(bob, bob, asset1, 1e18);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();
        
        doRollover(assetTokens, assetsBalances, 0, 0);

        exitWithShares(bob, bob, bob, vault.maxExitWithShares(bob));

        exitWithShares(origamiMultisig, origamiMultisig, origamiMultisig, vault.maxExitWithShares(origamiMultisig));

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 0;
        expectedAssets[3] = 0;

        checkBalanceSheet(expectedAssets, 0, 0);
        assertEq(vault.totalSupply(), 0, "total supply");
    }

    function test_joinWithToken_rebalance_shareIncrease_empties_vault_withShares() public {
        joinWithToken(bob, bob, asset1, 1e18);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        doRollover(assetTokens, assetsBalances, 0, 0);

        uint256[] memory assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 0.5e18;
        assetsAmounts[3] = 40e6;

        checkBalanceSheet(assetsAmounts, 4e18, 50e6);

        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 12352242353451232;
        assetsAmounts[3] = 51231;

        increaseSharePrice(assetsAmounts, 0, 59942);

        debt2.deal(bob, 25000000 + 29971);//note: this happens due to the share decrease and the ratios change, add appropriate assertions
        
        exitWithShares(bob, bob, bob, vault.maxExitWithShares(bob));
    }
    
    function test_joinWithToken_singleToken_rollover_previewJoinWithShares() public {
        joinWithToken(bob, bob, asset1, 1.231254351265336344e18);

        address[] memory assetTokens = new address[](1);
        assetTokens[0] = address(asset1);
        uint256[] memory assetsBalances = new uint256[](1);
        assetsBalances[0] = 1.231254351265336344e18 + SEED_ASSET1;

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18);

        address[] memory rolloverTokens = new address[](1);
        rolloverTokens[0] = asset1New;

        uint256[] memory rolloverAmounts = new uint256[](1);
        rolloverAmounts[0] = 1.115627175632668172e18;//note: half the asset1 balance

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        assertEq(vault.maxJoinWithToken(address(asset1), bob), 0);

        uint256[] memory expectedAssets = new uint256[](3);
        expectedAssets[0] = 0;
        expectedAssets[1] = 50e6 + 61.562718e6;
        expectedAssets[2] = 1.115627175632668172e18;

        checkBalanceSheet(expectedAssets, 2.462508702530672688e18 + SEED_LIABILITY1, 30.781358e6 + SEED_LIABILITY2);

        expectedAssets[1] = 100e6 + 1;
        expectedAssets[2] = 1e18;

        checkPreviewJoinWithShares(200e18, expectedAssets, 2e18 * 2, 50e6 - 1);
    } 
}

contract DynamicOrigamiTokenizedBalanceSheetVaultTestRolloverExitWithToken is DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase {

    using Strings for uint256;
    function test_fullRollover_exitWithToken_basic_asset1New() public {
        joinWithToken(alice, alice, asset1, 123e18);
        exitWithToken(alice, alice, alice, asset1, 50e18);

        uint256[] memory expectedAssets = new uint256[](4);
        expectedAssets[0] = 123e18 - 50e18 + SEED_ASSET1;
        expectedAssets[1] = 6_150e6 - 2_500e6 + SEED_ASSET2;

        checkBalanceSheet(
            expectedAssets, 
            246e18 - 100e18 + SEED_LIABILITY1, 
            3_075e6 - 1_250e6 + SEED_LIABILITY2);
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18);
        assertEq(asset1.balanceOf(alice), 50e18);
        assertEq(asset2.balanceOf(alice), 2_500e6);
        assertEq(debt1.balanceOf(alice), 246e18 - 100e18);
        assertEq(debt2.balanceOf(alice), 3_075e6 - 1_250e6);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetBalances,) = vault.balanceSheet();

        (address asset1New,) = doRollover(assetTokens, assetBalances, 0, 0);

        joinWithToken(alice, alice, IERC20(asset1New), 61.5e18);

        expectedAssets[0] = 0;
        expectedAssets[1] = 0;
        expectedAssets[2] = 61.5e18 + SEED_ASSET1_NEW;
        expectedAssets[3] = 4920e6 + SEED_ASSET2_NEW;

        checkBalanceSheet(
            expectedAssets, 
            246e18 - 100e18 + SEED_LIABILITY1 + 18_204e18, 
            3_075e6 - 1_250e6 + SEED_LIABILITY2 + 227_550e6);
        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES + 910_200e18);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18 + 910_200e18);
        
        exitWithToken(alice, alice, alice, IERC20(asset1New), 25e18);

        expectedAssets[2] = 61.5e18 + SEED_ASSET1_NEW - 25e18;
        expectedAssets[3] = 4920e6 + SEED_ASSET2_NEW - 2000e6;

        checkBalanceSheet(
            expectedAssets, 
            246e18 - 100e18 + SEED_LIABILITY1 + 18_204e18 - 7400e18, 
            3_075e6 - 1_250e6 + SEED_LIABILITY2 + 227_550e6 - 92500e6);

        assertEq(vault.totalSupply(), 12_300e18 - 5_000e18 + SEED_SHARES + 910_200e18 - 370000e18);
        assertEq(vault.balanceOf(alice), 12_300e18 - 5_000e18 + 910_200e18 - 370000e18);
    }

     function test_joinWithToken_multiple_exitWithAssets() public {
        
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            address user = makeAddr(i.toString());
            users[i] = user;
            joinWithToken(user, user, asset1, 1e18 * (i + 1));
        }

        uint256[] memory expectedAssets = new uint256[](2);
        expectedAssets[0] = 120e18 + SEED_ASSET1;
        expectedAssets[1] = 6_000e6 + SEED_ASSET2;

        checkBalanceSheet(expectedAssets, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18);
        address asset2New = createToken("Asset2New_6DP", "Asset2New", 6);

        address[] memory rolloverTokens = new address[](2);
        rolloverTokens[0] = asset1New;
        rolloverTokens[1] = asset2New;

        uint256[] memory rolloverAmounts = new uint256[](2);
        rolloverAmounts[0] = 15e18;
        rolloverAmounts[1] = 40e6;

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        uint256[] memory assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 15e18;
        assetsAmounts[3] = 40e6;

        checkBalanceSheet(assetsAmounts, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        // User 3 exits with asset1
        exitWithToken(users[2], users[2], users[2], IERC20(asset1New), 0.371900826446280991e18);

        uint256[] memory expectedAssets2 = new uint256[](4);
        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18;
        expectedAssets2[3] = 40e6 - 991735;

        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 - 5999999999999999989, 3_000e6 + SEED_LIABILITY2 - 75e6);

        // User 4 exits with asset1 and asset2
        exitWithToken(users[4], users[4], users[4], IERC20(asset2New), 1652892);

        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18 - 0.619834491464143655e18;
        expectedAssets2[3] = 40e6 - 991735 - 1652892;
    
        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 - 5999999999999999989 - 9.999996462288184313e18, 3_000e6 + SEED_LIABILITY2 - 75e6 - 124999956);
    }

    function test_joinWithToken_multiple_shareIncrease_exitWithAssets() public {
        
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            address user = makeAddr(i.toString());
            users[i] = user;
            joinWithToken(user, user, asset1, 1e18 * (i + 1));
        }

        uint256[] memory expectedAssets = new uint256[](2);
        expectedAssets[0] = 120e18 + SEED_ASSET1;
        expectedAssets[1] = 6_000e6 + SEED_ASSET2;

        checkBalanceSheet(expectedAssets, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18);
        address asset2New = createToken("Asset2New_6DP", "Asset2New", 6);

        address[] memory rolloverTokens = new address[](2);
        rolloverTokens[0] = asset1New;
        rolloverTokens[1] = asset2New;

        uint256[] memory rolloverAmounts = new uint256[](2);
        rolloverAmounts[0] = 15e18;
        rolloverAmounts[1] = 40e6;

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        uint256[] memory assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 15e18;
        assetsAmounts[3] = 40e6;

        checkBalanceSheet(assetsAmounts, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 0;
        assetsAmounts[3] = 0;

        increaseSharePrice(assetsAmounts, 0.556825e18, 475839);

        debt1.deal(users[2], debt1.balanceOf(users[2]) + 13805578512396694);
        debt2.deal(users[2], debt2.balanceOf(users[2]) + 11798);

        // User 3 exits with asset1
        exitWithToken(users[2], users[2], users[2], IERC20(asset1New), 0.371900826446280991e18);

        uint256[] memory expectedAssets2 = new uint256[](4);
        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18;
        expectedAssets2[3] = 40e6 - 991735;

        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 + 0.556825e18 - 6013805578512396683, 3_000e6 + SEED_LIABILITY2 + 475839 - 75011798);

        debt1.deal(users[4], debt1.balanceOf(users[4]) + 23009289380634785);
        debt2.deal(users[4], debt2.balanceOf(users[4]) + 19619);

        // User 4 exits with asset1 and asset2
        exitWithToken(users[4], users[4], users[4], IERC20(asset2New), 1652892);

        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18 - 0.619834491464143655e18;
        expectedAssets2[3] = 40e6 - 991735 - 1652892;
    
        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 + 0.556825e18 - 6013805578512396683 - 10023005751668819099, 3_000e6 + SEED_LIABILITY2 + 475839 - 75011798 - 125019619);
    }

    function test_joinWithToken_multiple_shareIncrease_exitWithDebt() public {
        
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            address user = makeAddr(i.toString());
            users[i] = user;
            joinWithToken(user, user, asset1, 1e18 * (i + 1));
        }

        uint256[] memory expectedAssets = new uint256[](2);
        expectedAssets[0] = 120e18 + SEED_ASSET1;
        expectedAssets[1] = 6_000e6 + SEED_ASSET2;

        checkBalanceSheet(expectedAssets, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        address[] memory assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        address asset1New = createToken("Asset1New_18DP", "Asset1New", 18);
        address asset2New = createToken("Asset2New_6DP", "Asset2New", 6);

        address[] memory rolloverTokens = new address[](2);
        rolloverTokens[0] = asset1New;
        rolloverTokens[1] = asset2New;

        uint256[] memory rolloverAmounts = new uint256[](2);
        rolloverAmounts[0] = 15e18;
        rolloverAmounts[1] = 40e6;

        vault.rebalance(createRollover(rolloverTokens, rolloverAmounts, assetTokens, assetsBalances));

        uint256[] memory assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 15e18;
        assetsAmounts[3] = 40e6;

        checkBalanceSheet(assetsAmounts, 240e18 + SEED_LIABILITY1, 3_000e6 + SEED_LIABILITY2);

        assetsAmounts = new uint256[](4);
        assetsAmounts[0] = 0;
        assetsAmounts[1] = 0;
        assetsAmounts[2] = 0;
        assetsAmounts[3] = 0;

        increaseSharePrice(assetsAmounts, 0.556825e18, 475839);

        debt1.deal(users[2], debt1.balanceOf(users[2]) + 13805578512396694);
        debt2.deal(users[2], debt2.balanceOf(users[2]) + 11798);

        // User 3 exits with asset1
        exitWithToken(users[2], users[2], users[2], debt1, 6013805578512396683);

        uint256[] memory expectedAssets2 = new uint256[](4);
        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18; 
        expectedAssets2[3] = 40e6 - 991735;

        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 + 0.556825e18 - 6013805578512396683, 3_000e6 + SEED_LIABILITY2 + 475839 - 75011798);

        debt1.deal(users[4], debt1.balanceOf(users[4]) + 23009289380634785);
        debt2.deal(users[4], debt2.balanceOf(users[4]) + 19619);

        // User 4 exits with asset1 and asset2
        exitWithToken(users[4], users[4], users[4], debt2, 125019619);

        expectedAssets2[0] = 0;
        expectedAssets2[1] = 0;
        expectedAssets2[2] = 15e18 - 0.371900826446280991e18 - 0.619834493814764925e18;
        expectedAssets2[3] = 40e6 - 991735 - 1652892;
    
        checkBalanceSheet(expectedAssets2, 240e18 + SEED_LIABILITY1 + 0.556825e18 - 6013805578512396683 - 10023005789679434558, 3_000e6 + SEED_LIABILITY2 + 475839 - 75011798 - 125019619);
    }
}