pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { MockTokenizedBalanceSheetVaultWithFees } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockTokenizedBalanceSheetVaultWithFees.m.sol";
import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";

contract OrigamiTokenizedBalanceSheetVaultCommon is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableTokenPermissionless internal asset1;
    DummyMintableTokenPermissionless internal asset2;
    DummyMintableTokenPermissionless internal debt1;
    DummyMintableTokenPermissionless internal debt2;
    MockTokenizedBalanceSheetVaultWithFees internal vault;
    MockBorrowLend internal borrowLend;

    uint256 internal constant MAX_TOTAL_SUPPLY = 100_000_000e18;
    uint16 internal immutable JOIN_FEE = 50;
    uint16 internal immutable EXIT_FEE = 200;

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

    function setUpWithFees(uint16 joinFeeBps, uint16 exitFeeBps) internal {
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

        vault = new MockTokenizedBalanceSheetVaultWithFees(
            origamiMultisig, 
            "TokenizedBalanceSheet",
            "TBSV",
            _assets,
            _liabilities,
            joinFeeBps,
            exitFeeBps,
            borrowLend
        );
        vm.label(address(vault), vault.symbol());
        
        vm.warp(100000000);
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
}