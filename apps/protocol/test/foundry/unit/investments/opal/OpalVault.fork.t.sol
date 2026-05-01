pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IOracle as IMorphoOracle } from "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";

import { OpalManager } from "contracts/investments/opal/OpalManager.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { OpalVault } from "contracts/investments/opal/OpalVault.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { IOpalVault } from "contracts/interfaces/investments/opal/IOpalVault.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";

import { OpalAdapterMorpho } from "contracts/investments/opal/adapters/OpalAdapterMorpho.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import {
    ITokenizedBalanceSheetVault
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import {
    OrigamiTokenizedBalanceSheetTestUtils
} from "test/foundry/unit/investments/tokenizedBalanceSheet/OrigamiTokenizedBalanceSheetTestUtils.t.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiHOhmVault } from "contracts/interfaces/investments/olympus/IOrigamiHOhmVault.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

contract OpalVaultForkTestBase is OrigamiTokenizedBalanceSheetTestUtils {
    OpalManager internal manager;
    OpalVault internal vault;
    TokenPrices internal tokenPrices;

    OpalAdapterFactory internal adapterFactory;
    OpalAdapterMorpho internal adapterImpl;

    OpalAdapterMorpho internal adapter1;
    OpalAdapterMorpho internal adapter2;

    uint16 internal constant PERFORMANCE_FEE = 330; // 3.3%

    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    IERC20 internal constant PT_SUSDE_25SEP2025 = IERC20(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77);
    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint16 internal JOIN_FEE_BPS = 0;
    uint16 internal EXIT_FEE_BPS = 0;

    bytes32 internal tokenHash;

    // PT-sUSDE-25SEP2025 / DAI
    IMorphoOracle internal constant ADAPTER1_MORPHO_ORACLE = IMorphoOracle(0x26394307806F4DD1ea053EC61CFFCa15613a4573);
    uint256 internal constant ADAPTER1_MORPHO_LLTV = 0.915e18;

    // PT-sUSDE-25SEP2025 / USDC
    IMorphoOracle internal constant ADAPTER2_MORPHO_ORACLE = IMorphoOracle(0x5139aa359F7F7FdE869305e8C7AD001B28E1C99a);
    uint256 internal constant ADAPTER2_MORPHO_LLTV = 0.915e18;

    uint96 internal constant MAX_SAFE_LLTV = 0.9e18; // 90%
    uint256 internal constant TARGET_LTV = 0.85e18; // 85% LTV

    uint256 internal constant MAX_LOAN_UR_ON_JOIN = 0.925e18; // 92.5%

    // Seed at roughly the target LTV
    // Assumes USDe === DAI, uses the sUSDe onchain rate as of this block
    // to work out the DAI seed amount.
    uint256 internal constant SEED_PT_SUSDE_25SEP2025_AMOUNT = 1000e18;

    // The seed shares is set to the collateral amount too
    uint256 internal constant SEED_SHARES_AMOUNT = 100e18;

    uint256 internal constant SEED_ADAPTER1_WEIGHT = 0.6e18;
    uint256 internal constant SEED_ADAPTER2_WEIGHT = 0.4e18;

    uint256 internal constant MAX_TOTAL_SUPPLY = type(uint256).max;

    function setUp() public virtual {
        fork("mainnet", 23_072_242);
        vm.label(MORPHO, "MORPHO");
        vm.label(address(PT_SUSDE_25SEP2025), "PT_SUSDE_25SEP2025");
        vm.label(address(DAI), "DAI");
        vm.label(address(USDC), "USDC");

        tokenPrices = new TokenPrices(30);

        deployVault();
        deployAdapters();

        supplyIntoMorpho(adapter1.getMarketParams(), 1_000_000e18); // DAI
        supplyIntoMorpho(adapter2.getMarketParams(), 1_000_000e6); // USDC

        tokenHash = vault.currentTokensHash();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);
    }

    function getVault() internal view override returns (IOrigamiTokenizedBalanceSheetVault) {
        return vault;
    }

    function deployAdapters() internal {
        vm.startPrank(origamiMultisig);

        // Create the factory, a Morpho OpalAdapter, and register it (allowing the manager to create new instances)
        {
            adapterImpl = new OpalAdapterMorpho("MORPHO.1");
            adapterFactory.addImplementation(address(adapterImpl));
        }

        // Create the new adapters
        {
            bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
                MORPHO,
                MorphoMarketParams({
                    collateralToken: address(PT_SUSDE_25SEP2025),
                    loanToken: address(DAI),
                    oracle: address(ADAPTER1_MORPHO_ORACLE),
                    irm: MORPHO_IRM,
                    lltv: ADAPTER1_MORPHO_LLTV
                })
            );

            bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LLTV, MAX_LOAN_UR_ON_JOIN);
            adapter1 = OpalAdapterMorpho(
                manager.addAdapter(address(adapterImpl), "[PT-sUSDE-25SEP2025] / [DAI]", immutableArgs, initArgs)
            );
            vm.label(address(adapter1), "ADAPTER1-PROXY");
        }

        // Create the new adapters
        {
            bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
                MORPHO,
                MorphoMarketParams({
                    collateralToken: address(PT_SUSDE_25SEP2025),
                    loanToken: address(USDC),
                    oracle: address(ADAPTER2_MORPHO_ORACLE),
                    irm: MORPHO_IRM,
                    lltv: ADAPTER2_MORPHO_LLTV
                })
            );

            bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LLTV, MAX_LOAN_UR_ON_JOIN);
            adapter2 = OpalAdapterMorpho(
                manager.addAdapter(address(adapterImpl), "[PT-sUSDE-25SEP2025] / [USDC]", immutableArgs, initArgs)
            );
            vm.label(address(adapter2), "ADAPTER2-PROXY");
        }

        vm.stopPrank();
    }

    function deployVault() internal {
        vault = new OpalVault(
            origamiMultisig, "OPAL PT Susde", "OPAL-PT-sUsde", PERFORMANCE_FEE, feeCollector, address(tokenPrices)
        );
        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        manager = new OpalManager(origamiMultisig, address(vault), address(adapterFactory));

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        manager.setFees(JOIN_FEE_BPS, EXIT_FEE_BPS);
        vm.stopPrank();
    }

    function supplyIntoMorpho(MorphoMarketParams memory marketParams, uint256 amount) internal {
        doMint(IERC20(marketParams.loanToken), origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        IERC20(marketParams.loanToken).approve(MORPHO, amount);
        IMorpho(MORPHO).supply(marketParams, amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }

    function seedAmounts()
        internal
        view
        returns (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt)
    {
        adapter1Collateral = SEED_ADAPTER1_WEIGHT * SEED_PT_SUSDE_25SEP2025_AMOUNT / 1e18;
        adapter1Debt = OrigamiMath.mulDiv(
            adapter1Collateral * TARGET_LTV / 1e18, // 18dp
            ADAPTER1_MORPHO_ORACLE.price(), // Since DAI=18dp, this is to 36+18-18=36 decimals
            1e36, // 18 + 36 - 36 == 18 dp (for DAI)
            OrigamiMath.Rounding.ROUND_DOWN
        );

        adapter2Collateral = SEED_ADAPTER2_WEIGHT * SEED_PT_SUSDE_25SEP2025_AMOUNT / 1e18;
        adapter2Debt = OrigamiMath.mulDiv(
            adapter2Collateral * TARGET_LTV / 1e18, // 18dp
            ADAPTER2_MORPHO_ORACLE.price(), // Since USDC=6dp, this is to 36+6-18=24 decimals
            1e36, // 18 + 24 - 36 == 6 dp (for USDC)
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }

    function dealAsset(address account, uint256 amount) internal {
        deal(address(PT_SUSDE_25SEP2025), account, PT_SUSDE_25SEP2025.balanceOf(account) + amount, false);
    }

    function seedDeposit(address account, uint256 maxSupply) internal {
        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();

        uint256[] memory assetAmounts = mkArray(adapter1Collateral + adapter2Collateral);
        uint256[] memory liabilityAmounts = mkArray(adapter1Debt, adapter2Debt);

        vm.startPrank(account);
        dealAsset(account, assetAmounts[0]);
        PT_SUSDE_25SEP2025.approve(address(vault), assetAmounts[0]);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        (perAdapterBS[0].assets, perAdapterBS[0].liabilities) = (mkArray(adapter1Collateral), mkArray(adapter1Debt)); // PT
        // sUSDe || DAI
        (perAdapterBS[1].assets, perAdapterBS[1].liabilities) = (mkArray(adapter2Collateral), mkArray(adapter2Debt)); // PT
        // sUSDe || USDC

        vault.seed(assetAmounts, liabilityAmounts, SEED_SHARES_AMOUNT, account, maxSupply, abi.encode(perAdapterBS));
        vm.stopPrank();
    }

    function joinWithToken(address account, IERC20 token, uint256 tokenAmount, address receiver)
        internal
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        uint256 prevShares = vault.balanceOf(receiver);
        (uint256 previewShares, uint256[] memory previewAssets, uint256[] memory previewLiabilities) =
            vault.previewJoinWithToken(address(token), tokenAmount);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, previewAssets, previewLiabilities);

        vm.startPrank(account);
        dealAsset(account, previewAssets[0]);
        PT_SUSDE_25SEP2025.approve(address(vault), previewAssets[0]);

        {
            (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
            uint256 expectedFeeAmount = sharesNoFees > previewShares ? sharesNoFees - previewShares : 0;
            bool isAsset = address(token) == address(PT_SUSDE_25SEP2025);
            assertEq(
                expectedFeeAmount,
                sharesNoFees
                    - OrigamiMath.mulDiv(
                        sharesNoFees,
                        10_000 - JOIN_FEE_BPS,
                        10_000,
                        isAsset ? OrigamiMath.Rounding.ROUND_DOWN : OrigamiMath.Rounding.ROUND_UP
                    ),
                "joinWithToken::expectedShareFees"
            );
        }

        vm.expectEmit(address(vault));
        emit ITokenizedBalanceSheetVault.Join(account, receiver, previewAssets, previewLiabilities, previewShares);
        (shares, assets, liabilities) = vault.joinWithToken(address(token), tokenAmount, receiver, tokenHash);
        vm.stopPrank();

        assertEq(shares, previewShares, "joinWithToken::shares");
        assertEq(vault.balanceOf(receiver), prevShares + shares);
        expectArr(previewAssets, assets);
        expectArr(previewLiabilities, liabilities);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, assets, liabilities);
    }

    function joinWithShares(address account, uint256 shares, address receiver)
        internal
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        uint256 prevShares = vault.balanceOf(receiver);
        (uint256[] memory previewAssets, uint256[] memory previewLiabilities) = vault.previewJoinWithShares(shares);

        vm.startPrank(account);
        dealAsset(account, previewAssets[0]);
        PT_SUSDE_25SEP2025.approve(address(vault), previewAssets[0]);

        vm.expectEmit(address(vault));
        emit ITokenizedBalanceSheetVault.Join(account, receiver, previewAssets, previewLiabilities, shares);
        (assets, liabilities) = vault.joinWithShares(shares, receiver, tokenHash);
        vm.stopPrank();

        assertEq(vault.balanceOf(receiver), prevShares + shares);
        expectArr(previewAssets, assets);
        expectArr(previewLiabilities, liabilities);
    }

    function exitWithToken(address caller, address sharesOwner, IERC20 token, uint256 tokenAmount, address receiver)
        internal
    {
        (uint256 previewShares, uint256[] memory previewAssets, uint256[] memory previewLiabilities) =
            vault.previewExitWithToken(address(token), tokenAmount);

        uint256 prevShares = vault.balanceOf(receiver);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, previewAssets, previewLiabilities);

        // Assume the caller already has the debt tokens to repay.
        vm.startPrank(caller);
        DAI.approve(address(vault), previewLiabilities[0]);
        USDC.approve(address(vault), previewLiabilities[1]);

        {
            (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
            uint256 expectedFeeAmount = sharesNoFees > previewShares ? sharesNoFees - previewShares : 0;
            if (expectedFeeAmount > 0) {
                vm.expectEmit(address(vault));
                emit IOrigamiTokenizedBalanceSheetVault.InKindFees(
                    IOrigamiTokenizedBalanceSheetVault.FeeType.EXIT_FEE, EXIT_FEE_BPS, expectedFeeAmount
                );
            }
        }

        vm.expectEmit(address(vault));
        emit ITokenizedBalanceSheetVault.Exit(
            caller, receiver, sharesOwner, previewAssets, previewLiabilities, previewShares
        );
        (uint256 actualShares, uint256[] memory actualAssets, uint256[] memory actualLiabilities) =
            vault.exitWithToken(address(token), tokenAmount, receiver, sharesOwner, tokenHash);
        vm.stopPrank();

        assertEq(actualShares, previewShares);
        assertEq(vault.balanceOf(sharesOwner), prevShares - previewShares);
        expectArr(previewAssets, actualAssets);
        expectArr(previewLiabilities, actualLiabilities);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, actualAssets, actualLiabilities);
    }

    function exitWithShares(address caller, address sharesOwner, uint256 sharesAmount, address receiver)
        internal
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        (uint256[] memory previewAssets, uint256[] memory previewLiabilities) =
            vault.previewExitWithShares(sharesAmount);

        vm.startPrank(caller);

        uint256 prevShares = vault.balanceOf(caller);

        // Assume the caller already has the debt tokens to repay.
        DAI.approve(address(vault), previewLiabilities[0]);
        USDC.approve(address(vault), previewLiabilities[1]);

        vm.expectEmit(address(vault));
        emit ITokenizedBalanceSheetVault.Exit(
            caller, receiver, sharesOwner, previewAssets, previewLiabilities, sharesAmount
        );
        (assets, liabilities) = vault.exitWithShares(sharesAmount, receiver, sharesOwner, tokenHash);
        vm.stopPrank();

        expectArr(previewAssets, assets);
        expectArr(previewLiabilities, liabilities);
        assertEq(vault.balanceOf(sharesOwner), prevShares - sharesAmount);
    }

    function _checkInputTokenAmount(
        IERC20 token,
        uint256 tokenAmount,
        uint256[] memory assetAmounts,
        uint256[] memory liabilityAmounts
    ) internal pure {
        if (address(token) == address(PT_SUSDE_25SEP2025)) {
            assertEq(
                assetAmounts[0], tokenAmount, "PT_SUSDE_25SEP2025 input tokenAmount not matching derived output amount"
            );
        } else if (address(token) == address(DAI)) {
            assertEq(liabilityAmounts[0], tokenAmount, "DAI input tokenAmount not matching derived output amount");
        } else if (address(token) == address(USDC)) {
            assertEq(liabilityAmounts[1], tokenAmount, "USDC input tokenAmount not matching derived output amount");
        } else {
            assertFalse(true, "unknown token in _checkInputTokenAmount");
        }
    }
}

contract OpalVaultForkTestAdmin is OpalVaultForkTestBase {
    function test_initialization_withSeed() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "OPAL PT Susde");
        assertEq(vault.symbol(), "OPAL-PT-sUsde");
        assertEq(vault.decimals(), 18);

        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT); // No fees taken on the seed
        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(address(PT_SUSDE_25SEP2025)), mkArray(address(DAI), address(USDC))))
        );

        assertEq(vault.MAX_PERFORMANCE_FEE_BPS(), 1000);

        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();
        checkBalanceSheet(mkArray(adapter1Collateral + adapter2Collateral), mkArray(adapter1Debt + 1, adapter2Debt + 1));

        checkConvertFromToken(
            PT_SUSDE_25SEP2025,
            SEED_PT_SUSDE_25SEP2025_AMOUNT * 2,
            SEED_SHARES_AMOUNT * 2,
            mkArray((adapter1Collateral + adapter2Collateral) * 2),
            mkArray((adapter1Debt + 1) * 2, (adapter2Debt + 1) * 2)
        );
        checkConvertFromToken(
            DAI,
            (adapter1Debt + 1) * 2,
            SEED_SHARES_AMOUNT * 2,
            mkArray((adapter1Collateral + adapter2Collateral) * 2),
            mkArray((adapter1Debt + 1) * 2, (adapter2Debt + 1) * 2)
        );
        checkConvertFromToken(
            USDC,
            (adapter2Debt + 1) * 2,
            SEED_SHARES_AMOUNT * 2,
            mkArray((adapter1Collateral + adapter2Collateral) * 2),
            mkArray((adapter1Debt + 1) * 2, (adapter2Debt + 1) * 2)
        );

        checkConvertFromShares(
            SEED_SHARES_AMOUNT * 100,
            mkArray((adapter1Collateral + adapter2Collateral) * 100),
            mkArray((adapter1Debt + 1) * 100, (adapter2Debt + 1) * 100)
        );
        checkConvertFromShares(
            1e18,
            mkArray(10e18),
            mkArray(4.993431516837899544e18, 3.354135e6) // 60% / 40%
        );

        assertEq(vault.joinFeeBps(), 0);
        assertEq(vault.exitFeeBps(), 0);

        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);

        (address[] memory aTokens, address[] memory lTokens) = vault.tokens();
        expectArr(aTokens, mkArray(address(PT_SUSDE_25SEP2025)));
        expectArr(lTokens, mkArray(address(DAI), address(USDC)));
        expectArr(vault.assetTokens(), aTokens);
        expectArr(vault.liabilityTokens(), lTokens);

        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(address(vault.manager()), address(manager));

        checkPreviewJoinWithShares(1e18, mkArray(10e18), mkArray(4.993431516837899544e18, 3.354135e6));
        checkPreviewJoinWithToken(
            PT_SUSDE_25SEP2025, 1e18, 0.1e18, mkArray(1e18), mkArray(0.499343151683789954e18, 0.335413e6)
        );
        checkPreviewJoinWithToken(
            DAI, 1e18, 0.20026308494028411e18, mkArray(2.0026308494028411e18), mkArray(1e18, 0.671709e6)
        );
        checkPreviewJoinWithToken(
            USDC, 1e6, 0.298139455362301362e18, mkArray(2.98139455362301362e18), mkArray(1.488738952819001732e18, 1e6)
        );
        checkPreviewExitWithShares(1e18, mkArray(10e18), mkArray(4.993431516837899545e18, 3.354136e6));
        checkPreviewExitWithToken(
            PT_SUSDE_25SEP2025, 1e18, 0.1e18, mkArray(1e18), mkArray(0.499343151683789955e18, 0.335414e6)
        );
        checkPreviewExitWithToken(
            DAI, 1e18, 0.200263084940284109e18, mkArray(2.00263084940284109e18), mkArray(1e18, 0.67171e6)
        );
        checkPreviewExitWithToken(
            USDC, 1e6, 0.298139455362301361e18, mkArray(2.98139455362301361e18), mkArray(1.488738952819001729e18, 1e6)
        );

        //   2,155,820.09 DAI liquidity which can be borrowed
        //   1,002,870.48 USDC liquidity which can be borrowed
        assertEq(vault.maxJoinWithToken(address(PT_SUSDE_25SEP2025), address(0)), 2_357_417.07144993642838232e18);
        assertEq(vault.maxJoinWithToken(address(DAI), address(0)), 1_177_160.070290981506689004e18);
        assertEq(vault.maxJoinWithToken(address(USDC), address(0)), 790_709.525039e6);
        assertEq(vault.maxJoinWithShares(address(0)), 235_741.707144993642838232e18);

        assertEq(vault.maxExitWithShares(address(0)), 9053.237113832858000655e18);
        assertEq(vault.maxExitWithToken(address(PT_SUSDE_25SEP2025), address(0)), 90_532.37113832858000655e18);
        assertEq(vault.maxExitWithToken(address(DAI), address(0)), 45_206.719533619575946318e18);
        assertEq(vault.maxExitWithToken(address(USDC), address(0)), 30_365.780009e6);
    }

    function test_init_noAdapters() public {
        deployVault();
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(new address[](0), new address[](0))));

        assertEq(vault.totalSupply(), 0);
        checkBalanceSheet(new uint256[](0), new uint256[](0));

        checkConvertFromToken(PT_SUSDE_25SEP2025, 1e18, 0, new uint256[](0), new uint256[](0));
        checkConvertFromShares(1e18, new uint256[](0), new uint256[](0));

        (address[] memory aTokens, address[] memory lTokens) = vault.tokens();
        expectArr(aTokens, new address[](0));
        expectArr(lTokens, new address[](0));

        checkPreviewJoinWithShares(1e18, new uint256[](0), new uint256[](0));
        checkPreviewJoinWithToken(PT_SUSDE_25SEP2025, 1e18, 0, new uint256[](0), new uint256[](0));
        checkPreviewExitWithShares(1e18, new uint256[](0), new uint256[](0));
        checkPreviewExitWithToken(PT_SUSDE_25SEP2025, 1e18, 0, new uint256[](0), new uint256[](0));

        assertEq(vault.maxJoinWithToken(address(PT_SUSDE_25SEP2025), address(0)), 0);
        assertEq(vault.maxJoinWithShares(address(0)), 0);
        assertEq(vault.maxExitWithShares(address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(address(PT_SUSDE_25SEP2025), address(0)), 0);
    }

    function test_initialization_noSeed() public {
        deployVault();
        deployAdapters();
        tokenHash = vault.currentTokensHash();

        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "OPAL PT Susde");
        assertEq(vault.symbol(), "OPAL-PT-sUsde");
        assertEq(vault.decimals(), 18);

        assertEq(vault.maxTotalSupply(), 0);
        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);
        assertEq(vault.totalSupply(), 0);
        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(address(PT_SUSDE_25SEP2025)), mkArray(address(DAI), address(USDC))))
        );

        assertEq(vault.MAX_PERFORMANCE_FEE_BPS(), 1000);

        (/*uint256 adapter1Collateral*/, uint256 adapter1Debt,/*uint256 adapter2Collateral*/, uint256 adapter2Debt) =
            seedAmounts();
        checkBalanceSheet(mkArray(0), mkArray(0, 0));

        checkConvertFromToken(PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT * 2, 0, mkArray(0), mkArray(0, 0));
        checkConvertFromToken(DAI, (adapter1Debt + 1) * 2, 0, mkArray(0), mkArray(0, 0));
        checkConvertFromToken(USDC, (adapter2Debt + 1) * 2, 0, mkArray(0), mkArray(0, 0));

        checkConvertFromShares(SEED_SHARES_AMOUNT * 100, mkArray(0), mkArray(0, 0));
        checkConvertFromShares(1e18, mkArray(0), mkArray(0, 0));

        assertEq(vault.joinFeeBps(), 0);
        assertEq(vault.exitFeeBps(), 0);

        assertEq(vault.areJoinsPaused(), false);
        assertEq(vault.areExitsPaused(), false);

        (address[] memory aTokens, address[] memory lTokens) = vault.tokens();
        expectArr(aTokens, mkArray(address(PT_SUSDE_25SEP2025)));
        expectArr(lTokens, mkArray(address(DAI), address(USDC)));
        expectArr(vault.assetTokens(), aTokens);
        expectArr(vault.liabilityTokens(), lTokens);

        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(address(vault.manager()), address(manager));

        checkPreviewJoinWithShares(1e18, mkArray(0), mkArray(0, 0));
        checkPreviewJoinWithToken(PT_SUSDE_25SEP2025, 1e18, 0, mkArray(0), mkArray(0, 0));
        checkPreviewJoinWithToken(DAI, 1e18, 0, mkArray(0), mkArray(0, 0));
        checkPreviewJoinWithToken(USDC, 1e6, 0, mkArray(0), mkArray(0, 0));
        checkPreviewExitWithShares(1e18, mkArray(0), mkArray(0, 0));
        checkPreviewExitWithToken(PT_SUSDE_25SEP2025, 1e18, 0, mkArray(0), mkArray(0, 0));
        checkPreviewExitWithToken(DAI, 1e18, 0, mkArray(0), mkArray(0, 0));
        checkPreviewExitWithToken(USDC, 1e6, 0, mkArray(0), mkArray(0, 0));

        assertEq(vault.maxJoinWithToken(address(PT_SUSDE_25SEP2025), address(0)), 0);
        assertEq(vault.maxJoinWithToken(address(DAI), address(0)), 0);
        assertEq(vault.maxJoinWithToken(address(USDC), address(0)), 0);
        assertEq(vault.maxJoinWithShares(address(0)), 0);

        assertEq(vault.maxExitWithShares(address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(address(PT_SUSDE_25SEP2025), address(0)), 0);
        assertEq(vault.maxExitWithToken(address(DAI), address(0)), 0);
        assertEq(vault.maxExitWithToken(address(USDC), address(0)), 0);
    }

    function test_constructor_fail_perfFee() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault = new OpalVault(
            origamiMultisig, "OPAL PT Susde", "OPAL-PT-sUsde", 1000 + 1, feeCollector, address(tokenPrices)
        );
    }

    function test_setup() public view {
        assertEq(adapter1.currentLtv(), TARGET_LTV + 1);
        assertEq(adapter2.currentLtv(), 0.850000001520511226e18);

        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();
        assertEq(adapter1Collateral + adapter2Collateral, SEED_PT_SUSDE_25SEP2025_AMOUNT);

        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = vault.balanceSheet();
        assertEq(totalAssets.length, 1);
        assertEq(totalAssets[0], SEED_PT_SUSDE_25SEP2025_AMOUNT);
        assertEq(totalLiabilities.length, 2);
        assertEq(totalLiabilities[0], adapter1Debt + 1);
        assertEq(totalLiabilities[1], adapter2Debt + 1);

        assertEq(DAI.balanceOf(origamiMultisig), adapter1Debt);
        assertEq(USDC.balanceOf(origamiMultisig), adapter2Debt);
    }

    function test_seed_fail_noAdapters() public {
        deployVault();
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOpalManager.InvalidAdapter.selector));
        vault.seed(
            new uint256[](0),
            new uint256[](0),
            1e18,
            origamiMultisig,
            3_333_333e18,
            abi.encode(new IOpalManager.AssetsAndLiabilities[](0))
        );
    }

    function test_seed_fail_badPerAdapterBS() public {
        deployVault();
        deployAdapters();

        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();

        assertEq(adapter1Collateral, 600e18);
        assertEq(adapter1Debt, 499.3431516837899544e18);
        assertEq(adapter2Collateral, 400e18);
        assertEq(adapter2Debt, 335.413505e6);

        uint256[] memory assetAmounts = mkArray(adapter1Collateral + adapter2Collateral);
        uint256[] memory liabilityAmounts = mkArray(adapter1Debt, adapter2Debt);

        vm.startPrank(origamiMultisig);
        dealAsset(origamiMultisig, assetAmounts[0]);
        PT_SUSDE_25SEP2025.approve(address(vault), assetAmounts[0]);

        // per adapter balance needs to be the same length as the active adapters.
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        vault.seed(
            assetAmounts,
            liabilityAmounts,
            SEED_SHARES_AMOUNT,
            origamiMultisig,
            3_333_333e18,
            abi.encode(new IOpalManager.AssetsAndLiabilities[](1))
        );
    }

    function test_seed_success() public {
        deployVault();
        deployAdapters();

        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();

        assertEq(adapter1Collateral, 600e18);
        assertEq(adapter1Debt, 499.3431516837899544e18);
        assertEq(adapter2Collateral, 400e18);
        assertEq(adapter2Debt, 335.413505e6);

        uint256[] memory assetAmounts = mkArray(adapter1Collateral + adapter2Collateral);
        uint256[] memory liabilityAmounts = mkArray(adapter1Debt, adapter2Debt);

        vm.startPrank(origamiMultisig);
        dealAsset(origamiMultisig, assetAmounts[0]);
        PT_SUSDE_25SEP2025.approve(address(vault), assetAmounts[0]);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        (perAdapterBS[0].assets, perAdapterBS[0].liabilities) = (mkArray(adapter1Collateral), mkArray(adapter1Debt)); // PT
        // sUSDe || DAI
        (perAdapterBS[1].assets, perAdapterBS[1].liabilities) = (mkArray(adapter2Collateral), mkArray(adapter2Debt)); // PT
        // sUSDe || USDC

        vault.seed(
            assetAmounts, liabilityAmounts, SEED_SHARES_AMOUNT, origamiMultisig, 3_333_333e18, abi.encode(perAdapterBS)
        );
        checkBalanceSheet(
            mkArray((adapter1Collateral + adapter2Collateral)), mkArray(adapter1Debt + 1, adapter2Debt + 1)
        );
        assertEq(vault.maxTotalSupply(), 3_333_333e18);

        // A join is at the same ratio
        (uint256 shares, uint256[] memory assets, uint256[] memory liabilities) =
            joinWithToken(alice, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 10, alice);
        checkBalanceSheet(
            mkArray((adapter1Collateral + adapter2Collateral) * 11 / 10),
            mkArray(adapter1Debt * 11 / 10 + 1, adapter2Debt * 11 / 10 + 1)
        );

        assertEq(shares, SEED_SHARES_AMOUNT / 10);
        expectArr(assets, mkArray(SEED_PT_SUSDE_25SEP2025_AMOUNT / 10));
        expectArr(liabilities, mkArray(adapter1Debt / 10, adapter2Debt / 10));

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), liabilities[0]);
        assertEq(USDC.balanceOf(alice), liabilities[1]);
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
    }

    function test_setManager_newManager() public {
        OpalManager newManager = new OpalManager(origamiMultisig, address(vault), address(adapterFactory));

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vm.stopPrank();

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit IOrigamiTokenizedBalanceSheetVault.ManagerSet(address(newManager));
        vault.setManager(address(newManager));

        assertEq(address(vault.manager()), address(newManager));

        (address[] memory assets, address[] memory liabilities) = vault.tokens();
        expectArr(assets);
        expectArr(liabilities);

        // Hash is of the empty arrays
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(new address[](0), new address[](0))));
    }

    function test_setTokenPrices_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setTokenPrices(address(0));
    }

    function test_setTokenPrices_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit IOrigamiTokenizedBalanceSheetVault.TokenPricesSet(alice);
        vault.setTokenPrices(alice);
        assertEq(address(vault.tokenPrices()), alice);
    }

    function test_setFeeCollector_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit IOpalVault.FeeCollectorSet(alice);
        vault.setFeeCollector(alice);
        assertEq(address(vault.feeCollector()), alice);
    }
}

contract OpalVaultForkTestAccess is OpalVaultForkTestBase {
    function test_access_setManager() public {
        expectElevatedAccess();
        vault.setManager(alice);
    }

    function test_access_setAnnualPerformanceFee() public {
        expectElevatedAccess();
        vault.setAnnualPerformanceFee(123);
    }

    function test_access_setFeeCollector() public {
        expectElevatedAccess();
        vault.setFeeCollector(alice);
    }

    function test_access_collectPerformanceFees() public {
        expectElevatedAccess();
        vault.collectPerformanceFees();
    }

    function test_access_setTokenPrices() public {
        expectElevatedAccess();
        vault.setTokenPrices(alice);
    }

    function test_access_setMaxTotalSupply() public {
        expectElevatedAccess();
        vault.setMaxTotalSupply(100);
    }
}

contract OpalVaultForkTestFees is OpalVaultForkTestBase {
    function test_accruedPerformanceFee() public {
        // No supply yet
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT);
        assertEq(vault.accruedPerformanceFee(), 0);

        uint256 depositAmount = 100_000e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, depositAmount, alice);

        uint256 expectedTotalSupply = SEED_SHARES_AMOUNT + 10_000e18;
        assertEq(vault.totalSupply(), expectedTotalSupply);
        assertEq(vault.accruedPerformanceFee(), 0);

        vm.warp(vm.getBlockTimestamp() + 182.5 days);
        assertEq(vault.accruedPerformanceFee(), expectedTotalSupply * PERFORMANCE_FEE / 10_000 / 2);

        vm.warp(vm.getBlockTimestamp() + 182.5 days);
        assertEq(vault.accruedPerformanceFee(), expectedTotalSupply * PERFORMANCE_FEE / 10_000);
    }

    function test_collectPerformanceFees_success() public {
        uint256 depositAmount = 100_000e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, depositAmount, alice);

        uint256 totalSupply = vault.totalSupply();

        vm.startPrank(origamiMultisig);
        vault.collectPerformanceFees();
        assertEq(vault.balanceOf(feeCollector), 0);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());

        vm.warp(vm.getBlockTimestamp() + 182.5 days);
        uint256 expectedAmount = totalSupply * PERFORMANCE_FEE / 10_000 / 2;
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeesCollected(feeCollector, expectedAmount);
        uint256 amount = vault.collectPerformanceFees();
        assertEq(amount, expectedAmount);
        assertEq(vault.balanceOf(feeCollector), expectedAmount);
        assertEq(vault.totalSupply(), totalSupply + expectedAmount);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());

        uint256 expectedAmount2 = (totalSupply + expectedAmount) * PERFORMANCE_FEE / 10_000 / 2;
        vm.warp(vm.getBlockTimestamp() + 182.5 days);
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeesCollected(feeCollector, expectedAmount2);
        amount = vault.collectPerformanceFees();
        assertEq(amount, expectedAmount2);
        assertEq(vault.balanceOf(feeCollector), expectedAmount + expectedAmount2);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());
    }

    function test_setAnnualPerformanceFee_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.setAnnualPerformanceFee(1001);
    }

    function test_setAnnualPerformanceFee_successNoSupply() public {
        (, uint256[] memory totalLiabilities) = vault.balanceSheet();
        doMint(DAI, origamiMultisig, totalLiabilities[0]);
        doMint(USDC, origamiMultisig, totalLiabilities[1]);
        exitWithShares(origamiMultisig, origamiMultisig, vault.totalSupply(), origamiMultisig);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeeSet(123);
        vault.setAnnualPerformanceFee(123);
        assertEq(vault.annualPerformanceFeeBps(), 123);
        assertEq(vault.balanceOf(feeCollector), 0);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());
    }

    function test_setAnnualPerformanceFee_successWithSupply() public {
        uint256 depositAmount = 100_000e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, depositAmount, alice);

        uint256 totalSupply = vault.totalSupply();
        vm.warp(vm.getBlockTimestamp() + 365 days);
        uint256 expectedAmount = totalSupply * PERFORMANCE_FEE / 10_000;

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeesCollected(feeCollector, expectedAmount);
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeeSet(123);
        vault.setAnnualPerformanceFee(123);
        assertEq(vault.annualPerformanceFeeBps(), 123);
        assertEq(vault.balanceOf(feeCollector), expectedAmount);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());
    }

    function test_collectPerformanceFees_nothingToMint() public {
        uint256 depositAmount = 100_000e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, depositAmount, alice);

        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, SEED_SHARES_AMOUNT + 10_000e18);

        vm.startPrank(origamiMultisig);
        vault.setAnnualPerformanceFee(0);

        skip(182.5 days);

        uint256 amount = vault.collectPerformanceFees();
        assertEq(amount, 0);
        assertEq(vault.balanceOf(feeCollector), 0);
    }

    function test_collectPerformanceFees_overMaxTotalSupply() public {
        uint256 depositAmount = 100_000e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, depositAmount, alice);

        uint256 totalSupply = vault.totalSupply();

        vm.prank(origamiMultisig);
        vault.setMaxTotalSupply(50_000e18);

        vm.startPrank(origamiMultisig);
        vault.collectPerformanceFees();
        assertEq(vault.balanceOf(feeCollector), 0);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());

        vm.warp(vm.getBlockTimestamp() + 182.5 days);
        uint256 expectedAmount = totalSupply * PERFORMANCE_FEE / 10_000 / 2;
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeesCollected(feeCollector, expectedAmount);
        uint256 amount = vault.collectPerformanceFees();
        assertEq(amount, expectedAmount);
        assertEq(vault.balanceOf(feeCollector), expectedAmount);
        assertEq(vault.totalSupply(), totalSupply + expectedAmount);
        assertEq(totalSupply + expectedAmount, 10_266.65e18);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());

        uint256 expectedAmount2 = (totalSupply + expectedAmount) * PERFORMANCE_FEE / 10_000 / 2;
        vm.warp(vm.getBlockTimestamp() + 182.5 days);
        vm.expectEmit(address(vault));
        emit IOpalVault.PerformanceFeesCollected(feeCollector, expectedAmount2);
        amount = vault.collectPerformanceFees();
        assertEq(amount, expectedAmount2);
        assertEq(vault.balanceOf(feeCollector), expectedAmount + expectedAmount2);
        assertEq(vault.lastPerformanceFeeTime(), vm.getBlockTimestamp());
    }
}

contract OpalVaultForkTestViews is OpalVaultForkTestBase {
    function test_tokensChanged() public {
        assertEq(vault.currentTokensHash(), 0x810b867b6344c6db8b2e350f2c28f774719c4472f974a17b7599ca639cc994c3);

        vm.startPrank(origamiMultisig);
        adapter1.setDeprecated(true);
        manager.removeAdapter(address(adapter1));

        expectArr(vault.assetTokens(), mkArray(address(PT_SUSDE_25SEP2025)));
        expectArr(vault.liabilityTokens(), mkArray(address(USDC)));
        assertEq(vault.currentTokensHash(), 0x9f535180702907ea9b59406923b62a5a8f259043068ace01db7d32f104d7bd62);
    }

    function test_supportsInterface() public view {
        assertEq(vault.supportsInterface(type(IOpalVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(IOrigamiTokenizedBalanceSheetVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(ITokenizedBalanceSheetVault).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(vault.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(vault.supportsInterface(type(IOrigamiHOhmVault).interfaceId), false);
    }

    function test_matchToken() public view {
        (IOrigamiTokenizedBalanceSheetVault.AssetOrLiability kind, uint256 index) =
            vault.matchToken(address(PT_SUSDE_25SEP2025));
        assertEq(uint256(kind), uint256(IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET));
        assertEq(index, 0);
        (kind, index) = vault.matchToken(address(DAI));
        assertEq(uint256(kind), uint256(IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY));
        assertEq(index, 0);
        (kind, index) = vault.matchToken(address(USDC));
        assertEq(uint256(kind), uint256(IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY));
        assertEq(index, 1);
        (kind, index) = vault.matchToken(alice);
        assertEq(uint256(kind), uint256(IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.INVALID));
        assertEq(index, 0);
    }
}

contract OpalVaultForkTestJoinAndExit is OpalVaultForkTestBase {
    function test_join_fail_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector,
                alice,
                address(PT_SUSDE_25SEP2025),
                10e18,
                0
            )
        );
        vault.joinWithToken(address(PT_SUSDE_25SEP2025), 10e18, alice, tokenHash);
    }

    function test_exit_fail_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithShares.selector, origamiMultisig, 1e18, 0
            )
        );
        vault.exitWithShares(1e18, origamiMultisig, origamiMultisig, tokenHash);
    }

    function test_joinWithToken_asset() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesAmount = 3.3e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, assetJoinAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_maxJoinWithToken_asset() public {
        uint256 max = vault.maxJoinWithToken(address(PT_SUSDE_25SEP2025), alice);

        vm.startPrank(alice);
        dealAsset(alice, 10_000_000e18);
        PT_SUSDE_25SEP2025.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.925000000038267362e18, 0, MAX_LOAN_UR_ON_JOIN
            )
        );
        vault.joinWithToken(address(PT_SUSDE_25SEP2025), max + 0.001e18, alice, tokenHash);

        // Works ok for max
        joinWithToken(alice, PT_SUSDE_25SEP2025, max, alice);
    }

    function test_joinWithToken_debt1() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesAmount = 3.3e18;
        joinWithToken(alice, DAI, debt1JoinAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_maxJoinWithToken_debt1() public {
        uint256 max = vault.maxJoinWithToken(address(DAI), alice);

        vm.startPrank(alice);
        dealAsset(alice, 10_000_000e18);
        PT_SUSDE_25SEP2025.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.925000000076635398e18, 0, MAX_LOAN_UR_ON_JOIN
            )
        );
        vault.joinWithToken(address(DAI), max + 0.001e18, alice, tokenHash);

        // Works ok for max
        joinWithToken(alice, DAI, max, alice);
    }

    function test_joinWithToken_debt2() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 32.99999791898660158e18;
        uint256 debt1JoinAmount = 16.478322966425279431e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesAmount = assetJoinAmount / 10; // share price is 1/10th right now
        joinWithToken(alice, USDC, debt2JoinAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_maxJoinWithToken_debt2() public {
        uint256 max = vault.maxJoinWithToken(address(USDC), alice);

        vm.startPrank(alice);
        dealAsset(alice, 10_000_000e18);
        PT_SUSDE_25SEP2025.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.92500000011405865e18, 0, MAX_LOAN_UR_ON_JOIN
            )
        );
        vault.joinWithToken(address(USDC), max + 0.001e6, alice, tokenHash);

        // Works ok for max
        joinWithToken(alice, USDC, max, alice);
    }

    function test_joinWithToken_other() public {
        address USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, USDS, 1e18, 0
            )
        );
        vault.joinWithToken(USDS, 1e18, alice, tokenHash);
    }

    function test_joinWithShares() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesAmount = 3.3e18;
        joinWithShares(alice, sharesAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_maxJoinWithShares() public {
        uint256 max = vault.maxJoinWithShares(alice);

        vm.startPrank(alice);
        dealAsset(alice, 10_000_000e18);
        PT_SUSDE_25SEP2025.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.925000000382673611e18, 0, MAX_LOAN_UR_ON_JOIN
            )
        );
        vault.joinWithShares(max + 0.001e18, alice, tokenHash);

        // Works ok for max
        joinWithShares(alice, max, alice);
    }

    function test_exitWithToken_asset() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = 3.3e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4e18;
        uint256 debt1ExitAmount = 1.997372606735159818e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.4e18;
        exitWithToken(bob, bob, PT_SUSDE_25SEP2025, assetExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_maxExitWithToken_asset() public {
        joinWithShares(alice, 100e18, alice);

        uint256 max = vault.maxExitWithToken(address(PT_SUSDE_25SEP2025), alice);

        vm.startPrank(alice);
        USDC.approve(address(vault), 10_000_000e6);
        DAI.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector,
                alice,
                address(PT_SUSDE_25SEP2025),
                1000.001e18,
                1000e18
            )
        );
        vault.exitWithToken(address(PT_SUSDE_25SEP2025), max + 0.001e18, alice, alice, tokenHash);

        // Works ok for max
        assertEq(vault.balanceOf(alice), 100e18);
        exitWithToken(alice, alice, PT_SUSDE_25SEP2025, max, alice);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_exitWithToken_debt1() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = 3.3e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4e18;
        uint256 debt1ExitAmount = 1.997372606735159818e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.4e18;
        exitWithToken(bob, bob, DAI, debt1ExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_maxExitWithToken_debt1() public {
        joinWithShares(alice, 100e18, alice);

        uint256 max = vault.maxExitWithToken(address(DAI), alice);

        vm.startPrank(alice);
        USDC.approve(address(vault), 10_000_000e6);
        DAI.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector,
                alice,
                address(DAI),
                499.344151683789954401e18,
                499.343151683789954401e18
            )
        );
        vault.exitWithToken(address(DAI), max + 0.001e18, alice, alice, tokenHash);

        // Works ok for max
        assertEq(vault.balanceOf(alice), 100e18);
        exitWithToken(alice, alice, DAI, max, alice);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_exitWithToken_debt2() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = 3.3e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4.00000291789922534e18;
        uint256 debt1ExitAmount = 1.997374063768155295e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.400000291789922534e18;
        exitWithToken(bob, bob, USDC, debt2ExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_maxExitWithToken_debt2() public {
        joinWithShares(alice, 100e18, alice);

        uint256 max = vault.maxExitWithToken(address(USDC), alice);

        vm.startPrank(alice);
        USDC.approve(address(vault), 10_000_000e6);
        DAI.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector,
                alice,
                address(USDC),
                335.414506e6,
                335.413506e6
            )
        );
        vault.exitWithToken(address(USDC), max + 0.001e6, alice, alice, tokenHash);

        // Works ok for max
        assertEq(vault.balanceOf(alice), 100e18);
        exitWithToken(alice, alice, USDC, max, alice);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_exitWithToken_other() public {
        uint256 assetJoinAmount = 33e18;
        joinWithToken(alice, PT_SUSDE_25SEP2025, assetJoinAmount, alice);

        address USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector, alice, USDS, 1e18, 0
            )
        );
        vault.exitWithToken(USDS, 1e18, alice, alice, tokenHash);
    }

    function test_exitWithShares() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = 3.3e18;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4e18;
        uint256 debt1ExitAmount = 1.997372606735159818e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.4e18;
        exitWithShares(bob, bob, sharesExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_maxExitWithShares() public {
        joinWithShares(alice, 100e18, alice);

        uint256 max = vault.maxExitWithShares(alice);

        vm.startPrank(alice);
        USDC.approve(address(vault), 10_000_000e6);
        DAI.approve(address(vault), 10_000_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithShares.selector, alice, 100.001e18, 100e18
            )
        );
        vault.exitWithShares(max + 0.001e18, alice, alice, tokenHash);

        // Works ok for max
        assertEq(vault.balanceOf(alice), 100e18);
        exitWithShares(alice, alice, max, alice);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_join_targetLtv() public {
        joinWithToken(alice, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, alice);

        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();

        checkBalanceSheet(
            mkArray((adapter1Collateral + adapter2Collateral) * 4 / 3),
            mkArray(adapter1Debt * 4 / 3 - 1, adapter2Debt * 4 / 3 + 1)
        );

        assertEq(DAI.balanceOf(origamiMultisig), adapter1Debt);
        assertEq(USDC.balanceOf(origamiMultisig), adapter2Debt);
        assertEq(DAI.balanceOf(alice), adapter1Debt / 3 - 2);
        assertEq(USDC.balanceOf(alice), adapter2Debt / 3);

        joinWithToken(bob, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, bob);
        joinWithToken(bob, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, bob);

        assertEq(adapter1.currentLtv(), TARGET_LTV);
        assertEq(adapter2.currentLtv(), 0.849999997719233163e18);
    }
}

contract OpalVaultForkTestChangeAdapter is OpalVaultForkTestBase {
    function test_join_changeAdapters() public {
        vm.startPrank(origamiMultisig);
        adapter1.setDeprecated(true);
        manager.removeAdapter(address(adapter1));
        vm.stopPrank();

        vm.startPrank(alice);
        dealAsset(alice, 1_000_000e18);
        PT_SUSDE_25SEP2025.approve(address(vault), 1_000_000e18);

        // Old hash no longer works
        vm.expectRevert(abi.encodeWithSelector(ITokenizedBalanceSheetVault.IncorrectTokensHash.selector));
        vault.joinWithShares(100e18, bob, tokenHash);

        // Updated hash works, bob receives only the USDC no DAI
        vault.joinWithShares(100e18, bob, vault.currentTokensHash());
        assertEq(vault.balanceOf(bob), 100e18);
        assertEq(USDC.balanceOf(bob), 335.413506e6);
        assertEq(DAI.balanceOf(bob), 0);
    }

    function test_exit_changeAdapters() public {
        joinWithShares(alice, 100e18, alice);

        vm.startPrank(origamiMultisig);
        adapter1.setDeprecated(true);
        manager.removeAdapter(address(adapter1));

        // allowance for bob to burn alice's shares
        vm.startPrank(alice);
        vault.approve(bob, 100e18);

        vm.startPrank(bob);

        // Old hash no longer works
        vm.expectRevert(abi.encodeWithSelector(ITokenizedBalanceSheetVault.IncorrectTokensHash.selector));
        vault.exitWithShares(100e18, bob, alice, tokenHash);

        // Updated hash works, bob receives only the USDC no DAI
        doMint(USDC, bob, 83.853377e6);
        USDC.approve(address(vault), 83.853377e6);
        vault.exitWithShares(25e18, bob, alice, vault.currentTokensHash());

        assertEq(vault.balanceOf(alice), 75e18);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(USDC.balanceOf(alice), 335.413506e6);
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(alice), 499.343151683789954401e18);
        assertEq(DAI.balanceOf(bob), 0);
    }
}

contract OpalVaultForkTestJoinAndExitWithFees is OpalVaultForkTestBase {
    function setUp() public override {
        JOIN_FEE_BPS = 100;
        EXIT_FEE_BPS = 250;
        super.setUp();
    }

    function test_joinWithToken_asset() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesAmount = uint256(3.3e18) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithToken(alice, PT_SUSDE_25SEP2025, assetJoinAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_joinWithToken_debt1() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesAmount = uint256(3.3e18) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithToken(alice, DAI, debt1JoinAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_joinWithToken_debt2() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 32.99999791898660158e18;
        uint256 debt1JoinAmount = 16.478322966425279431e18;
        uint256 debt2JoinAmount = 11.068645e6;
        // share price is 1/10th right now
        uint256 sharesAmount = (assetJoinAmount / 10) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithToken(alice, USDC, debt2JoinAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_joinWithShares() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33.33333333333333334e18;
        uint256 debt1JoinAmount = 16.644771722792998483e18;
        uint256 debt2JoinAmount = 11.18045e6;
        uint256 sharesAmount = 3.3e18;
        joinWithShares(alice, sharesAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount),
            mkArray(seedLiabilities[0] + debt1JoinAmount, seedLiabilities[1] + debt2JoinAmount)
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount);

        assertEq(PT_SUSDE_25SEP2025.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), sharesAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesAmount);
    }

    function test_exitWithToken_asset() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = uint256(3.3e18) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4e18;
        uint256 debt1ExitAmount = 1.997372606735159823e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.410125350609377716e18;
        exitWithToken(bob, bob, PT_SUSDE_25SEP2025, assetExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_exitWithToken_debt1() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = uint256(3.3e18) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4e18 - 1;
        uint256 debt1ExitAmount = 1.997372606735159818e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.410125350609377715e18;
        exitWithToken(bob, bob, DAI, debt1ExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_exitWithToken_debt2() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = uint256(3.3e18) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 4.000002917899225348e18;
        uint256 debt1ExitAmount = 1.997374063768155299e18;
        uint256 debt2ExitAmount = 1.341655e6;
        uint256 sharesExitAmount = 0.410125649785488425e18;
        exitWithToken(bob, bob, USDC, debt2ExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_exitWithShares() public {
        (uint256[] memory seedAssets, uint256[] memory seedLiabilities) = vault.balanceSheet();

        uint256 assetJoinAmount = 33e18;
        uint256 debt1JoinAmount = 16.478324005565068495e18;
        uint256 debt2JoinAmount = 11.068645e6;
        uint256 sharesJoinAmount = uint256(3.3e18) * (10_000 - JOIN_FEE_BPS) / 10_000;
        joinWithShares(alice, sharesJoinAmount, bob);

        uint256 assetExitAmount = 3.901246283904829229e18;
        uint256 debt1ExitAmount = 1.94806061489971103e18;
        uint256 debt2ExitAmount = 1.308531e6;
        uint256 sharesExitAmount = 0.4e18;
        exitWithShares(bob, bob, sharesExitAmount, bob);

        checkBalanceSheet(
            mkArray(seedAssets[0] + assetJoinAmount - assetExitAmount),
            mkArray(
                seedLiabilities[0] + debt1JoinAmount - debt1ExitAmount,
                seedLiabilities[1] + debt2JoinAmount - debt2ExitAmount
            )
        );
        assertEq(DAI.balanceOf(bob), debt1JoinAmount - debt1ExitAmount);
        assertEq(USDC.balanceOf(bob), debt2JoinAmount - debt2ExitAmount);
        assertEq(vault.balanceOf(bob), sharesJoinAmount - sharesExitAmount);
        assertEq(vault.totalSupply(), SEED_SHARES_AMOUNT + sharesJoinAmount - sharesExitAmount);
    }

    function test_join_targetLtv() public {
        joinWithToken(alice, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, alice);

        (uint256 adapter1Collateral, uint256 adapter1Debt, uint256 adapter2Collateral, uint256 adapter2Debt) =
            seedAmounts();

        checkBalanceSheet(
            mkArray((adapter1Collateral + adapter2Collateral) * 4 / 3),
            mkArray(adapter1Debt * 4 / 3 - 1, adapter2Debt * 4 / 3 + 1)
        );

        assertEq(DAI.balanceOf(origamiMultisig), adapter1Debt);
        assertEq(USDC.balanceOf(origamiMultisig), adapter2Debt);
        assertEq(DAI.balanceOf(alice), adapter1Debt / 3 - 2);
        assertEq(USDC.balanceOf(alice), adapter2Debt / 3);

        joinWithToken(bob, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, bob);
        joinWithToken(bob, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, bob);

        assertEq(adapter1.currentLtv(), TARGET_LTV);
        assertEq(adapter2.currentLtv(), 0.849999997719233163e18);
    }

    function test_exit_targetLtv() public {
        joinWithToken(alice, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT, alice);

        exitWithToken(alice, alice, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, alice);
        exitWithToken(alice, alice, PT_SUSDE_25SEP2025, SEED_PT_SUSDE_25SEP2025_AMOUNT / 3, alice);

        assertEq(adapter1.currentLtv(), TARGET_LTV);
        assertEq(adapter2.currentLtv(), 0.849999999619872194e18);
    }
}
