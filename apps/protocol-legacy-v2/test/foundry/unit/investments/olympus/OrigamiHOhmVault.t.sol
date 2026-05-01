pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiHOhmCommon } from "test/foundry/unit/investments/olympus/OrigamiHOhmCommon.t.sol";
import { OrigamiHOhmManager } from "contracts/investments/olympus/OrigamiHOhmManager.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";

import { MockOhm } from "contracts/test/external/olympus/test/mocks/MockOhm.sol";
import { MockCoolerTreasuryBorrower } from "test/foundry/mocks/external/olympus/MockCoolerTreasuryBorrower.m.sol";
import { Kernel, Actions } from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";
import { DLGTEv1 as IDLGTEv1 } from "contracts/test/external/olympus/src/modules/DLGTE/DLGTE.v1.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { DelegateEscrowFactory } from "contracts/test/external/olympus/src/external/cooler/DelegateEscrowFactory.sol";
import { CoolerLtvOracle } from "contracts/test/external/olympus/src/policies/cooler/CoolerLtvOracle.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import { MockSUsdsToken } from "contracts/test/external/maker/MockSUsdsToken.m.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiHOhmVault } from "contracts/interfaces/investments/olympus/IOrigamiHOhmVault.sol";
import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";

import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract OrigamiHOhmVaultTestBase is OrigamiHOhmCommon {
    using OrigamiMath for uint256;

    OrigamiHOhmManager internal manager;
    TokenPrices internal tokenPrices;

    MockSUsdsToken internal sUSDS;
    MockOhm internal OHM;

    MockERC20 internal USDC;

    MonoCooler internal cooler;
    Kernel internal kernel;
    DelegateEscrowFactory internal escrowFactory;
    MockCoolerTreasuryBorrower internal treasuryBorrower;
    CoolerLtvOracle internal ltvOracle;

    address internal immutable OTHERS = makeAddr("OTHERS");


    event InKindFees(IOrigamiTokenizedBalanceSheetVault.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    function setUp() public {
        OlympusMonoCoolerDeployerLib.Contracts memory coolerContracts;
        OlympusMonoCoolerDeployerLib.deploy(coolerContracts, bytes32(0), origamiMultisig, OTHERS);

        USDS = coolerContracts.USDS;
        sUSDS = coolerContracts.sUSDS;
        OHM = coolerContracts.OHM;
        gOHM = coolerContracts.gOHM;
        cooler = coolerContracts.monoCooler;
        kernel = coolerContracts.kernel;
        escrowFactory = coolerContracts.escrowFactory;
        treasuryBorrower = MockCoolerTreasuryBorrower(address(coolerContracts.treasuryBorrower));
        ltvOracle = coolerContracts.ltvOracle;

        vm.prank(origamiMultisig);
        ltvOracle.setOriginationLtvAt(uint96(uint256(11.5e18) * OHM_PER_GOHM / 1e18), uint32(vm.getBlockTimestamp()) + 182.5 days);

        tokenPrices = new TokenPrices(30);
        tokenPrices.transferOwnership(origamiMultisig);

        deployVault();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);

        USDC = new MockERC20("USDC", "USDC", 6);
    }

    function deployVault() internal {
        vault = new OrigamiHOhmVault(
            origamiMultisig, 
            "Origami hOHM", 
            "hOHM",
            address(gOHM),
            address(tokenPrices)
        );

        manager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        manager.setExitFees(EXIT_FEE_BPS);

        tokenPrices.setTokenPriceFunction(
            address(USDS),
            abi.encodeCall(TokenPrices.scalar, (0.999e30))
        );
        tokenPrices.setTokenPriceFunction(
            address(OHM),
            abi.encodeCall(TokenPrices.scalar, (22.5e30))
        );
        tokenPrices.setTokenPriceFunction(
            address(gOHM),
            abi.encodeCall(TokenPrices.mul, (
                abi.encodeCall(TokenPrices.tokenPrice, (address(OHM))),
                abi.encodeCall(TokenPrices.scalar, (OHM_PER_GOHM * 10 ** (30-18)))
            ))
        );
        tokenPrices.setTokenPriceFunction(
            address(vault),
            abi.encodeCall(TokenPrices.tokenizedBalanceSheetTokenPrice, (address(vault)))
        );

        vm.stopPrank();
    }

    function seedDeposit(address account, uint256 maxSupply) internal {
        uint256[] memory assetAmounts = new uint256[](1);
        assetAmounts[0] = SEED_GOHM_AMOUNT;
        uint256[] memory liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = SEED_USDS_AMOUNT;

        vm.startPrank(account);
        gOHM.mint(account, assetAmounts[0]);
        gOHM.approve(address(vault), assetAmounts[0]);
        vault.seed(assetAmounts, liabilityAmounts, SEED_HOHM_SHARES, account, maxSupply);
        vm.stopPrank();
    }

    function updateDebtToken(address newDebtToken) internal {
        vm.startPrank(origamiMultisig);
        MockCoolerTreasuryBorrower newTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), newDebtToken);
        kernel.executeAction(Actions.ActivatePolicy, address(newTreasuryBorrower));
        cooler.setTreasuryBorrower(address(newTreasuryBorrower));
        kernel.executeAction(Actions.DeactivatePolicy, address(treasuryBorrower));

        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));
        manager.setDebtTokenFromCooler(address(0));
        vault.setManager(address(manager));
        (address[] memory aTokens, address[] memory lTokens) = vault.tokens();
        assertEq(aTokens.length, 1);
        assertEq(aTokens[0], address(gOHM));
        assertEq(lTokens.length, 1);
        assertEq(lTokens[0], address(newDebtToken));
        manager.setPaused(IOrigamiManagerPausable.Paused(false, false));
        vm.stopPrank();
    }

    function checkBalanceSheet(uint256 a1, uint256 l1) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = vault.balanceSheet();
        assertEq(assets.length, 1, "balanceSheet::assets::length");
        assertEq(assets[0], a1, "balanceSheet::assets[0]");
        assertEq(liabilities.length, 1, "balanceSheet::liabilities::length");
        assertEq(liabilities[0], l1, "balanceSheet::liabilities[0]");
    }

    function checkConvertFromToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256 expectedAsset1,
        uint256 expectedLiability1
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.convertFromToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "convertFromToken::shares");
        assertEq(assets.length, 1, "convertFromToken::assets::length");
        assertEq(assets[0], expectedAsset1, "convertFromToken::assets[0]");
        assertEq(liabilities.length, 1, "convertFromToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "convertFromToken::liabilities[0]");
    }

    function checkConvertFromShares(uint256 shares, uint256 a1, uint256 l1) internal view {
        (uint256[] memory assets, uint256[] memory liabilities) = vault.convertFromShares(shares);
        assertEq(assets.length, 1, "convertFromShares::assets::length");
        assertEq(assets[0], a1, "convertFromShares::assets[0]");
        assertEq(liabilities.length, 1, "convertFromShares::liabilities::length");
        assertEq(liabilities[0], l1, "convertFromShares::liabilities[0]");
    }

    function checkPreviewJoinWithShares(
        uint256 shares,
        uint256 expectedAsset1,
        uint256 expectedLiability1
    ) internal view {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithShares(shares);

        assertEq(assets.length, 1, "previewJoinWithShares::assets::length");
        assertEq(assets[0], expectedAsset1, "previewJoinWithShares::assets[0]");
        assertEq(liabilities.length, 1, "previewJoinWithShares::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewJoinWithShares::liabilities[0]");
    }

    function checkPreviewJoinWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256 expectedAsset1,
        uint256 expectedLiability1
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewJoinWithToken::shares");
        assertEq(assets.length, 1, "previewJoinWithToken::assets::length");
        assertEq(assets[0], expectedAsset1, "previewJoinWithToken::assets[0]");
        assertEq(liabilities.length, 1, "previewJoinWithToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewJoinWithToken::liabilities[0]");
    }

    function checkPreviewExitWithShares(
        uint256 shares,
        uint256 expectedAsset1,
        uint256 expectedLiability1
    ) internal view {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithShares(shares);

        assertEq(assets.length, 1, "previewExitWithShares::assets::length");
        assertEq(assets[0], expectedAsset1, "previewExitWithShares::assets[0]");
        assertEq(liabilities.length, 1, "previewExitWithShares::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewExitWithShares::liabilities[0]");
    }

    function checkPreviewExitWithToken(
        IERC20 token,
        uint256 tokenAmount,
        uint256 expectedShares,
        uint256 expectedAsset1,
        uint256 expectedLiability1
    ) internal view {
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = vault.previewExitWithToken(address(token), tokenAmount);

        assertEq(shares, expectedShares, "previewExitWithToken::shares");
        assertEq(assets.length, 1, "previewExitWithToken::assets::length");
        assertEq(assets[0], expectedAsset1, "previewExitWithToken::assets[0]");
        assertEq(liabilities.length, 1, "previewExitWithToken::liabilities::length");
        assertEq(liabilities[0], expectedLiability1, "previewExitWithToken::liabilities[0]");
    }

    function joinWithToken(
        address account,
        IERC20 token,
        uint256 tokenAmount,
        address receiver
    ) internal returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        (
            uint256 previewShares,
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewJoinWithToken(address(token), tokenAmount);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, previewAssets, previewLiabilities);

        vm.startPrank(account);

        gOHM.mint(account, previewAssets[0]);
        gOHM.approve(address(vault), previewAssets[0]);

        {
            (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
            uint256 expectedFeeAmout = sharesNoFees - previewShares;
            assertEq(expectedFeeAmout, 0); // Expect no fees
        }

        vm.expectEmit(address(vault));
        emit Join(account, receiver, previewAssets, previewLiabilities, previewShares);
        (shares, assets, liabilities) = vault.joinWithToken(address(token), tokenAmount, receiver);
        vm.stopPrank();

        assertEq(shares, previewShares, "joinWithToken::shares");
        assertEq(assets.length, previewAssets.length, "joinWithToken::assets.length");
        assertEq(assets[0], previewAssets[0], "joinWithToken::assets[0]");
        assertEq(liabilities.length, previewLiabilities.length, "joinWithToken::liabilities.length");
        assertEq(liabilities[0], previewLiabilities[0], "joinWithToken::liabilities[0]");

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, assets, liabilities);
    }

    function joinWithShares(address account, uint256 shares, address receiver) internal {
        (
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewJoinWithShares(shares);

        vm.startPrank(account);
        gOHM.mint(account, previewAssets[0]);
        gOHM.approve(address(vault), previewAssets[0]);
        
        vm.expectEmit(address(vault));
        emit Join(account, receiver, previewAssets, previewLiabilities, shares);
        (
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.joinWithShares(shares, receiver);
        vm.stopPrank();

        assertEq(actualAssets.length, previewAssets.length);
        assertEq(actualAssets[0], previewAssets[0]);
        assertEq(actualLiabilities.length, previewLiabilities.length);
        assertEq(actualLiabilities[0], previewLiabilities[0]);
    }

    function exitWithToken(address caller, address sharesOwner, IERC20 token, uint256 tokenAmount, address receiver) internal {
        exitWithToken(caller, sharesOwner, token, tokenAmount, receiver, USDS);
    }

    function exitWithToken(address caller, address sharesOwner, IERC20 token, uint256 tokenAmount, address receiver, IERC20 debtToken) internal {
        (
            uint256 previewShares,
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewExitWithToken(address(token), tokenAmount);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, previewAssets, previewLiabilities);

        // Assume the caller already has the debt tokens to repay.
        vm.startPrank(caller);
        debtToken.approve(address(vault), previewLiabilities[0]);
        
        {
            (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
            uint256 expectedFeeAmout = sharesNoFees > previewShares ? sharesNoFees - previewShares : 0;
            if (expectedFeeAmout > 0) {
                vm.expectEmit(address(vault));
                emit InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.EXIT_FEE, 
                    EXIT_FEE_BPS,
                    expectedFeeAmout
                );
            }
        }

        vm.expectEmit(address(vault));
        emit Exit(caller, receiver, sharesOwner, previewAssets, previewLiabilities, previewShares);
        (
            uint256 actualShares,
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithToken(address(token), tokenAmount, receiver, sharesOwner);
        vm.stopPrank();

        assertEq(actualShares, previewShares);
        assertEq(actualAssets.length, previewAssets.length);
        assertEq(actualAssets[0], previewAssets[0]);
        assertEq(actualLiabilities.length, previewLiabilities.length);
        assertEq(actualLiabilities[0], previewLiabilities[0]);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, actualAssets, actualLiabilities);
    }

    function exitWithShares(address caller, address sharesOwner, uint256 shares, address receiver) internal {
        (
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewExitWithShares(shares);

        // Assume the caller already has the debt tokens to repay.
        vm.startPrank(caller);
        USDS.approve(address(vault), previewLiabilities[0]);
        
        {
            (, uint256 expectedFeeAmout) = shares.splitSubtractBps(EXIT_FEE_BPS, OrigamiMath.Rounding.ROUND_DOWN);
            if (expectedFeeAmout > 0) {
                vm.expectEmit(address(vault));
                emit InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.EXIT_FEE, 
                    EXIT_FEE_BPS,
                    expectedFeeAmout
                );
            }
        }

        vm.expectEmit(address(vault));
        emit Exit(caller, receiver, sharesOwner, previewAssets, previewLiabilities, shares);
        (
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = vault.exitWithShares(shares, receiver, sharesOwner);
        vm.stopPrank();

        assertEq(actualAssets.length, previewAssets.length);
        assertEq(actualAssets[0], previewAssets[0]);
        assertEq(actualLiabilities.length, previewLiabilities.length);
        assertEq(actualLiabilities[0], previewLiabilities[0]);
    }

    function check_accountDelegationBalances(
        address account, 
        uint256 expectedTotalCollateral,
        address expectedDelegate,
        uint256 expectedDelegatedCollateral
    ) internal view {
        (
            uint256 totalCollateral,
            address delegateAddress,
            uint256 delegatedCollateral
        ) = vault.accountDelegationBalances(account);
        assertEq(totalCollateral, expectedTotalCollateral, "accountDelegationBalances::totalCollateral");
        assertEq(delegateAddress, expectedDelegate, "accountDelegationBalances::delegateAddress");
        assertEq(delegatedCollateral, expectedDelegatedCollateral, "accountDelegationBalances::delegatedCollateral");
    }
}

contract OrigamiHOhmVaultTestAdmin is OrigamiHOhmVaultTestBase {
    event TokenPricesSet(address indexed tokenPrices);
    event ManagerSet(address indexed manager);
    event DebtTokenSet(address indexed debtToken);
    
    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami hOHM");
        assertEq(vault.symbol(), "hOHM");
        assertEq(vault.decimals(), 18);
        
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES); // No fees taken on the seed

        checkBalanceSheet(SEED_GOHM_AMOUNT, SEED_USDS_AMOUNT);

        checkConvertFromToken(gOHM, SEED_GOHM_AMOUNT*2, SEED_HOHM_SHARES*2, SEED_GOHM_AMOUNT*2, SEED_USDS_AMOUNT*2);
        checkConvertFromToken(USDS, SEED_USDS_AMOUNT*2, SEED_HOHM_SHARES*2, SEED_GOHM_AMOUNT*2, SEED_USDS_AMOUNT*2);

        checkConvertFromShares(SEED_HOHM_SHARES*100, SEED_GOHM_AMOUNT*100, SEED_USDS_AMOUNT*100);
        checkConvertFromShares(1e18, 0.000003714158371712e18, 0.011e18);

        assertEq(vault.joinFeeBps(), 0);
        assertEq(vault.exitFeeBps(), EXIT_FEE_BPS);

        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);

        assertEq(address(vault.collateralToken()), address(gOHM));
        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(address(vault.debtToken()), address(USDS));
        assertEq(address(vault.manager()), address(manager));

        // 5bps exit fees
        checkPreviewJoinWithShares(1e18, 0.000003714158371713e18, 0.011e18);
        checkPreviewJoinWithToken(gOHM, 1e18, 269_240e18, 1e18, 2_961.64e18);
        checkPreviewJoinWithToken(USDS, 1e18, 90.909090909090909091e18, 0.000337650761064816e18, 1e18);
        checkPreviewExitWithShares(1e18, 0.000003677016787995e18, 0.01089e18);
        checkPreviewExitWithToken(gOHM, 1e18, 271_959.595959595959595960e18, 1e18, 2_961.64e18);
        checkPreviewExitWithToken(USDS, 1e18, 91.827364554637281910e18, 0.000337650761064815e18, 1e18);

        // No max total supply
        assertEq(vault.maxJoinWithToken(address(gOHM), alice), type(uint256).max);
        assertEq(vault.maxJoinWithToken(address(USDS), alice), type(uint256).max);
        assertEq(vault.maxJoinWithShares(alice), type(uint256).max);
        assertEq(vault.maxExitWithShares(alice), 0);
        assertEq(vault.maxExitWithToken(address(gOHM), alice), 0);
        assertEq(vault.maxExitWithToken(address(USDS), alice), 0);
    }

    function test_seed() public {
        deployVault();
        assertEq(SEED_HOHM_SHARES, 2_692_400e18);
        assertEq(SEED_USDS_AMOUNT, 29_616.4e18);
        assertEq(SEED_GOHM_AMOUNT, 10e18);
        
        vm.startPrank(origamiMultisig);
        uint256[] memory assetAmounts = new uint256[](1);
        assetAmounts[0] = SEED_GOHM_AMOUNT; // gOHM [18dp]
        uint256[] memory liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = SEED_USDS_AMOUNT; // USDS [18dp]

        gOHM.mint(origamiMultisig, assetAmounts[0]);
        gOHM.approve(address(vault), assetAmounts[0]);

        vault.seed(
            assetAmounts, 
            liabilityAmounts, 
            SEED_HOHM_SHARES,
            origamiMultisig,
            3_333_333e18
        );
        checkBalanceSheet(SEED_GOHM_AMOUNT, SEED_USDS_AMOUNT);
        assertEq(vault.maxTotalSupply(), 3_333_333e18);
        
        // A join is at the same ratio
        (
            uint256 shares,
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = joinWithToken(alice, gOHM, SEED_GOHM_AMOUNT/10, alice);
        checkBalanceSheet(
            SEED_GOHM_AMOUNT/10 + SEED_GOHM_AMOUNT,
            SEED_USDS_AMOUNT/10 + SEED_USDS_AMOUNT
        );

        assertEq(shares, SEED_HOHM_SHARES/10);
        assertEq(assets.length, 1);
        assertEq(assets[0], SEED_GOHM_AMOUNT/10);
        assertEq(liabilities.length, 1);
        assertEq(liabilities[0], SEED_USDS_AMOUNT/10);

        assertEq(gOHM.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(alice), liabilities[0]);
        assertEq(vault.balanceOf(alice), shares);
    }


    function test_setManager_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setManager(address(0));
    }

    function test_setManager_sameManager() public {
        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.debtToken()), address(USDS));
    }

    function test_setManager_newManager() public {
        OrigamiHOhmManager newManager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit ManagerSet(address(newManager));
        vault.setManager(address(newManager));
        assertEq(address(vault.manager()), address(newManager));
        assertEq(address(vault.debtToken()), address(USDS));
    }

    function test_setManager_newDebtToken() public {
        vm.startPrank(origamiMultisig);
        MockCoolerTreasuryBorrower newTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), address(USDC));
        cooler.setTreasuryBorrower(address(newTreasuryBorrower));
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));
        manager.setDebtTokenFromCooler(address(0));

        vm.expectEmit(address(vault));
        emit DebtTokenSet(address(USDC));
        vault.setManager(address(manager));

        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.debtToken()), address(USDC));
    }

    function test_setTokenPrices_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setTokenPrices(address(0));
    }

    function test_setTokenPrices_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit TokenPricesSet(alice);
        vault.setTokenPrices(alice);
        assertEq(address(vault.tokenPrices()), alice);
    }
}

contract OrigamiHOhmVaultTestAccess is OrigamiHOhmVaultTestBase {
    function test_setManager_access() public {
        expectElevatedAccess();
        vault.setManager(alice);
    }

    function test_setTokenPrices_access() public {
        expectElevatedAccess();
        vault.setTokenPrices(alice);
    }
}

contract OrigamiHOhmVaultTestViews is OrigamiHOhmVaultTestBase {
    function test_assetTokens() public view {
        address[] memory tokens = vault.assetTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(gOHM));
    }

    function test_liabilityTokens_default() public {
        address[] memory tokens = vault.liabilityTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(USDS));

        vm.startPrank(origamiMultisig);
    }

    function test_liabilityTokens_updated() public {
        // Update the cooler debt token to be USDC instead of USDS
        updateDebtToken(address(USDC));

        address[] memory tokens = vault.liabilityTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(USDC));
    }

    function test_isBalanceSheetToken_default() public view {
        (bool isAsset, bool isLiability) = vault.isBalanceSheetToken(address(USDC));
        assertFalse(isAsset);
        assertFalse(isLiability);

        (isAsset, isLiability) = vault.isBalanceSheetToken(address(gOHM));
        assertTrue(isAsset);
        assertFalse(isLiability);

        (isAsset, isLiability) = vault.isBalanceSheetToken(address(USDS));
        assertFalse(isAsset);
        assertTrue(isLiability);
    }

    function test_isBalanceSheetToken_updated() public {
        updateDebtToken(address(USDC));

        (bool isAsset, bool isLiability) = vault.isBalanceSheetToken(address(USDC));
        assertFalse(isAsset);
        assertTrue(isLiability);

        (isAsset, isLiability) = vault.isBalanceSheetToken(address(gOHM));
        assertTrue(isAsset);
        assertFalse(isLiability);

        (isAsset, isLiability) = vault.isBalanceSheetToken(address(USDS));
        assertFalse(isAsset);
        assertFalse(isLiability);
    }

    function test_supportsInterface() public view {
        assertEq(vault.supportsInterface(type(IOrigamiHOhmVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(IOrigamiTokenizedBalanceSheetVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(ITokenizedBalanceSheetVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(vault.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC4626).interfaceId), false);
    }

    function test_token_prices_positive() public view {
        // Shares == 2,692,400
        // 29_616.4 USDS @ 0.999 USDS/USD = 29,586.7836 USD
        // 10 gOHM @ 269.24 gOHM/OHM * 22.5 OHM/USD = 60,579 USD

        // 30,992.2164 / 2,692,400 = 0.011511
        assertEq(tokenPrices.tokenPrice(address(vault)), 0.0115109999999941248e30);
    }

    function test_token_prices_negative() public {
        // Floored at zero if the liabilities are worth more than the debt.
        vm.prank(origamiMultisig);
        tokenPrices.setTokenPriceFunction(
            address(gOHM),
            abi.encodeCall(TokenPrices.mul, (
                abi.encodeCall(TokenPrices.tokenPrice, (address(OHM))),
                abi.encodeCall(TokenPrices.scalar, 1e30)
            ))
        );
        assertEq(tokenPrices.tokenPrice(address(vault)), 0);
    }
}

contract OrigamiHOhmVaultTestJoinAndExit is OrigamiHOhmVaultTestBase {    
    function test_join_fail_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(gOHM), 10e18, 0));
        vault.joinWithToken(address(gOHM), 10e18, alice);
    }
    
    function test_exit_fail_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        joinWithToken(alice, gOHM, 10e18, alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(gOHM), 1e18, 0));
        vault.exitWithToken(address(gOHM), 1e18, alice, alice);
    }

    function test_joinWithToken_gohm() public {
        uint256 gohmJoinAmount = 33e18;
        uint256 usdsJoinAmount = 97_734.12e18;
        uint256 sharesAmount = 8_884_920e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, bob);

        checkBalanceSheet(SEED_GOHM_AMOUNT + gohmJoinAmount, SEED_USDS_AMOUNT + usdsJoinAmount);
        assertEq(USDS.balanceOf(bob), usdsJoinAmount);

        assertEq(gOHM.balanceOf(alice), 0);
        assertEq(gOHM.balanceOf(address(vault)), 0);
        assertEq(gOHM.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES + sharesAmount);
    }

    function test_joinWithToken_usds() public {
        uint256 gohmJoinAmount = 33e18;
        uint256 usdsJoinAmount = 97_734.12e18;
        uint256 sharesAmount = 8_884_920e18;
        joinWithToken(alice, USDS, usdsJoinAmount, bob);

        checkBalanceSheet(SEED_GOHM_AMOUNT + gohmJoinAmount, SEED_USDS_AMOUNT + usdsJoinAmount);
        assertEq(USDS.balanceOf(bob), usdsJoinAmount);

        assertEq(gOHM.balanceOf(alice), 0);
        assertEq(gOHM.balanceOf(address(vault)), 0);
        assertEq(gOHM.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES + sharesAmount);
    }

    function test_joinWithToken_other() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, address(USDC), 1e18, 0));
        vault.joinWithToken(address(USDC), 1e18, alice);
    }

    function test_joinWithShares() public {
        uint256 gohmJoinAmount = 33e18;
        uint256 usdsJoinAmount = 97_734.12e18;
        uint256 sharesAmount = 8_884_920e18;
        joinWithShares(alice, sharesAmount, bob);

        checkBalanceSheet(SEED_GOHM_AMOUNT + gohmJoinAmount, SEED_USDS_AMOUNT + usdsJoinAmount);
        assertEq(USDS.balanceOf(bob), usdsJoinAmount);

        assertEq(gOHM.balanceOf(alice), 0);
        assertEq(gOHM.balanceOf(address(vault)), 0);
        assertEq(gOHM.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES + sharesAmount);
    }

    function test_exitWithToken_gohm() public {
        uint256 gohmJoinAmount = 33e18;
        uint256 usdsJoinAmount = 97_734.12e18;
        uint256 sharesJoinAmount = 8_884_920e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 gohmExitAmount = 3.712301292527113356e18;
        uint256 usdsExitAmount = 10_994.499999999999999664e18;
        uint256 sharesExitAmount = 1_009_595.959595959595928728e18;
        exitWithToken(bob, bob, gOHM, gohmExitAmount, bob);

        checkBalanceSheet(SEED_GOHM_AMOUNT + gohmJoinAmount - gohmExitAmount, SEED_USDS_AMOUNT + usdsJoinAmount - usdsExitAmount);
        assertEq(USDS.balanceOf(bob), usdsJoinAmount - usdsExitAmount);

        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES + sharesJoinAmount - sharesExitAmount);
    }

    function test_exitWithToken_usds() public {
        uint256 gohmJoinAmount = 33e18;
        uint256 usdsJoinAmount = 97_734.12e18;
        uint256 sharesJoinAmount = 8_884_920e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 gohmExitAmount = 3.712301292527113356e18;
        uint256 usdsExitAmount = 10_994.499999999999999664e18;
        uint256 sharesExitAmount = 1_009_595.959595959595928743e18;
        exitWithToken(bob, bob, USDS, usdsExitAmount, bob);

        checkBalanceSheet(SEED_GOHM_AMOUNT + gohmJoinAmount - gohmExitAmount, SEED_USDS_AMOUNT + usdsJoinAmount - usdsExitAmount);
        assertEq(USDS.balanceOf(bob), usdsJoinAmount - usdsExitAmount);

        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount + 1);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES + sharesJoinAmount - sharesExitAmount + 1);
    }


    function test_exitWithToken_other() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, address(USDC), 1e18, 0));
        vault.exitWithToken(address(USDC), 1e18, alice, alice);
    }

    function test_exitWithShares() public {
        uint256 gohmJoinAmount = 33e18;
        uint256 usdsJoinAmount = 97_734.12e18;
        uint256 sharesJoinAmount = 8_884_920e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 gohmExitAmount = 3.677016787995840142e18;
        uint256 usdsExitAmount = 10_890e18;
        uint256 sharesExitAmount = 1_000_000e18;
        exitWithShares(bob, bob, sharesExitAmount, bob);

        checkBalanceSheet(SEED_GOHM_AMOUNT + gohmJoinAmount - gohmExitAmount, SEED_USDS_AMOUNT + usdsJoinAmount - usdsExitAmount);
        assertEq(USDS.balanceOf(bob), usdsJoinAmount - usdsExitAmount);

        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_HOHM_SHARES + sharesJoinAmount - sharesExitAmount);
    }
}

contract OrigamiHOhmVaultTestDelegations is OrigamiHOhmVaultTestBase {
    function test_delegateVotingPower_self() public {
        uint256 gohmJoinAmount = 100e18;
        (, uint256[] memory assets, ) = joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        check_accountDelegationBalances(alice, gohmJoinAmount, address(0), 0);

        vm.startPrank(alice);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, alice, int256(assets[0]));
        vault.delegateVotingPower(alice);

        check_accountDelegationBalances(alice, gohmJoinAmount, alice, gohmJoinAmount);
    }

    function test_delegateVotingPower_other() public {
        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        check_accountDelegationBalances(alice, gohmJoinAmount, address(0), 0);
        check_accountDelegationBalances(bob, gohmJoinAmount, address(0), 0);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vault.delegateVotingPower(alice);

        check_accountDelegationBalances(bob, gohmJoinAmount, alice, gohmJoinAmount);
    }

    function test_delegateVotingPower_removeDelegate() public {
        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        check_accountDelegationBalances(alice, gohmJoinAmount, address(0), 0);
        check_accountDelegationBalances(bob, gohmJoinAmount, address(0), 0);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vault.delegateVotingPower(alice);

        check_accountDelegationBalances(bob, gohmJoinAmount, alice, gohmJoinAmount);

        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, -int256(gohmJoinAmount));
        vault.delegateVotingPower(address(0));
        check_accountDelegationBalances(bob, gohmJoinAmount, address(0), 0);
    }

    function test_delegateVotingPower_zeroSupply() public {
        deployVault();

        // A noop
        vm.startPrank(bob);
        vault.delegateVotingPower(alice);
        check_accountDelegationBalances(bob, 0, alice, 0);
    }

    function test_delegateVotingPower_noUpfrontCollateral() public {    
        check_accountDelegationBalances(bob, 0, address(0), 0);   
        vm.startPrank(bob);
        vault.delegateVotingPower(alice);

        check_accountDelegationBalances(bob, 0, alice, 0);   

        // now a fresh join will delegate
        uint256 gohmJoinAmount = 100e18;
        gOHM.mint(bob, gohmJoinAmount);
        gOHM.approve(address(vault), gohmJoinAmount);

        (
            uint256 previewShares,
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewJoinWithToken(address(gOHM), gohmJoinAmount);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vm.expectEmit(address(vault));
        emit Join(bob, bob, previewAssets, previewLiabilities, previewShares);
        vault.joinWithToken(address(gOHM), gohmJoinAmount, bob);

        check_accountDelegationBalances(bob, gohmJoinAmount, alice, gohmJoinAmount);
    }

    function test_delegateVotingPower_ohmBacking_increaseAndReDelegate() public {
        uint256 expectedTotalSupply = SEED_HOHM_SHARES;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        expectedTotalSupply += 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        expectedTotalSupply += 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vault.delegateVotingPower(alice);

        uint256 addedCollateral = 10e18; 
        {
            vm.startPrank(address(manager));
            gOHM.mint(address(manager), addedCollateral);
            cooler.addCollateral(uint128(addedCollateral), address(manager), new IDLGTEv1.DelegationRequest[](0));
        }

        assertEq(vault.totalSupply(), expectedTotalSupply);
        uint256 expectedExtraCollateral = addedCollateral * 26_924_000e18 / expectedTotalSupply;
        assertEq(expectedExtraCollateral, 4.761904761904761904e18);
        check_accountDelegationBalances(bob, gohmJoinAmount + expectedExtraCollateral, alice, gohmJoinAmount);

        // Bob sync's themselves
        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(expectedExtraCollateral));
        vault.delegateVotingPower(alice);

        check_accountDelegationBalances(bob, gohmJoinAmount + expectedExtraCollateral, alice, gohmJoinAmount + expectedExtraCollateral);
    }

    function test_delegateVotingPower_ohmBacking_increaseAndSync() public {
        uint256 expectedTotalSupply = SEED_HOHM_SHARES;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        expectedTotalSupply += 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        expectedTotalSupply += 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vault.delegateVotingPower(alice);

        uint256 addedCollateral = 10e18; 
        {
            vm.startPrank(address(manager));
            gOHM.mint(address(manager), addedCollateral);
            cooler.addCollateral(uint128(addedCollateral), address(manager), new IDLGTEv1.DelegationRequest[](0));
        }

        assertEq(vault.totalSupply(), expectedTotalSupply);
        uint256 expectedExtraCollateral = addedCollateral * 26_924_000e18 / expectedTotalSupply;
        assertEq(expectedExtraCollateral, 4.761904761904761904e18);       
        check_accountDelegationBalances(bob, gohmJoinAmount + expectedExtraCollateral, alice, gohmJoinAmount);

        // Alice sync's Bob to the existing delegate
        vm.startPrank(alice);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(expectedExtraCollateral));
        vault.syncDelegation(bob);

        check_accountDelegationBalances(bob, gohmJoinAmount + expectedExtraCollateral, alice, gohmJoinAmount + expectedExtraCollateral);
    }

    function test_delegateVotingPower_ohmBacking_increaseAndJoinAgain() public {
        uint256 expectedTotalSupply = SEED_HOHM_SHARES;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        expectedTotalSupply += 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        expectedTotalSupply += 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vault.delegateVotingPower(alice);

        uint256 addedCollateral = 10e18; 
        {
            vm.startPrank(address(manager));
            gOHM.mint(address(manager), addedCollateral);
            cooler.addCollateral(uint128(addedCollateral), address(manager), new IDLGTEv1.DelegationRequest[](0));
        }

        assertEq(vault.totalSupply(), expectedTotalSupply);
        uint256 expectedExtraCollateral = addedCollateral * 26_924_000e18 / expectedTotalSupply;
        assertEq(expectedExtraCollateral, 4.761904761904761904e18);       
        check_accountDelegationBalances(bob, gohmJoinAmount + expectedExtraCollateral, alice, gohmJoinAmount);
        check_accountDelegationBalances(alice, gohmJoinAmount + expectedExtraCollateral, address(0), 0);

        // Alice joins more sending to bob
        joinWithToken(alice, gOHM, gohmJoinAmount, bob);

        check_accountDelegationBalances(bob, 2*gohmJoinAmount + expectedExtraCollateral, alice, 2*gohmJoinAmount + expectedExtraCollateral);
        check_accountDelegationBalances(alice, gohmJoinAmount + expectedExtraCollateral, address(0), 0);
    }

    function test_delegateVotingPower_ohmBacking_increaseThenExit() public {
        uint256 expectedTotalSupply = SEED_HOHM_SHARES;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        uint256 expectedSharesMinted = 26_924_000e18;
        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        expectedTotalSupply += expectedSharesMinted;
        assertEq(vault.totalSupply(), expectedTotalSupply);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        expectedTotalSupply += expectedSharesMinted;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        assertEq(manager.collateralTokenBalance(), 2*gohmJoinAmount+SEED_GOHM_AMOUNT);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmJoinAmount));
        vault.delegateVotingPower(alice);

        uint256 addedCollateral = 10e18; 
        {
            vm.startPrank(address(manager));
            gOHM.mint(address(manager), addedCollateral);
            cooler.addCollateral(uint128(addedCollateral), address(manager), new IDLGTEv1.DelegationRequest[](0));
        }

        uint256 totalCollateral = 2*gohmJoinAmount + SEED_GOHM_AMOUNT + addedCollateral;
        assertEq(manager.collateralTokenBalance(), 2*gohmJoinAmount + SEED_GOHM_AMOUNT + addedCollateral);

        assertEq(vault.totalSupply(), expectedTotalSupply);
        uint256 expectedExtraCollateral = addedCollateral * expectedSharesMinted / expectedTotalSupply;
        assertEq(expectedExtraCollateral, 4.761904761904761904e18);       
        check_accountDelegationBalances(bob, gohmJoinAmount + expectedExtraCollateral, alice, gohmJoinAmount);
        check_accountDelegationBalances(alice, gohmJoinAmount + expectedExtraCollateral, address(0), 0);

        // Bob exits
        exitWithToken(bob, bob, gOHM, gohmJoinAmount/2, bob);
        uint256 expectedSharesBurned = 12_979_889.807162534435261709e18;
        assertEq(vault.balanceOf(bob), expectedSharesMinted - expectedSharesBurned);

        totalCollateral -= gohmJoinAmount/2;
        assertEq(manager.collateralTokenBalance(), totalCollateral);

        // 1% fees which burn the total supply. Means bob got hit with some fees in gOHM terms, and Alice earned them
        // Maths for that checked in other tests.
        uint256 aliceTotalCollateral = gohmJoinAmount + expectedExtraCollateral + 0.312163005845961746e18;
        check_accountDelegationBalances(alice, aliceTotalCollateral, address(0), 0);
        uint256 bobTotalCollateral = gohmJoinAmount + expectedExtraCollateral - gohmJoinAmount/2 - 0.343379306430557920e18;
        check_accountDelegationBalances(bob, bobTotalCollateral, alice, bobTotalCollateral);

        // The only spare should be from the seed
        uint256 seedTotalCollateral = SEED_GOHM_AMOUNT + 0.507406776775072365e18;
        check_accountDelegationBalances(origamiMultisig, seedTotalCollateral, address(0), 0);

        // Just 1 for rounding
        assertEq(manager.collateralTokenBalance(), aliceTotalCollateral + bobTotalCollateral + seedTotalCollateral + 1);
    }

    function test_delegateVotingPower_reduceOnExit() public {
        uint256 expectedTotalSupply = SEED_HOHM_SHARES;
        uint256 gohmJoinAmount = 100e18;
        joinWithToken(alice, gOHM, gohmJoinAmount, alice);
        joinWithToken(bob, gOHM, gohmJoinAmount, bob);
        expectedTotalSupply += 2 * 26_924_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);
        
        check_accountDelegationBalances(alice, gohmJoinAmount, address(0), 0);

        vm.startPrank(alice);
        vault.delegateVotingPower(alice);

        uint256 gohmExitAmount = 33e18;
        USDS.approve(address(vault), type(uint256).max);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, alice, int256(66.792452830188679245e18) - int256(gohmJoinAmount)); // see maths below
        vault.exitWithToken(address(gOHM), gohmExitAmount, alice, alice);

        expectedTotalSupply -= 8_974_666.666666666666666667e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);

        assertEq(manager.collateralTokenBalance(), SEED_GOHM_AMOUNT + 2*gohmJoinAmount - gohmExitAmount);
        assertEq(vault.balanceOf(alice), 26_924_000e18-8_974_666.666666666666666667e18);
        uint256 expectedAliceCollateral = manager.collateralTokenBalance() * vault.balanceOf(alice) / expectedTotalSupply;
        assertEq(expectedAliceCollateral, 66.792452830188679245e18); // slightly less than the 67, because of fees
        
        check_accountDelegationBalances(alice, expectedAliceCollateral, alice, expectedAliceCollateral);

        // No change after a forced sync
        vault.syncDelegation(alice);
        check_accountDelegationBalances(alice, expectedAliceCollateral, alice, expectedAliceCollateral);

        // Alice could exit for that amount, minus the exit fee%
        assertEq(vault.maxExitWithToken(address(gOHM), alice), expectedAliceCollateral*(10_000-EXIT_FEE_BPS)/10_000);
    }

    function test_transfer_toSelf_noDelegation() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(alice);
        vault.transfer(alice, 10_000_000e18);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
    }

    function test_transfer_zeroAmount() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(alice);
        vault.transfer(bob, 0); // No change (same as toSelf)
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
    }

    function test_transfer_toOther_noDelegation() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(alice);
        vault.transfer(bob, 10_000_000e18);
        assertEq(vault.balanceOf(alice), aliceExpectedShares-10_000_000e18);
        assertEq(vault.balanceOf(bob), bobExpectedShares+10_000_000e18);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
    }

    function test_transfer_toSelf_withDelegation() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(alice);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, alice, int256(gohmAliceJoinAmount));
        vault.delegateVotingPower(alice);
        check_accountDelegationBalances(alice, gohmAliceJoinAmount, alice, gohmAliceJoinAmount);
        check_accountDelegationBalances(bob, gohmBobJoinAmount, address(0), 0);

        vm.startPrank(alice);
        vault.transfer(alice, 10_000_000e18);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
        check_accountDelegationBalances(alice, gohmAliceJoinAmount, alice, gohmAliceJoinAmount);
        check_accountDelegationBalances(bob, gohmBobJoinAmount, address(0), 0);
    }

    function test_transfer_toOther_withDelegationFrom_noDelegationTo() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(alice);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, alice, int256(gohmAliceJoinAmount));
        vault.delegateVotingPower(alice);
        check_accountDelegationBalances(alice, gohmAliceJoinAmount, alice, gohmAliceJoinAmount);
        check_accountDelegationBalances(bob, gohmBobJoinAmount, address(0), 0);

        vm.startPrank(alice);
        vault.transfer(bob, 10_000_000e18);
        assertEq(vault.balanceOf(alice), aliceExpectedShares-10_000_000e18);
        assertEq(vault.balanceOf(bob), bobExpectedShares+10_000_000e18);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
        uint256 expectedGohmMoved = 37.141583717129698411e18;
        check_accountDelegationBalances(alice, gohmAliceJoinAmount-expectedGohmMoved, alice, gohmAliceJoinAmount-expectedGohmMoved);
        check_accountDelegationBalances(bob, gohmBobJoinAmount+expectedGohmMoved-1, address(0), 0); // small rounding effect

        address escrow = address(escrowFactory.escrowFor(alice));
        assertEq(gOHM.balanceOf(escrow), gohmAliceJoinAmount-expectedGohmMoved);
        escrow = address(escrowFactory.escrowFor(bob));
        assertEq(gOHM.balanceOf(escrow), 0);
    }

    function test_transfer_toOther_noDelegationFrom_withDelegationTo() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmBobJoinAmount));
        vault.delegateVotingPower(alice);
        check_accountDelegationBalances(alice, gohmAliceJoinAmount, address(0), 0);
        check_accountDelegationBalances(bob, gohmBobJoinAmount, alice, gohmBobJoinAmount);

        vm.startPrank(alice);
        vault.transfer(bob, 10_000_000e18);
        assertEq(vault.balanceOf(alice), aliceExpectedShares-10_000_000e18);
        assertEq(vault.balanceOf(bob), bobExpectedShares+10_000_000e18);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
        uint256 expectedGohmMoved = 37.141583717129698411e18;
        check_accountDelegationBalances(alice, gohmAliceJoinAmount-expectedGohmMoved, address(0), 0);
        check_accountDelegationBalances(bob, gohmBobJoinAmount+expectedGohmMoved-1, alice, gohmBobJoinAmount+expectedGohmMoved-1);

        address escrow = address(escrowFactory.escrowFor(alice));
        assertEq(gOHM.balanceOf(escrow), gohmBobJoinAmount+expectedGohmMoved-1);
        escrow = address(escrowFactory.escrowFor(bob));
        assertEq(gOHM.balanceOf(escrow), 0);
    }

    function test_transfer_toOther_withDelegationFrom_withDelegationTo() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);
        checkBalanceSheet(143.33e18, 424_491.8612e18);

        vm.startPrank(alice);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, alice, int256(gohmAliceJoinAmount));
        vault.delegateVotingPower(alice);

        vm.startPrank(bob);
        vm.expectEmit(address(manager));
        emit DelegationApplied(bob, alice, int256(gohmBobJoinAmount));
        vault.delegateVotingPower(alice);

        check_accountDelegationBalances(alice, gohmAliceJoinAmount, alice, gohmAliceJoinAmount);
        check_accountDelegationBalances(bob, gohmBobJoinAmount, alice, gohmBobJoinAmount);

        vm.startPrank(alice);
        vault.transfer(bob, 10_000_000e18);
        assertEq(vault.balanceOf(alice), aliceExpectedShares-10_000_000e18);
        assertEq(vault.balanceOf(bob), bobExpectedShares+10_000_000e18);
        checkBalanceSheet(143.33e18, 424_491.8612e18);
        uint256 expectedGohmMoved = 37.141583717129698411e18;
        check_accountDelegationBalances(alice, gohmAliceJoinAmount-expectedGohmMoved, alice, gohmAliceJoinAmount-expectedGohmMoved);
        check_accountDelegationBalances(bob, gohmBobJoinAmount+expectedGohmMoved-1, alice, gohmBobJoinAmount+expectedGohmMoved-1);

        address escrow = address(escrowFactory.escrowFor(alice));
        assertEq(gOHM.balanceOf(escrow), (gohmAliceJoinAmount-expectedGohmMoved)+(gohmBobJoinAmount+expectedGohmMoved-1));
        escrow = address(escrowFactory.escrowFor(bob));
        assertEq(gOHM.balanceOf(escrow), 0);
    }
}

contract OrigamiHOhmVaultTestMulticall is OrigamiHOhmVaultTestBase {
    function test_multicall_success_joinAndDelegate() public {
        uint256 gohmJoinAmount = 10e18;
        bytes[] memory operations = new bytes[](2);
        (operations[0], operations[1]) = (
            abi.encodeCall(ITokenizedBalanceSheetVault.joinWithToken, (address(gOHM), gohmJoinAmount, alice)),
            abi.encodeCall(IOrigamiHOhmVault.delegateVotingPower, (alice))
        );

        vm.startPrank(alice);
        gOHM.mint(alice, gohmJoinAmount);
        gOHM.approve(address(vault), gohmJoinAmount);

        (
            uint256 previewShares,
            uint256[] memory previewAssets,
            uint256[] memory previewLiabilities
        ) = vault.previewJoinWithToken(address(gOHM), gohmJoinAmount);
        vm.expectEmit(address(vault));
        emit Join(alice, alice, previewAssets, previewLiabilities, previewShares);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, alice, int256(gohmJoinAmount));

        bytes[] memory results = vault.multicall(operations);
        assertEq(results.length, 2);
        (
            uint256 actualShares,
            uint256[] memory actualAssets,
            uint256[] memory actualLiabilities
        ) = abi.decode(results[0], (uint256,uint256[],uint256[]));
        assertEq(actualShares, previewShares);
        assertEq(actualAssets[0], previewAssets[0]);
        assertEq(actualLiabilities[0], previewLiabilities[0]);
        
        assertEq(results[1], bytes(""));

        check_accountDelegationBalances(alice, gohmJoinAmount, alice, gohmJoinAmount);
        assertEq(vault.balanceOf(alice), 2_692_400e18);        
    }

    function test_multicall_fail_joinAndTransferTooMuch() public {
        uint256 gohmJoinAmount = 10e18;
        bytes[] memory operations = new bytes[](2);
        (operations[0], operations[1]) = (
            abi.encodeCall(ITokenizedBalanceSheetVault.joinWithToken, (address(gOHM), gohmJoinAmount, alice)),
            abi.encodeCall(IERC20.transfer, (alice, 10_000_000e18))
        );

        vm.startPrank(alice);
        gOHM.mint(alice, gohmJoinAmount);
        gOHM.approve(address(vault), gohmJoinAmount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.multicall(operations);
    }
}

contract OrigamiHOhmVaultTestDebtTokenChange is OrigamiHOhmVaultTestBase {

    function test_changeDebtToken_noSurplus() public {
        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);

        uint256 expectedCoolerDebtInWad = 424_491.8612e18;
        uint256 expectedSurplus = 0;
        checkBalanceSheet(143.33e18, expectedCoolerDebtInWad - expectedSurplus);
        assertEq(manager.coolerDebtInWad(), expectedCoolerDebtInWad);
        assertEq(manager.surplusDebtTokenAmount(), expectedSurplus);

        uint256 exitGohmAmount = 25e18;
        uint256 exitUsdsAmount = 74_041e18;
        uint256 exitSharesAmount = 6_798_989.898989898989898990e18;
        checkPreviewExitWithToken(gOHM, exitGohmAmount, exitSharesAmount, exitGohmAmount, exitUsdsAmount);

        // Update the cooler debt token to be USDC instead of USDS
        {
            updateDebtToken(address(USDC));
            assertEq(address(vault.debtToken()), address(USDC));
            assertEq(address(manager.debtToken()), address(USDC));
        }

        // No longer any surplus - that's on the multisig to swap and put that back in
        {
            checkBalanceSheet(143.33e18, expectedCoolerDebtInWad/1e12);
            assertEq(manager.coolerDebtInWad(), expectedCoolerDebtInWad);
            assertEq(manager.surplusDebtTokenAmount(), 0);
        }

        // Do the swap so the manager has surplus USDC now instead of USDC
        {
            deal(address(USDS), address(manager), 0);
            deal(address(USDC), address(manager), expectedSurplus/1e12);
            checkBalanceSheet(143.33e18, (expectedCoolerDebtInWad-expectedSurplus)/1e12);
            assertEq(manager.coolerDebtInWad(), expectedCoolerDebtInWad);
            assertEq(manager.surplusDebtTokenAmount(), expectedSurplus/1e12);
        }
       
        uint256 exitUsdcAmount = exitUsdsAmount / 1e12;
        checkPreviewExitWithToken(gOHM, exitGohmAmount, exitSharesAmount, exitGohmAmount, exitUsdcAmount);

        // To exit, Alice would need to swap her USDS => USDC
        {
            USDC.mint(alice, exitUsdcAmount);
            exitWithToken(alice, alice, gOHM, 25e18, alice, USDC);
            assertEq(USDC.balanceOf(alice), 0);
            assertEq(gOHM.balanceOf(alice), 25e18);
        }

        // And now Bob could join, receiving USDC
        joinWithToken(bob, gOHM, 10e18, bob);
        assertEq(USDC.balanceOf(bob), 29_616.4e6 - 1);
    }

    function test_changeDebtToken_withSurplus() public {
        skip(90 days);

        uint256 gohmAliceJoinAmount = 100e18;
        uint256 aliceExpectedShares = 26_924_000e18; 
        uint256 gohmBobJoinAmount = 33.33e18;
        uint256 bobExpectedShares = 8_973_769.2e18;
        joinWithToken(alice, gOHM, gohmAliceJoinAmount, alice);
        assertEq(vault.balanceOf(alice), aliceExpectedShares);
        joinWithToken(bob, gOHM, gohmBobJoinAmount, bob);
        assertEq(vault.balanceOf(bob), bobExpectedShares);

        uint256 expectedCoolerDebtInWad = 434_007.245386300503568640e18;
        uint256 expectedSurplus = 8_993.020939884823344424e18;
        assertEq(manager.coolerDebtInWad(), expectedCoolerDebtInWad);
        assertEq(manager.surplusDebtTokenAmount(), expectedSurplus);
        checkBalanceSheet(143.33e18, expectedCoolerDebtInWad - expectedSurplus);

        uint256 exitGohmAmount = 25e18;
        uint256 exitUsdsAmount = 74_132.111987444303395001e18;
        uint256 exitSharesAmount = 6_798_989.898989898989898990e18;
        checkPreviewExitWithToken(gOHM, exitGohmAmount, exitSharesAmount, exitGohmAmount, exitUsdsAmount);

        // Update the cooler debt token to be USDC instead of USDS
        {
            updateDebtToken(address(USDC));
            assertEq(address(vault.debtToken()), address(USDC));
            assertEq(address(manager.debtToken()), address(USDC));
        }

        // No longer any surplus - that's on the multisig to swap and put that back in
        {
            checkBalanceSheet(143.33e18, expectedCoolerDebtInWad/1e12 + 1);
            assertEq(manager.coolerDebtInWad(), expectedCoolerDebtInWad);
            assertEq(manager.surplusDebtTokenAmount(), 0);
        }

        // Do the swap so the manager has surplus USDC now instead of USDC
        {
            deal(address(USDS), address(manager), 0);
            deal(address(USDC), address(manager), expectedSurplus/1e12);
            checkBalanceSheet(143.33e18, (expectedCoolerDebtInWad-expectedSurplus)/1e12+2);
            assertEq(manager.coolerDebtInWad(), expectedCoolerDebtInWad);
            assertEq(manager.surplusDebtTokenAmount(), expectedSurplus/1e12);
        }
       
        uint256 exitUsdcAmount = exitUsdsAmount / 1e12 + 1;
        checkPreviewExitWithToken(gOHM, exitGohmAmount, exitSharesAmount, exitGohmAmount, exitUsdcAmount);

        // To exit, Alice would need to swap her USDS => USDC
        {
            USDC.mint(alice, exitUsdcAmount);
            exitWithToken(alice, alice, gOHM, 25e18, alice, USDC);
            assertEq(USDC.balanceOf(alice), 0);
            assertEq(gOHM.balanceOf(alice), 25e18);
        }

        // And now Bob could join, receiving USDC
        joinWithToken(bob, gOHM, 10e18, bob);
        assertEq(USDC.balanceOf(bob), 29_652.844795e6);
    }
}
