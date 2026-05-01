pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase } from "test/foundry/unit/common/tokenizedBalanceSheet/DynamicAssetsTokenizedBalanceSheetVault.t.sol";
import { TokenizedBalanceSheetVaultTest } from "test/foundry/invariant/investments/tokenizedBalanceSheet/TokenizedBalanceSheetVault.test.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

contract DynamicAssetsTokenizedBalanceSheetVaultFuzzTest is DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase, TokenizedBalanceSheetVaultTest {
    function setUp() public override(DynamicTokensOrigamiTokenizedBalanceSheetVaultTestBase) {
        super.setUp();

        _vault_ = vault;
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;

        address[] memory liabilities = vault.liabilityTokens();

        for (uint256 i; i < liabilities.length; i++){
            DummyMintableTokenPermissionless(liabilities[i]).deal(address(borrowLend), type(uint160).max);
        }
    }
    
    function setUpBalances(Init memory init) internal override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        super.setUpBalances(init);

        assetTokens = vault.assetTokens();
        (uint256[] memory assetsBalances, ) = vault.balanceSheet();

        (address asset1New, address asset2New) = doRollover(assetTokens, assetsBalances, 0, 0);

        for (uint256 i; i < init.user.length; i++) {
            DummyMintableTokenPermissionless(asset1New).deal(init.user[i], type(uint160).max);
            DummyMintableTokenPermissionless(asset2New).deal(init.user[i], type(uint160).max);
        }

        //note: refresh assetTokens/liabilityTokens after rollover
        assetTokens = vault.assetTokens();
        liabilityTokens = vault.liabilityTokens();
    }

    //dev: here we are assuming a different configuration in the balance sheet, either all the old assets are removed, or only a token or two
    function _randomizeToken(
        bool isAsset,
        uint32 tokenIndex,
        address[] memory assets,
        address[] memory liabilities
    ) internal view override returns (
        address randomToken,
        uint256 randomIndex
    ) {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = vault.balanceSheet();
        address[] memory tokens = isAsset ? assets : liabilities;
        uint256[] memory balances = isAsset ? totalAssets : totalLiabilities;

        uint256 countNonZero = 0;
        uint256[] memory nonZeroIndexes = new uint256[](tokens.length);

        // Filter only non-zero balance tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (balances[i] > 0) {
                nonZeroIndexes[countNonZero] = i;
                countNonZero++;
            }
        }

        // Select a random non-zero token using tokenIndex
        randomIndex = nonZeroIndexes[tokenIndex % countNonZero];
        randomToken = tokens[randomIndex];
    }
}