pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { VanillaOrigamiTokenizedBalanceSheetVaultTestBase } from "test/foundry/unit/common/tokenizedBalanceSheet/VanillaOrigamiTokenizedBalanceSheetVault.t.sol";
import { Interactor } from "test/foundry/mocks/common/tokenizedBalanceSheet/TokenizedBalanceSheetInteractor.m.sol";
import { TokenizedBalanceSheetVaultTest } from "test/foundry/invariant/investments/tokenizedBalanceSheet/TokenizedBalanceSheetVault.test.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

import { StdInvariant } from "forge-std/StdInvariant.sol";

contract VanillaOrigamiTokenizedBalanceSheetVaultFuzzTest is VanillaOrigamiTokenizedBalanceSheetVaultTestBase, TokenizedBalanceSheetVaultTest {
    Interactor[N] private users;

    mapping(address token => uint256 ratio) private exchangeRatios;

    function setUp() public virtual override(VanillaOrigamiTokenizedBalanceSheetVaultTestBase) {
        super.setUp();

        _vault_ = vault;
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;

        address[] memory liabilities = vault.liabilityTokens();
        for (uint256 i; i < liabilities.length; i++){
            DummyMintableTokenPermissionless(liabilities[i]).deal(address(borrowLend), type(uint200).max);
        }

        for (uint256 i; i < N; i++){
            users[i] = new Interactor(vault, borrowLend);
            vm.label(address(users[i]), string.concat("USER-", vm.toString(i)));

            targetContract(address(users[i]));
        }
    }

    function setUpYield(uint32[N] memory yield) internal override {
        increaseSharePrice(yield[0], yield[1], yield[2], yield[3]);
    }

    function invariant_totalAssetsConsistency() public view {
        uint256 totalShares = vault.balanceOf(origamiMultisig);

        for (uint256 i; i < N; i++){
            totalShares += vault.balanceOf(address(users[i]));
        }
        assertEq(totalShares, vault.totalSupply());
    }

    function invariant_whenYieldIncreasesAssetSharePriceAlsoDoes() public {
        (
        uint256[] memory totalAssets, 
        uint256[] memory totalLiabilities
        ) = vault.balanceSheet();

        uint256 totalSupply = vault.totalSupply();

        uint256 asset1Ratio = totalAssets[0] * 1e18 / totalSupply;
        uint256 asset2Ratio = totalAssets[1] * 1e18 / totalSupply;
        uint256 debt1Ratio = totalLiabilities[0] * 1e18 / totalSupply;
        uint256 debt2Ratio = totalLiabilities[1] * 1e18 / totalSupply;   

        if (exchangeRatios[address(asset1)] != 0) {
            assertGt(asset1Ratio, exchangeRatios[address(asset1)], "asset1");
            assertGt(asset2Ratio, exchangeRatios[address(asset2)], "asset2");
        }
        
        if (exchangeRatios[address(debt1)] != 0) {
            assertLt(debt1Ratio, exchangeRatios[address(debt1)], "liability1");
            assertLt(debt2Ratio, exchangeRatios[address(debt2)], "liability2");
        }

        exchangeRatios[address(asset1)] = asset1Ratio;
        exchangeRatios[address(asset2)] = asset2Ratio;
        exchangeRatios[address(debt1)] = debt1Ratio;
        exchangeRatios[address(debt2)] = debt2Ratio;
    }

    function invariant_previewJoinWithTokenAlwaysTakesExactInput() public view {
        uint256 amount;
        amount = _bound(amount, 1, type(uint256).max);

        (, uint256[] memory assets1,) = vault.previewJoinWithToken(address(asset1), amount);
        (, uint256[] memory assets2,) = vault.previewJoinWithToken(address(asset2), amount);
        (,, uint256[] memory liabilities1) = vault.previewJoinWithToken(address(debt1), amount);
        (,, uint256[] memory liabilities2) = vault.previewJoinWithToken(address(debt2), amount);

        assertEq(assets1[0], amount, "asset1");
        assertEq(assets2[1], amount, "asset2");
        assertEq(liabilities1[0], amount, "liability1");
        assertEq(liabilities2[1], amount, "liability2");
    }

    function invariant_previewExitWithTokenAlwaysGiveExactOutput() public view {
        uint256 amount;
        amount = _bound(amount, 1, type(uint256).max);

        (, uint256[] memory assets1,) = vault.previewExitWithToken(address(asset1), amount);
        (, uint256[] memory assets2,) = vault.previewExitWithToken(address(asset2), amount);
        (,, uint256[] memory liabilities1) = vault.previewExitWithToken(address(debt1), amount);
        (,, uint256[] memory liabilities2) = vault.previewExitWithToken(address(debt2), amount);

        assertEq(assets1[0], amount, "asset1");
        assertEq(assets2[1], amount, "asset2");
        assertEq(liabilities1[0], amount, "liability1");
        assertEq(liabilities2[1], amount, "liability2");
    }

    function _excludeSelector(bytes4[] memory selectors) internal {
        StdInvariant.FuzzSelector memory excludedSelector = StdInvariant.FuzzSelector({
            addr: address(0), 
            selectors: selectors
        });

        for (uint256 i; i < N; i++) {
            excludedSelector.addr = address(users[i]);
            excludeSelector(excludedSelector);
        }
    }
}

contract VanillaOrigamiTokenizedBalanceSheetVaultFuzzTestWithoutSharePrice is VanillaOrigamiTokenizedBalanceSheetVaultFuzzTest {
    uint256 internal asset1Ratio;
    uint256 internal asset2Ratio;
    uint256 internal liab1Ratio;
    uint256 internal liab2Ratio;

    function setUp() public override {
        VanillaOrigamiTokenizedBalanceSheetVaultFuzzTest.setUp();

        // Need to be excluded in the setUp() -- doesn't work if done in the invariant test itself.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Interactor.increaseSharePrice.selector;
        _excludeSelector(selectors);

        asset1Ratio = SEED_ASSET1 * 1e18 / SEED_SHARES;
        asset2Ratio = SEED_ASSET2 * 1e18 / SEED_SHARES;
        liab1Ratio =  SEED_LIABILITY1 * 1e18 / SEED_SHARES;
        liab2Ratio =  SEED_LIABILITY2 * 1e18 / SEED_SHARES;
    }

    function invariant_alwaysHoldsTheExchangeRateUntilYield() public view {
        (
            uint256[] memory totalAssets, 
            uint256[] memory totalLiabilities
        ) = vault.balanceSheet();
        uint256 totalSupply = vault.totalSupply();

        if (totalSupply > 0) {
            // Might have slight rounding diffs depending on token balances
            assertApproxEqAbs(totalAssets[0] * 1e18 / totalSupply, asset1Ratio, 1, "asset1");
            assertApproxEqAbs(totalAssets[1] * 1e18 / totalSupply, asset2Ratio, 1, "asset1");
            assertApproxEqAbs(totalLiabilities[0] * 1e18 / totalSupply, liab1Ratio, 1, "liability1");
            assertApproxEqAbs(totalLiabilities[1] * 1e18 / totalSupply, liab2Ratio, 1, "liability2");
        }
    }
}
