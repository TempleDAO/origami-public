pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibString } from "solady/utils/LibString.sol";

import {
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OpalTestSetup } from "test/foundry/unit/investments/opal/OpalTestSetup.t.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";

import {
    MockMoneyMarketOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockMoneyMarketOpalAdapter.m.sol";

abstract contract OpalVaultMaxJoinExitBaseTest is OpalTestSetup {
    MockMoneyMarketOpalAdapter internal adapterImpl;

    MockMoneyMarketOpalAdapter[] internal adapters;

    struct AdapterConfig {
        address asset1;
        address liability1;
        bytes32 groupId;
    }

    uint256 internal SEED_SHARES_AMOUNT = 1_000_000e18;
    uint256 internal MAX_TOTAL_SUPPLY = type(uint256).max;

    function setUp() public virtual override {
        OpalTestSetup.setUp();

        vm.startPrank(origamiMultisig);
        adapterImpl = new MockMoneyMarketOpalAdapter("MOCK.1");
        adapterFactory.addImplementation(address(adapterImpl));
        addAdapters();
        seedDeposit();
        vm.stopPrank();
    }

    function addAdapters() internal virtual;

    function seedAmounts() internal view virtual returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed);

    function perAdapterSeed() internal view virtual returns (IOpalManager.AssetsAndLiabilities[] memory perAdapterBS) {
        perAdapterBS = new IOpalManager.AssetsAndLiabilities[](adapters.length);
        (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed) = seedAmounts();

        require(assetsSeed.length == adapters.length, "Invalid perAdapterSeed asset length");
        require(liabilitiesSeed.length == adapters.length, "Invalid perAdapterSeed liabilities length");
        for (uint256 i; i < adapters.length; ++i) {
            perAdapterBS[i].assets = mkArray(assetsSeed[i]);
            perAdapterBS[i].liabilities = mkArray(liabilitiesSeed[i]);
        }
    }

    function addAdapters(AdapterConfig[] memory adapterConfigs) internal {
        for (uint256 i; i < adapterConfigs.length; ++i) {
            string memory description = LibString.concat("ADAPTER.", LibString.toString(i));
            AdapterConfig memory config = adapterConfigs[i];
            address instance = manager.addAdapter(
                address(adapterImpl),
                LibString.toSmallString(description),
                adapterImpl.encodeImmutableArgs(config.asset1, config.liability1, config.groupId),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            );
            vm.label(instance, description);
            adapters.push(MockMoneyMarketOpalAdapter(instance));
        }
    }

    function seedDeposit() internal {
        address[] memory assetTokens = manager.assetTokens();
        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = seedAmounts();
        require(assetTokens.length == assetAmounts.length, "bad assetAmounts length");
        require(assetTokens.length == liabilityAmounts.length, "bad liabilityAmounts length");

        for (uint256 i; i < assetTokens.length; ++i) {
            deal(assetTokens[i], origamiMultisig, assetAmounts[i]);
            IERC20(assetTokens[i]).approve(address(vault), assetAmounts[i]);
        }

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet = perAdapterSeed();

        vault.seed(
            assetAmounts,
            liabilityAmounts,
            SEED_SHARES_AMOUNT,
            origamiMultisig,
            MAX_TOTAL_SUPPLY,
            abi.encode(perAdapterBalanceSheet)
        );
    }

    function mkArray(AdapterConfig memory v1) internal pure returns (AdapterConfig[] memory arr) {
        arr = new AdapterConfig[](1);
        arr[0] = v1;
    }

    function mkArray(AdapterConfig memory v1, AdapterConfig memory v2, AdapterConfig memory v3)
        internal
        pure
        returns (AdapterConfig[] memory arr)
    {
        arr = new AdapterConfig[](3);
        arr[0] = v1;
        arr[1] = v2;
        arr[2] = v3;
    }
}

contract OpalVaultMaxJoinExitNoAdaptersTest is OpalTestSetup {
    function test_maxJoin() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.maxJoinWithShares(address(0)), 0);
        assertEq(vault.maxJoinWithToken(ASSET1, address(0)), 0);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(0);
        assertEq(previewAssets.length, 0);
        assertEq(previewLiabilities.length, 0);

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, 0);
        assertEq(previewShares, 0);
        assertEq(previewAssets.length, 0);
        assertEq(previewLiabilities.length, 0);
    }

    function test_maxExit() public view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.maxExitWithShares(address(0)), type(uint256).max);
        assertEq(vault.maxExitWithToken(ASSET1, address(0)), 0);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(0);
        assertEq(previewAssets.length, 0);
        assertEq(previewLiabilities.length, 0);

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, 0);
        assertEq(previewShares, 0);
        assertEq(previewAssets.length, 0);
        assertEq(previewLiabilities.length, 0);
    }
}

contract OpalVaultMaxJoinExitBasic18dpTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1 = 997_700e18;
    uint256 internal SEED_DEBT1 = 596_000e18;

    function addAdapters() internal override {
        addAdapters(mkArray(AdapterConfig(ASSET1, DEBT1, "GROUPID_1")));

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT1, address(adapters[0].mockMorpho()), 1_000_000e18);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1);
        liabilitiesSeed = mkArray(SEED_DEBT1);
    }

    function test_maxJoinWithToken_noSupplyCap_noAdapterCap() public {
        uint256 adapterCap = type(uint256).max;

        for (uint256 i; i < adapters.length; ++i) {
            vm.mockCall(
                address(adapters[i]),
                abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
                abi.encode(mkArray(adapterCap), mkArray(adapterCap))
            );
        }

        assertEq(vault.maxJoinWithToken(ASSET1, address(0)), adapterCap);
        assertEq(vault.maxJoinWithToken(DEBT1, address(0)), adapterCap);
        assertEq(vault.maxJoinWithToken(DEBT4, address(0)), 0);
    }

    function test_maxJoinWithToken_noSupplyCap_noAdapterCap_withJoinFee() public {
        vm.prank(origamiMultisig);
        manager.setFees(100, 100);

        uint256 adapterCap = type(uint256).max;

        for (uint256 i; i < adapters.length; ++i) {
            vm.mockCall(
                address(adapters[i]),
                abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
                abi.encode(mkArray(adapterCap), mkArray(adapterCap))
            );
        }

        assertEq(vault.maxJoinWithToken(ASSET1, address(0)), adapterCap);
        assertEq(vault.maxJoinWithToken(DEBT1, address(0)), adapterCap);
        assertEq(vault.maxJoinWithToken(DEBT4, address(0)), 0);
        assertEq(vault.maxJoinWithShares(address(0)), type(uint256).max);
    }

    function test_maxJoinWithToken_noSupplyCap_zeroAvailableCap() public {
        uint256 adapterCap = 0;

        for (uint256 i; i < adapters.length; ++i) {
            vm.mockCall(
                address(adapters[i]),
                abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
                abi.encode(mkArray(adapterCap), mkArray(adapterCap))
            );
        }

        assertEq(vault.maxJoinWithToken(ASSET1, address(0)), adapterCap);
        assertEq(vault.maxJoinWithToken(DEBT1, address(0)), adapterCap);
        assertEq(vault.maxJoinWithToken(DEBT4, address(0)), 0);
    }

    function test_maxExitWithToken_noSupplyCap_noAdapterCap() public {
        uint256 adapterCap = type(uint256).max;

        for (uint256 i; i < adapters.length; ++i) {
            vm.mockCall(
                address(adapters[i]),
                abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
                abi.encode(mkArray(adapterCap), mkArray(adapterCap))
            );
        }

        assertEq(vault.maxExitWithToken(ASSET1, address(0)), adapterCap);
        assertEq(vault.maxExitWithToken(DEBT1, address(0)), adapterCap);
        assertEq(vault.maxExitWithToken(DEBT4, address(0)), 0);
    }

    function test_maxExitWithToken_noSupplyCap_noAdapterCap_withExitFee() public {
        vm.prank(origamiMultisig);
        manager.setFees(100, 100);

        uint256 adapterCap = type(uint256).max;

        for (uint256 i; i < adapters.length; ++i) {
            vm.mockCall(
                address(adapters[i]),
                abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
                abi.encode(mkArray(adapterCap), mkArray(adapterCap))
            );
        }

        assertEq(vault.maxExitWithToken(ASSET1, address(0)), adapterCap);
        assertEq(vault.maxExitWithToken(DEBT1, address(0)), adapterCap);
        assertEq(vault.maxExitWithToken(DEBT4, address(0)), 0);
        assertEq(vault.maxExitWithShares(address(0)), type(uint256).max);
    }

    function test_maxExitWithToken_noSupplyCap_zeroAvailableCap() public {
        uint256 adapterCap = 0;

        for (uint256 i; i < adapters.length; ++i) {
            vm.mockCall(
                address(adapters[i]),
                abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
                abi.encode(mkArray(adapterCap), mkArray(adapterCap))
            );
        }

        assertEq(vault.maxExitWithToken(ASSET1, address(0)), adapterCap);
        assertEq(vault.maxExitWithToken(DEBT1, address(0)), adapterCap);
        assertEq(vault.maxExitWithToken(DEBT4, address(0)), 0);
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 333.333333333333333333e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        assertEq(maxJoinWithAsset1, adapterMaxJoinAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));
        assertEq(maxJoinWithDebt1, adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares - 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 2); // 2 under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], adapterMaxJoinAssets[0]); // over
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // matches
        assertLt(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // under
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1 + 1);
        assertGt(previewAssets[0], adapterMaxJoinAssets[0]); // over
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap_withExitFee() public {
        vm.prank(origamiMultisig);
        manager.setFees(100, 100);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );

        assertEq(vault.maxJoinWithShares(address(0)), 329.999999999999999999e18);
        assertEq(vault.maxJoinWithToken(ASSET1, address(0)), 332.566666666666666666e18);
        assertEq(vault.maxJoinWithToken(DEBT1, address(0)), 198.666666666666666666e18);
    }

    function test_fuzz_maxJoinWithToken_noSupplyCap_withAdapterCap(uint256 maxJoinAssetCap, uint256 maxJoinLiabilityCap)
        public
    {
        maxJoinAssetCap = bound(maxJoinAssetCap, 0, SEED_ASSET1 + 1e18);
        maxJoinLiabilityCap = bound(maxJoinLiabilityCap, 0, SEED_DEBT1 + 1e18);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(maxJoinAssetCap), mkArray(maxJoinLiabilityCap))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);
    }

    function test_maxJoinWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18
        vm.startPrank(origamiMultisig);
        vault.setMaxTotalSupply(1_000_000e18 + 300e18); // 300 more than now
        vm.stopPrank();

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 300e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        assertEq(maxJoinWithAsset1, 299.31e18);
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));
        assertEq(maxJoinWithDebt1, 178.8e18);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // matches
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // matches
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertGt(previewLiabilities[0], maxJoinWithDebt1); // over
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 333.333333333333333333e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, address(0));
        assertEq(maxExitWithAsset1, adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, address(0));
        assertEq(maxExitWithDebt1, adapterMaxExitLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares - 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 2); // 2 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0] - 1); // equals the underlying adapter max

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertGt(previewLiabilities[0], adapterMaxExitLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertGt(previewLiabilities[0], adapterMaxExitLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1 + 1);
        assertLt(previewAssets[0], adapterMaxExitAssets[0]); // under
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // matches
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap_withExitFee() public {
        vm.prank(origamiMultisig);
        manager.setFees(100, 100);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );

        assertEq(vault.maxExitWithShares(address(0)), 336.700336700336700337e18);
        assertEq(vault.maxExitWithToken(ASSET1, address(0)), 332.566666666666666666e18);
        assertEq(vault.maxExitWithToken(DEBT1, address(0)), 198.666666666666666666e18);
    }

    function test_fuzz_maxExitWithToken_noSupplyCap_withAdapterCap(uint256 maxExitAssetCap, uint256 maxExitLiabilityCap)
        public
    {
        maxExitAssetCap = bound(maxExitAssetCap, 0, SEED_ASSET1 + 1e18);
        maxExitLiabilityCap = bound(maxExitLiabilityCap, 0, SEED_DEBT1 + 1e18);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(maxExitAssetCap), mkArray(maxExitLiabilityCap))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, address(0));
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);
    }

    function test_maxExitWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18

        // Undelrying cap is much higher than the 1mm in the vault to max withdraw
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18 * 10_000), mkArray(198.666666666666666667e18 * 10_000))
        );

        // Use the origami multisig since it has the full balance of shares (1mm shares)
        uint256 maxExitWithShares = vault.maxExitWithShares(origamiMultisig);
        assertEq(maxExitWithShares, 1_000_000e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, origamiMultisig);
        assertEq(maxExitWithAsset1, 997_700e18);
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, origamiMultisig);
        assertEq(maxExitWithDebt1, 596_000e18);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1 + 1);
        assertGt(previewAssets[0], maxExitWithAsset1); // over
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1 + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
    }
}

contract OpalVaultMaxJoinExit6dpAssetTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1_6DP = 997_700e6;
    uint256 internal SEED_DEBT1 = 596_000e18;

    function addAdapters() internal override {
        addAdapters(mkArray(AdapterConfig(ASSET1_6DP, DEBT1, "GROUPID_1")));

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT1, address(adapters[0].mockMorpho()), 1_000_000e18);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1_6DP);
        liabilitiesSeed = mkArray(SEED_DEBT1);
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e6
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566667e6
        // forced max liabilities = 198.666666666666666667e18
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566667e6), mkArray(198.666666666666666667e18))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 333.333333333333333333e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1_6DP, address(0));
        assertEq(maxJoinWithAsset1, adapterMaxJoinAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));
        assertEq(maxJoinWithDebt1, adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAsset1);
        assertEq(previewShares, 333.333332665129798536e18);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0] - 1); // equals the underlying adapter max
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertEq(previewLiabilities[0], 198.666666268417359927e18); // 1 under the underlying adapter max
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // equals the underlying adapter max
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // matches
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // matches
        assertGt(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1 + 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // matches
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
    }

    function test_fuzz_maxJoinWithToken_noSupplyCap_withAdapterCap(uint256 maxJoinAssetCap, uint256 maxJoinLiabilityCap)
        public
    {
        maxJoinAssetCap = bound(maxJoinAssetCap, 0, SEED_ASSET1_6DP + 1e6);
        maxJoinLiabilityCap = bound(maxJoinLiabilityCap, 0, SEED_DEBT1 + 1e18);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(maxJoinAssetCap), mkArray(maxJoinLiabilityCap))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1_6DP, address(0));
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAsset1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);
    }

    function test_maxJoinWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e6
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566667e6
        // forced max liabilities = 198.666666666666666667e18
        vm.startPrank(origamiMultisig);
        vault.setMaxTotalSupply(1_000_000e18 + 300e18); // 300 more than now
        vm.stopPrank();

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566667e6), mkArray(198.666666666666666667e18))
        );

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 300e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1_6DP, address(0));
        assertEq(maxJoinWithAsset1, 299.31e6);
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));
        assertEq(maxJoinWithDebt1, 178.8e18);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // matches
        (previewShares, previewAssets, previewLiabilities) =
            vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAsset1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertGt(previewLiabilities[0], maxJoinWithDebt1); // over
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertGt(previewLiabilities[0], maxJoinWithDebt1); // over
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e6
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566667e6
        // forced max liabilities = 198.666666666666666667e18
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566667e6), mkArray(198.666666666666666667e18))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 333.333333333333333333e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1_6DP, address(0));
        assertEq(maxExitWithAsset1, adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, address(0));
        assertEq(maxExitWithDebt1, adapterMaxExitLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAsset1);
        assertEq(previewShares, 333.333332665129798537e18); // A bit under the underlying adapter max
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], 198.666666268417359929e18); // A bit under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares - 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0] - 1); // equals the underlying adapter max

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertLt(previewAssets[0], adapterMaxExitAssets[0]); // under
        assertGt(previewLiabilities[0], adapterMaxExitLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertGt(previewLiabilities[0], adapterMaxExitLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1 + 1);
        assertLt(previewAssets[0], adapterMaxExitAssets[0]); // under
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // matches
    }

    function test_fuzz_maxExitWithToken_noSupplyCap_withAdapterCap(uint256 maxExitAssetCap, uint256 maxExitLiabilityCap)
        public
    {
        maxExitAssetCap = bound(maxExitAssetCap, 0, SEED_ASSET1_6DP + 1e6);
        maxExitLiabilityCap = bound(maxExitLiabilityCap, 0, SEED_DEBT1 + 1e18);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(maxExitAssetCap), mkArray(maxExitLiabilityCap))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1_6DP, address(0));
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAsset1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);
    }

    function test_maxExitWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e6
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566667e6
        // forced max liabilities = 198.666666666666666667e18

        // Undelrying cap is much higher than the 1mm in the vault to max withdraw
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566667e6 * 10_000), mkArray(198.666666666666666667e18 * 10_000))
        );

        // Use the origami multisig since it has the full balance of shares (1mm shares)
        uint256 maxExitWithShares = vault.maxExitWithShares(origamiMultisig);
        assertEq(maxExitWithShares, 1_000_000e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1_6DP, origamiMultisig);
        assertEq(maxExitWithAsset1, 997_700e6);
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, origamiMultisig);
        assertEq(maxExitWithDebt1, 596_000e18);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAsset1 + 1);
        assertGt(previewAssets[0], maxExitWithAsset1); // over
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1 + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
    }
}

contract OpalVaultMaxJoinExit6dpLiabilityTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1 = 997_700e18;
    uint256 internal SEED_DEBT1_6DP = 596_000e6;

    function addAdapters() internal override {
        addAdapters(mkArray(AdapterConfig(ASSET1, DEBT1_6DP, "GROUPID_1")));

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT1_6DP, address(adapters[0].mockMorpho()), 1_000_000e6);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1);
        liabilitiesSeed = mkArray(SEED_DEBT1_6DP);
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e6
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666667e6
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666667e6))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 333.333333333333333333e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        assertEq(maxJoinWithAsset1, adapterMaxJoinAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1_6DP, address(0));
        assertEq(maxJoinWithDebt1, adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares - 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0] - 1); // 1 under the underlying adapter max
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebt1);
        assertEq(previewShares, 333.333332214765100672e18);
        assertEq(previewAssets[0], 332.566665550671140941e18); // a bit more under adapter max due to rounding
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], adapterMaxJoinAssets[0]); // over
        assertLt(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // under
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // matches
        assertLt(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // under
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebt1 + 1);
        assertGt(previewAssets[0], adapterMaxJoinAssets[0]); // over
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
    }

    function test_fuzz_maxJoinWithToken_noSupplyCap_withAdapterCap(uint256 maxJoinAssetCap, uint256 maxJoinLiabilityCap)
        public
    {
        maxJoinAssetCap = bound(maxJoinAssetCap, 0, SEED_ASSET1 + 1e18);
        maxJoinLiabilityCap = bound(maxJoinLiabilityCap, 0, SEED_DEBT1_6DP + 1e6);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(maxJoinAssetCap), mkArray(maxJoinLiabilityCap))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1_6DP, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebt1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);
    }

    function test_maxJoinWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e6
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666667e6
        vm.startPrank(origamiMultisig);
        vault.setMaxTotalSupply(1_000_000e18 + 300e18); // 300 more than now
        vm.stopPrank();

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666667e6))
        );

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 300e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        assertEq(maxJoinWithAsset1, 299.31e18);
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1_6DP, address(0));
        assertEq(maxJoinWithDebt1, 178.8e6);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // matches
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // matches
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebt1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertGt(previewLiabilities[0], maxJoinWithDebt1); // over
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e6
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666667e6
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666667e6))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 333.333333333333333333e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, address(0));
        assertEq(maxExitWithAsset1, adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1_6DP, address(0));
        assertEq(maxExitWithDebt1, adapterMaxExitLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebt1);
        assertEq(previewShares, 333.333332214765100671e18); // a bit under the underlying adapter max
        assertEq(previewAssets[0], 332.566665550671140939e18); // a bit under the underlying adapter max
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0] - 1); // 1 under the underlying adapter max
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // matches
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // matches
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebt1 + 1);
        assertGt(previewAssets[0], adapterMaxExitAssets[0]); // over
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // matches
    }

    function test_fuzz_maxExitWithToken_noSupplyCap_withAdapterCap(uint256 maxExitAssetCap, uint256 maxExitLiabilityCap)
        public
    {
        maxExitAssetCap = bound(maxExitAssetCap, 0, SEED_ASSET1 + 1e18);
        maxExitLiabilityCap = bound(maxExitLiabilityCap, 0, SEED_DEBT1_6DP + 1e6);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(maxExitAssetCap), mkArray(maxExitLiabilityCap))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, address(0));
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1_6DP, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebt1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);
    }

    function test_maxExitWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e6
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666667e6

        // Undelrying cap is much higher than the 1mm in the vault to max withdraw
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18 * 10_000), mkArray(198.666667e6 * 10_000))
        );

        // Use the origami multisig since it has the full balance of shares (1mm shares)
        uint256 maxExitWithShares = vault.maxExitWithShares(origamiMultisig);
        assertEq(maxExitWithShares, 1_000_000e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, origamiMultisig);
        assertEq(maxExitWithAsset1, 997_700e18);
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1_6DP, origamiMultisig);
        assertEq(maxExitWithDebt1, 596_000e6);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1 + 1);
        assertGt(previewAssets[0], maxExitWithAsset1); // over
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebt1 + 1);
        assertGt(previewAssets[0], maxExitWithAsset1); // over
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
    }
}

contract OpalVaultMaxJoinExitBasic18dpWithShareFeesTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1 = 997_700e18;
    uint256 internal SEED_DEBT1 = 596_000e18;

    function setUp() public virtual override {
        OpalVaultMaxJoinExitBaseTest.setUp();

        vm.prank(origamiMultisig);
        manager.setFees(113, 223);
    }

    function addAdapters() internal override {
        addAdapters(mkArray(AdapterConfig(ASSET1, DEBT1, "GROUPID_1")));

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT1, address(adapters[0].mockMorpho()), 1_000_000e18);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1);
        liabilitiesSeed = mkArray(SEED_DEBT1);
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 329.566666666666666666e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        assertEq(maxJoinWithAsset1, adapterMaxJoinAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));
        assertEq(maxJoinWithDebt1, adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // 1 under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares - 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0] - 1); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 2); // 1 under the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0] - 1); // equals the underlying adapter max

        // // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], adapterMaxJoinAssets[0]); // over
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxJoinAssets[0]); // matches
        assertLt(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // under
        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1 + 1);
        assertGt(previewAssets[0], adapterMaxJoinAssets[0]); // over
        assertEq(previewLiabilities[0], adapterMaxJoinLiabilities[0]); // matches
    }

    function test_fuzz_maxJoinWithToken_noSupplyCap_withAdapterCap(uint256 maxJoinAssetCap, uint256 maxJoinLiabilityCap)
        public
    {
        maxJoinAssetCap = bound(maxJoinAssetCap, 0, SEED_ASSET1 + 1e18);
        maxJoinLiabilityCap = bound(maxJoinLiabilityCap, 0, SEED_DEBT1 + 1e18);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(maxJoinAssetCap), mkArray(maxJoinLiabilityCap))
        );
        (uint256[] memory adapterMaxJoinAssets, uint256[] memory adapterMaxJoinLiabilities) = adapters[0].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertLe(previewAssets[0], adapterMaxJoinAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxJoinLiabilities[0]);
    }

    function test_maxJoinWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18
        vm.startPrank(origamiMultisig);
        vault.setMaxTotalSupply(1_000_000e18 + 300e18); // 300 more than now
        vm.stopPrank();

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 300e18);
        uint256 maxJoinWithAsset1 = vault.maxJoinWithToken(ASSET1, address(0));
        assertEq(maxJoinWithAsset1, 302.730858703347830485e18);
        uint256 maxJoinWithDebt1 = vault.maxJoinWithToken(DEBT1, address(0));
        assertEq(maxJoinWithDebt1, 180.843531910589663194e18);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
        assertEq(previewAssets[0], maxJoinWithAsset1 + 1); // 1 more than the total supply based cap (but thats ok)
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1);
        assertEq(previewShares, maxJoinWithShares - 1); // 1 less than the total supply based cap
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1);
        assertEq(previewShares, maxJoinWithShares - 1); // 1 less than the total supply based cap
        assertEq(previewAssets[0], maxJoinWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertGt(previewLiabilities[0], maxJoinWithDebt1); // over
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1, maxJoinWithAsset1 + 1);
        assertEq(previewShares, maxJoinWithShares); // matches
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertEq(previewLiabilities[0], maxJoinWithDebt1); // matches
        (previewShares, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1, maxJoinWithDebt1 + 1);
        assertGt(previewShares, maxJoinWithShares); // over
        assertGt(previewAssets[0], maxJoinWithAsset1); // over
        assertGt(previewLiabilities[0], maxJoinWithDebt1); // over
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18), mkArray(198.666666666666666667e18))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 340.936210834952780335e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, address(0));
        assertEq(maxExitWithAsset1, adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, address(0));
        assertEq(maxExitWithDebt1, adapterMaxExitLiabilities[0] - 1); // 1 under the underlying adapter max

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // equals the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 1); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // equals the underlying adapter max

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares - 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0] - 2); // 1 under the underlying adapter max
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0] - 1); // 1 under the underlying adapter max

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertGt(previewLiabilities[0], adapterMaxExitLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1 + 1);
        assertEq(previewAssets[0], adapterMaxExitAssets[0]); // matches
        assertGt(previewLiabilities[0], adapterMaxExitLiabilities[0]); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1 + 1);
        assertLt(previewAssets[0], adapterMaxExitAssets[0]); // under
        assertEq(previewLiabilities[0], adapterMaxExitLiabilities[0]); // matches
    }

    function test_fuzz_maxExitWithToken_noSupplyCap_withAdapterCap(uint256 maxExitAssetCap, uint256 maxExitLiabilityCap)
        public
    {
        maxExitAssetCap = bound(maxExitAssetCap, 0, SEED_ASSET1 + 1e18);
        maxExitLiabilityCap = bound(maxExitLiabilityCap, 0, SEED_DEBT1 + 1e18);

        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(maxExitAssetCap), mkArray(maxExitLiabilityCap))
        );
        (uint256[] memory adapterMaxExitAssets, uint256[] memory adapterMaxExitLiabilities) = adapters[0].maxExit();

        // Use the special case for address(0) so it doesn't take the amount of shares that the owner holds
        // into consideration.
        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, address(0));
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, address(0));

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);

        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertLe(previewAssets[0], adapterMaxExitAssets[0]);
        assertLe(previewLiabilities[0], adapterMaxExitLiabilities[0]);
    }

    function test_maxExitWithToken_withSupplyCap_withAdapterCap() public {
        // asset1 balance = 997_700e18
        // debt1 balance = 596_000e18
        // supply = 1_000_000
        // forced max assets = 332.566666666666666667e18
        // forced max liabilities = 198.666666666666666667e18

        // Undelrying cap is much higher than the 1mm in the vault to max withdraw
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566666666666666667e18 * 10_000), mkArray(198.666666666666666667e18 * 10_000))
        );

        // Use the origami multisig since it has the full balance of shares (1mm shares)
        uint256 maxExitWithShares = vault.maxExitWithShares(origamiMultisig);
        assertEq(maxExitWithShares, 1_000_000e18);
        uint256 maxExitWithAsset1 = vault.maxExitWithToken(ASSET1, origamiMultisig);
        assertEq(maxExitWithAsset1, 975_451.29e18);
        uint256 maxExitWithDebt1 = vault.maxExitWithToken(DEBT1, origamiMultisig);
        assertEq(maxExitWithDebt1, 582_709.2e18);

        uint256 previewShares;
        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        (previewShares, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1);
        assertEq(previewShares, maxExitWithShares);
        assertEq(previewAssets[0], maxExitWithAsset1); // equals the total supply based cap
        assertEq(previewLiabilities[0], maxExitWithDebt1); // equals the total supply based cap

        // Verify that any more would breach the underyling adapter maximum's (either the asset or liability)
        (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertEq(previewLiabilities[0], maxExitWithDebt1); // matches
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1, maxExitWithAsset1 + 1);
        assertGt(previewAssets[0], maxExitWithAsset1); // over
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
        (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1, maxExitWithDebt1 + 1);
        assertEq(previewAssets[0], maxExitWithAsset1); // matches
        assertGt(previewLiabilities[0], maxExitWithDebt1); // over
    }
}

contract OpalVaultMaxJoinExitComplexNonOverlappingTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1_6DP = 997_700e6;
    uint256 internal SEED_ASSET2 = 996_600e18;
    uint256 internal SEED_ASSET3 = 995_500e18;
    uint256 internal SEED_DEBT1_6DP = 596_000e6;
    uint256 internal SEED_DEBT2 = 593_000e18;
    uint256 internal SEED_DEBT3 = 591_000e18;

    function addAdapters() internal override {
        addAdapters(
            mkArray(
                AdapterConfig(ASSET1_6DP, DEBT2, "GROUPID_1"),
                AdapterConfig(ASSET2, DEBT1_6DP, "GROUPID_2"),
                AdapterConfig(ASSET3, DEBT3, "GROUPID_3")
            )
        );

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT2, address(adapters[0].mockMorpho()), 1_000_000e18);
        deal(DEBT1_6DP, address(adapters[1].mockMorpho()), 1_000_000e6);
        deal(DEBT3, address(adapters[2].mockMorpho()), 1_000_000e18);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1_6DP, SEED_ASSET2, SEED_ASSET3);
        liabilitiesSeed = mkArray(SEED_DEBT2, SEED_DEBT1_6DP, SEED_DEBT3);
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(332.566667e6), mkArray(218.666666666666666667e18))
        );
        vm.mockCall(
            address(adapters[1]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(342.566666666666666667e18), mkArray(228.666667e6))
        );
        vm.mockCall(
            address(adapters[2]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(mkArray(352.566666666666666667e18), mkArray(238.666666666666666667e18))
        );
        (uint256[] memory adapterMaxJoinAssets1, uint256[] memory adapterMaxJoinLiabilities1) = adapters[0].maxJoin();
        (uint256[] memory adapterMaxJoinAssets2, uint256[] memory adapterMaxJoinLiabilities2) = adapters[1].maxJoin();
        (uint256[] memory adapterMaxJoinAssets3, uint256[] memory adapterMaxJoinLiabilities3) = adapters[2].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 333.333331662824496341e18);

        // The ASSET1_6DP restriction is the limiting factor for this vault
        // All are under the max
        uint256[] memory maxJoinWithAssets = new uint256[](3);
        maxJoinWithAssets[0] = vault.maxJoinWithToken(ASSET1_6DP, address(0));
        maxJoinWithAssets[1] = vault.maxJoinWithToken(ASSET2, address(0));
        maxJoinWithAssets[2] = vault.maxJoinWithToken(ASSET3, address(0));
        uint256[] memory maxJoinWithDebts = new uint256[](3);
        maxJoinWithDebts[0] = vault.maxJoinWithToken(DEBT2, address(0));
        maxJoinWithDebts[1] = vault.maxJoinWithToken(DEBT1_6DP, address(0));
        maxJoinWithDebts[2] = vault.maxJoinWithToken(DEBT3, address(0));

        assertEq(maxJoinWithAssets[0], adapterMaxJoinAssets1[0] - 3);
        assertLe(maxJoinWithAssets[0], adapterMaxJoinAssets1[0]);
        assertEq(maxJoinWithDebts[0], 197.66666567605492633e18);
        assertLe(maxJoinWithDebts[0], adapterMaxJoinLiabilities1[0]);

        assertEq(maxJoinWithAssets[1], 332.199998335170893053e18);
        assertLe(maxJoinWithAssets[1], adapterMaxJoinAssets2[0]);
        assertEq(maxJoinWithDebts[1], 198.666665e6);
        assertLe(maxJoinWithDebts[1], adapterMaxJoinLiabilities2[0]);

        assertEq(maxJoinWithAssets[2], 331.833331670341786107e18);
        assertLe(maxJoinWithAssets[2], adapterMaxJoinAssets3[0]);
        assertEq(maxJoinWithDebts[2], 196.999999012729277337e18);
        assertLe(maxJoinWithDebts[2], adapterMaxJoinLiabilities3[0]);

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;

        // ASSET1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAssets[0]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 3, 332.199997336273428886e18, 331.833330672546857773e18);
            expectArr(previewLiabilities, 197.666665081687882128e18, 198.666665e6, 196.99999842036684374e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAssets[0] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666665e6, 196.999999012729277337e18);
        }

        // ASSET2
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET2, maxJoinWithAssets[1]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893053e18, 331.833331670341786107e18);
            expectArr(previewLiabilities, 197.666665676054926329e18, 198.666665e6, 196.999999012729277336e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET2, maxJoinWithAssets[1] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666665e6, 196.999999012729277337e18);
        }

        // ASSET3
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET3, maxJoinWithAssets[2]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893053e18, 331.833331670341786107e18);
            expectArr(previewLiabilities, 197.666665676054926329e18, 198.666665e6, 196.999999012729277336e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET3, maxJoinWithAssets[2] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666665e6, 196.999999012729277337e18);
        }

        // DEBT2
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT2, maxJoinWithDebts[0]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666665e6, 196.999999012729277337e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT2, maxJoinWithDebts[0] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 1, 332.199998335170893056e18, 331.83333167034178611e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666665e6, 196.999999012729277338e18);
        }

        // DEBT1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebts[1]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 3, 332.199997213087248323e18, 331.833330549496644296e18);
            expectArr(previewLiabilities, 197.666665008389261745e18, 198.666665e6, 196.999998347315436241e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebts[1] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 1, 332.19999888523489933e18, 331.833332219798657719e18);
            expectArr(previewLiabilities, 197.666666003355704698e18, 198.666666e6, 196.999999338926174497e18);
        }

        // DEBT3
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT3, maxJoinWithDebts[2]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666665e6, 196.999999012729277337e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT3, maxJoinWithDebts[2] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 1, 332.199998335170893055e18, 331.833331670341786109e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666665e6, 196.999999012729277338e18);
        }
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(332.566667e6), mkArray(218.666666666666666667e18))
        );
        vm.mockCall(
            address(adapters[1]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(342.566666666666666667e18), mkArray(228.666667e6))
        );
        vm.mockCall(
            address(adapters[2]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(mkArray(352.566666666666666667e18), mkArray(238.666666666666666667e18))
        );
        (uint256[] memory adapterMaxExitAssets1, uint256[] memory adapterMaxExitLiabilities1) = adapters[0].maxExit();
        (uint256[] memory adapterMaxExitAssets2, uint256[] memory adapterMaxExitLiabilities2) = adapters[1].maxExit();
        (uint256[] memory adapterMaxExitAssets3, uint256[] memory adapterMaxExitLiabilities3) = adapters[2].maxExit();

        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 333.333331662824496341e18);

        // The ASSET1_6DP restriction is the limiting factor for this vault
        // All are under the max
        uint256[] memory maxExitWithAssets = new uint256[](3);
        maxExitWithAssets[0] = vault.maxExitWithToken(ASSET1_6DP, address(0));
        maxExitWithAssets[1] = vault.maxExitWithToken(ASSET2, address(0));
        maxExitWithAssets[2] = vault.maxExitWithToken(ASSET3, address(0));
        uint256[] memory maxExitWithDebts = new uint256[](3);
        maxExitWithDebts[0] = vault.maxExitWithToken(DEBT2, address(0));
        maxExitWithDebts[1] = vault.maxExitWithToken(DEBT1_6DP, address(0));
        maxExitWithDebts[2] = vault.maxExitWithToken(DEBT3, address(0));

        assertEq(maxExitWithAssets[0], adapterMaxExitAssets1[0] - 3);
        assertLe(maxExitWithAssets[0], adapterMaxExitAssets1[0]);
        assertEq(maxExitWithDebts[0], 197.66666567605492633e18);
        assertLe(maxExitWithDebts[0], adapterMaxExitLiabilities1[0]);

        assertEq(maxExitWithAssets[1], 332.199998335170893053e18);
        assertLe(maxExitWithAssets[1], adapterMaxExitAssets2[0]);
        assertEq(maxExitWithDebts[1], 198.666665e6);
        assertLe(maxExitWithDebts[1], adapterMaxExitLiabilities2[0]);

        assertEq(maxExitWithAssets[2], 331.833331670341786107e18);
        assertLe(maxExitWithAssets[2], adapterMaxExitAssets3[0]);
        assertEq(maxExitWithDebts[2], 196.999999012729277337e18);
        assertLe(maxExitWithDebts[2], adapterMaxExitLiabilities3[0]);

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;

        // ASSET1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAssets[0]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 332.199997336273428886e18, 331.833330672546857773e18);
            expectArr(previewLiabilities, 197.66666508168788213e18, 198.666666e6, 196.999998420366843741e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAssets[0] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277339e18);
        }

        // ASSET2
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET2, maxExitWithAssets[1]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 332.199998335170893053e18, 331.833331670341786107e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277338e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET2, maxExitWithAssets[1] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277339e18);
        }

        // ASSET3
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET3, maxExitWithAssets[2]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 332.199998335170893053e18, 331.833331670341786107e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277338e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET3, maxExitWithAssets[2] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277339e18);
        }

        // DEBT2
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT2, maxExitWithDebts[0]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 332.199998335170893052e18, 331.833331670341786106e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666666e6, 196.999999012729277337e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT2, maxExitWithDebts[0] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 332.199998335170893054e18, 331.833331670341786108e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277339e18);
        }

        // DEBT1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebts[1]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 4, 332.199997213087248321e18, 331.833330549496644294e18);
            expectArr(previewLiabilities, 197.666665008389261745e18, 198.666665e6, 196.999998347315436242e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebts[1] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 332.199998885234899328e18, 331.833332219798657717e18);
            expectArr(previewLiabilities, 197.666666003355704698e18, 198.666666e6, 196.999999338926174497e18);
        }

        // DEBT3
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT3, maxExitWithDebts[2]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 332.199998335170893052e18, 331.833331670341786106e18);
            expectArr(previewLiabilities, 197.66666567605492633e18, 198.666666e6, 196.999999012729277337e18);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT3, maxExitWithDebts[2] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 332.199998335170893053e18, 331.833331670341786107e18);
            expectArr(previewLiabilities, 197.666665676054926331e18, 198.666666e6, 196.999999012729277338e18);
        }
    }
}

// Overlapping assets, separate adapter group id's
contract OpalVaultMaxJoinExitComplexWithOverlappingSeparateGroupIdTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1_6DP = 997_700e6;
    uint256 internal SEED_ASSET2 = 996_600e18;
    uint256 internal SEED_DEBT1_6DP = 596_000e6;
    uint256 internal SEED_DEBT2 = 593_000e18;

    function addAdapters() internal override {
        addAdapters(
            mkArray(
                AdapterConfig(ASSET1_6DP, DEBT2, "GROUPID_1"),
                AdapterConfig(ASSET2, DEBT1_6DP, "GROUPID_2"),
                AdapterConfig(ASSET2, DEBT2, "GROUPID_3")
            )
        );

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT2, address(adapters[0].mockMorpho()), 1_000_000e18);
        deal(DEBT1_6DP, address(adapters[1].mockMorpho()), 1_000_000e6);
        deal(DEBT2, address(adapters[2].mockMorpho()), 1_000_000e18);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1_6DP, SEED_ASSET2 * 2);
        liabilitiesSeed = mkArray(SEED_DEBT2 * 2, SEED_DEBT1_6DP);
    }

    function perAdapterSeed() internal view override returns (IOpalManager.AssetsAndLiabilities[] memory perAdapterBS) {
        perAdapterBS = new IOpalManager.AssetsAndLiabilities[](adapters.length);
        (perAdapterBS[0].assets, perAdapterBS[0].liabilities) = (mkArray(SEED_ASSET1_6DP), mkArray(SEED_DEBT2));
        (perAdapterBS[1].assets, perAdapterBS[1].liabilities) = (mkArray(SEED_ASSET2), mkArray(SEED_DEBT1_6DP));
        (perAdapterBS[2].assets, perAdapterBS[2].liabilities) = (mkArray(SEED_ASSET2), mkArray(SEED_DEBT2));
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(
                mkArray(332.566667e6), // ASSET1
                mkArray(218.666666666666666667e18) // DEBT2
            )
        );
        vm.mockCall(
            address(adapters[1]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(
                mkArray(342.566666666666666667e18), // ASSET2
                mkArray(228.666667e6) // DEBT1
            )
        );
        vm.mockCall(
            address(adapters[2]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(
                mkArray(352.566666666666666667e18), // ASSET2
                mkArray(238.666666666666666667e18) // DEBT2
            )
        );
        (uint256[] memory adapterMaxJoinAssets1, uint256[] memory adapterMaxJoinLiabilities1) = adapters[0].maxJoin();
        (uint256[] memory adapterMaxJoinAssets2, uint256[] memory adapterMaxJoinLiabilities2) = adapters[1].maxJoin();
        (uint256[] memory adapterMaxJoinAssets3, uint256[] memory adapterMaxJoinLiabilities3) = adapters[2].maxJoin();

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 333.333331662824496341e18);

        // The ASSET1_6DP restriction is the limiting factor for this vault
        // All are under the max
        uint256[] memory maxJoinWithAssets = new uint256[](2);
        maxJoinWithAssets[0] = vault.maxJoinWithToken(ASSET1_6DP, address(0));
        maxJoinWithAssets[1] = vault.maxJoinWithToken(ASSET2, address(0));
        uint256[] memory maxJoinWithDebts = new uint256[](2);
        maxJoinWithDebts[0] = vault.maxJoinWithToken(DEBT2, address(0));
        maxJoinWithDebts[1] = vault.maxJoinWithToken(DEBT1_6DP, address(0));

        assertEq(maxJoinWithAssets[0], adapterMaxJoinAssets1[0] - 3, "1.1"); // ASSET1
        assertLe(maxJoinWithAssets[0], adapterMaxJoinAssets1[0], "1.2");
        assertEq(maxJoinWithDebts[0], 2 * 197.66666567605492633e18, "1.3"); // DEBT2
        assertLe(maxJoinWithDebts[0], adapterMaxJoinLiabilities1[0] + adapterMaxJoinLiabilities3[0], "1.4");

        assertEq(maxJoinWithAssets[1], 2 * 332.199998335170893053e18, "1.5"); // ASSET 2
        assertLe(maxJoinWithAssets[1], adapterMaxJoinAssets2[0] + adapterMaxJoinAssets3[0], "1.6");
        assertEq(maxJoinWithDebts[1], 198.666665e6, "1.7"); // DEBT1
        assertLe(maxJoinWithDebts[1], adapterMaxJoinLiabilities2[0], "1.8");

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;

        // ASSET1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAssets[0]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 3, 2 * 332.199997336273428886e18);
            expectArr(previewLiabilities, 197.666665081687882128e18 * 2 + 1, 198.666665e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAssets[0] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 2 * 332.199998335170893053e18 + 1);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18, 198.666665e6);
        }

        // ASSET2
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET2, maxJoinWithAssets[1]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 2 * 332.199998335170893053e18);
            expectArr(previewLiabilities, 2 * 197.666665676054926329e18 + 1, 198.666666e6 - 1);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET2, maxJoinWithAssets[1] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 2 * 332.199998335170893053e18 + 1);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18, 198.666665e6);
        }

        // DEBT2
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT2, maxJoinWithDebts[0]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 2, 2 * 332.199998335170893053e18 + 1);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18, 198.666665e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT2, maxJoinWithDebts[0] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 1, 2 * 332.199998335170893054e18 + 1);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18 + 1, 198.666665e6);
        }

        // DEBT1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebts[1]);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 3, 2 * 332.199997213087248322e18 + 1);
            expectArr(previewLiabilities, 2 * 197.666665008389261745e18, 198.666665e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebts[1] + 1);
            expectArr(previewAssets, adapterMaxJoinAssets1[0] - 1, 2 * 332.19999888523489933e18);
            expectArr(previewLiabilities, 2 * 197.666666003355704698e18, 198.666666e6);
        }
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(
                mkArray(332.566667e6), // ASSET1
                mkArray(218.666666666666666667e18) // DEBT2
            )
        );
        vm.mockCall(
            address(adapters[1]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(
                mkArray(342.566666666666666667e18), // ASSET2
                mkArray(228.666667e6) // DEBT1
            )
        );
        vm.mockCall(
            address(adapters[2]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(
                mkArray(352.566666666666666667e18), // ASSET2
                mkArray(238.666666666666666667e18) // DEBT2
            )
        );
        (uint256[] memory adapterMaxExitAssets1, uint256[] memory adapterMaxExitLiabilities1) = adapters[0].maxExit();
        (uint256[] memory adapterMaxExitAssets2, uint256[] memory adapterMaxExitLiabilities2) = adapters[1].maxExit();
        (uint256[] memory adapterMaxExitAssets3, uint256[] memory adapterMaxExitLiabilities3) = adapters[2].maxExit();

        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 333.333331662824496341e18);

        // The ASSET1_6DP restriction is the limiting factor for this vault
        // All are under the max
        uint256[] memory maxExitWithAssets = new uint256[](2);
        maxExitWithAssets[0] = vault.maxExitWithToken(ASSET1_6DP, address(0));
        maxExitWithAssets[1] = vault.maxExitWithToken(ASSET2, address(0));
        uint256[] memory maxExitWithDebts = new uint256[](2);
        maxExitWithDebts[0] = vault.maxExitWithToken(DEBT2, address(0));
        maxExitWithDebts[1] = vault.maxExitWithToken(DEBT1_6DP, address(0));

        assertEq(maxExitWithAssets[0], adapterMaxExitAssets1[0] - 3, "1.1"); // ASSET1
        assertLe(maxExitWithAssets[0], adapterMaxExitAssets1[0], "1.2");
        assertEq(maxExitWithDebts[0], 2 * 197.66666567605492633e18, "1.3"); // DEBT2
        assertLe(maxExitWithDebts[0], adapterMaxExitLiabilities1[0] + adapterMaxExitLiabilities3[0], "1.4");

        assertEq(maxExitWithAssets[1], 2 * 332.199998335170893053e18, "2.1"); // ASSET2
        assertLe(maxExitWithAssets[1], adapterMaxExitAssets2[0] + adapterMaxExitAssets3[0], "2.2");
        assertEq(maxExitWithDebts[1], 198.666665e6, "2.3"); // DEBT1
        assertLe(maxExitWithDebts[1], adapterMaxExitLiabilities2[0], "2.4");

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;

        // ASSET1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAssets[0]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 2 * 332.199997336273428886e18 + 1);
            expectArr(previewLiabilities, 2 * 197.666665081687882129e18 + 1, 198.666666e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAssets[0] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 2 * 332.199998335170893054e18);
            expectArr(previewLiabilities, 2 * 197.666665676054926331e18, 198.666666e6);
        }

        // ASSET2
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET2, maxExitWithAssets[1]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 2 * 332.199998335170893053e18);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18 + 1, 198.666666e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET2, maxExitWithAssets[1] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 2 * 332.199998335170893053e18 + 1);
            expectArr(previewLiabilities, 2 * 197.666665676054926331e18, 198.666666e6);
        }

        // DEBT2
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT2, maxExitWithDebts[0]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 2 * 332.199998335170893052e18);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18, 198.666666e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT2, maxExitWithDebts[0] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 3, 2 * 332.199998335170893053e18);
            expectArr(previewLiabilities, 2 * 197.66666567605492633e18 + 1, 198.666666e6);
        }

        // DEBT1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebts[1]);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 4, 2 * 332.199997213087248321e18);
            expectArr(previewLiabilities, 2 * 197.666665008389261744e18 + 1, 198.666665e6);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebts[1] + 1);
            expectArr(previewAssets, adapterMaxExitAssets1[0] - 2, 2 * 332.199998885234899328e18 + 1);
            expectArr(previewLiabilities, 2 * 197.666666003355704698e18, 198.666666e6);
        }
    }
}

// Overlapping assets, overlapping adapter group id's
contract OpalVaultMaxJoinExitComplexWithOverlappingPartialGroupIdTest is OpalVaultMaxJoinExitBaseTest {
    uint256 internal SEED_ASSET1_6DP = 997_700e6;
    uint256 internal SEED_ASSET2 = 996_600e18;
    uint256 internal SEED_DEBT1_6DP = 596_000e6;
    uint256 internal SEED_DEBT2 = 593_000e18;

    function addAdapters() internal override {
        addAdapters(
            mkArray(
                AdapterConfig(ASSET1_6DP, DEBT2, "GROUPID_1"),
                AdapterConfig(ASSET2, DEBT1_6DP, "GROUPID_2"),
                AdapterConfig(ASSET2, DEBT2, "GROUPID_1")
            )
        );

        // Supply some debt that can be borrowed to the mock morpho
        deal(DEBT2, address(adapters[0].mockMorpho()), 1_000_000e18);
        deal(DEBT1_6DP, address(adapters[1].mockMorpho()), 1_000_000e6);
        deal(DEBT2, address(adapters[2].mockMorpho()), 1_000_000e18);
    }

    function seedAmounts()
        internal
        view
        override
        returns (uint256[] memory assetsSeed, uint256[] memory liabilitiesSeed)
    {
        assetsSeed = mkArray(SEED_ASSET1_6DP, SEED_ASSET2 * 2);
        liabilitiesSeed = mkArray(SEED_DEBT2 * 2, SEED_DEBT1_6DP);
    }

    function perAdapterSeed() internal view override returns (IOpalManager.AssetsAndLiabilities[] memory perAdapterBS) {
        perAdapterBS = new IOpalManager.AssetsAndLiabilities[](adapters.length);
        (perAdapterBS[0].assets, perAdapterBS[0].liabilities) = (mkArray(SEED_ASSET1_6DP), mkArray(SEED_DEBT2));
        (perAdapterBS[1].assets, perAdapterBS[1].liabilities) = (mkArray(SEED_ASSET2), mkArray(SEED_DEBT1_6DP));
        (perAdapterBS[2].assets, perAdapterBS[2].liabilities) = (mkArray(SEED_ASSET2), mkArray(SEED_DEBT2));
    }

    function test_maxJoinWithToken_noSupplyCap_withAdapterCap() public {
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(
                mkArray(332.566667e6), // ASSET1 (ISOLATED)
                mkArray(218.666666666666666667e18) // DEBT2 (**COMMON**)
            )
        );
        vm.mockCall(
            address(adapters[1]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(
                mkArray(342.566666666666666667e18), // ASSET2 (ISOLATED)
                mkArray(228.666667e6) // DEBT1 (ISOLATED)
            )
        );
        vm.mockCall(
            address(adapters[2]),
            abi.encodeWithSelector(IOpalAdapter.maxJoin.selector),
            abi.encode(
                mkArray(352.566666666666666667e18), // ASSET2 (ISOLATED)
                mkArray(238.666666666666666667e18) // DEBT2 (**COMMON**)
            )
        );

        // Check the manager aggregated maxJoin
        (uint256[] memory adapterMaxJoinAssets1, uint256[] memory adapterMaxJoinLiabilities1) = manager.maxJoin();

        /*
        For ASSET2 (ISOLATED LIMIT):
            adapter1:
                combinedBalanceForToken: 1993200
                groupIdBalanceForToken: 996600
                adapterMaxForToken: 342.566666666666666667
                == 685.133333333333333334

            adapter2:
                combinedBalanceForToken: 1993200
                groupIdBalanceForToken: 996600
                adapterMaxForToken: 352.566666666666666667
                == 705.133333333333333334
        */
        expectArr(adapterMaxJoinAssets1, 332.566665e6, 342.566666666666666665e18 * 2);

        /*
        FOR DEBT2 (COMMON LIMIT):
            adapter0:
                combinedBalanceForToken: 1,186,000
                groupIdBalanceForToken: 1,186,000
                adapterMaxForToken: 218.666666666666666667
                == 218.666666666666666667

            adapter2:
                combinedBalanceForToken: 1,186,000
                groupIdBalanceForToken: 1,186,000
                adapterMaxForToken: 238.666666666666666667
                == 238.666666666666666667
        */
        expectArr(adapterMaxJoinLiabilities1, 218.666666666666666665e18, 228.666665e6);

        (adapterMaxJoinAssets1, adapterMaxJoinLiabilities1) = adapters[0].maxJoin();
        assertEq(adapterMaxJoinAssets1[0], 332.566667e6);
        assertEq(adapterMaxJoinLiabilities1[0], 218.666666666666666667e18);
        (uint256[] memory adapterMaxJoinAssets2, uint256[] memory adapterMaxJoinLiabilities2) = adapters[1].maxJoin();
        assertEq(adapterMaxJoinAssets2[0], 342.566666666666666667e18);
        assertEq(adapterMaxJoinLiabilities2[0], 228.666667e6);
        (uint256[] memory adapterMaxJoinAssets3, uint256[] memory adapterMaxJoinLiabilities3) = adapters[2].maxJoin();
        assertEq(adapterMaxJoinAssets3[0], 352.566666666666666667e18);
        assertEq(adapterMaxJoinLiabilities3[0], 238.666666666666666667e18);

        uint256 maxJoinWithShares = vault.maxJoinWithShares(address(0));
        assertEq(maxJoinWithShares, 184.373243395165823494e18);

        // DEBT2 restriction is the limiting factor for this vault.
        uint256[] memory maxJoinWithAssets = new uint256[](2);
        maxJoinWithAssets[0] = vault.maxJoinWithToken(ASSET1_6DP, address(0));
        maxJoinWithAssets[1] = vault.maxJoinWithToken(ASSET2, address(0));
        uint256[] memory maxJoinWithDebts = new uint256[](2);
        maxJoinWithDebts[0] = vault.maxJoinWithToken(DEBT2, address(0));
        maxJoinWithDebts[1] = vault.maxJoinWithToken(DEBT1_6DP, address(0));

        assertEq(maxJoinWithAssets[0], 183.949184e6, "1.1"); // ASSET1
        assertLe(maxJoinWithAssets[0], adapterMaxJoinAssets1[0], "1.2");
        assertEq(maxJoinWithDebts[0], adapterMaxJoinLiabilities1[0] - 4, "1.3"); // DEBT2
        assertLe(maxJoinWithDebts[0], adapterMaxJoinLiabilities1[0], "1.4");

        assertEq(maxJoinWithAssets[1], 367.492748735244519388e18, "2.1"); // ASSET 2
        assertLe(maxJoinWithAssets[1], adapterMaxJoinAssets2[0] + adapterMaxJoinAssets3[0], "2.2");
        assertEq(maxJoinWithDebts[1], 109.886453e6, "2.3"); // DEBT1
        assertLe(maxJoinWithDebts[1], adapterMaxJoinLiabilities2[0], "2.4");

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;

        {
            (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, maxJoinWithAssets[1] + 1);
            expectArr(previewLiabilities, adapterMaxJoinLiabilities1[0] - 4, maxJoinWithDebts[1]);

            // With an extra
            (previewAssets, previewLiabilities) = vault.previewJoinWithShares(maxJoinWithShares + 1);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, maxJoinWithAssets[1] + 3);
            expectArr(previewLiabilities, adapterMaxJoinLiabilities1[0] - 2, maxJoinWithDebts[1]);
        }

        // ASSET1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAssets[0]);
            expectArr(previewAssets, maxJoinWithAssets[0], 367.492746866593164278e18);
            expectArr(previewLiabilities, 218.666665554775984764e18, maxJoinWithDebts[1] - 1);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET1_6DP, maxJoinWithAssets[0] + 1);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, 367.492748864388092613e18);
            expectArr(previewLiabilities, 218.666666743510073167e18, maxJoinWithDebts[1]); // over
        }

        // ASSET2
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET2, maxJoinWithAssets[1]);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, maxJoinWithAssets[1]);
            expectArr(previewLiabilities, adapterMaxJoinLiabilities1[0] - 5, maxJoinWithDebts[1]);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(ASSET2, maxJoinWithAssets[1] + 1);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, maxJoinWithAssets[1] + 1);
            expectArr(previewLiabilities, adapterMaxJoinLiabilities1[0] - 4, maxJoinWithDebts[1]);
        }

        // DEBT2
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT2, maxJoinWithDebts[0]);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, maxJoinWithAssets[1] + 1);
            expectArr(previewLiabilities, adapterMaxJoinLiabilities1[0] - 4, maxJoinWithDebts[1]);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT2, maxJoinWithDebts[0] + 1);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, maxJoinWithAssets[1] + 3);
            expectArr(previewLiabilities, adapterMaxJoinLiabilities1[0] - 3, maxJoinWithDebts[1]);
        }

        // DEBT1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebts[1]);
            expectArr(previewAssets, maxJoinWithAssets[0] + 1, 367.492748522818791947e18);
            expectArr(previewLiabilities, 218.666666540268456376e18, maxJoinWithDebts[1]);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewJoinWithToken(DEBT1_6DP, maxJoinWithDebts[1] + 1);
            expectArr(previewAssets, maxJoinWithAssets[0] + 3, 367.492751867114093962e18);
            expectArr(previewLiabilities, 218.666668530201342282e18, maxJoinWithDebts[1] + 1); // over
        }
    }

    function test_maxExitWithToken_noSupplyCap_withAdapterCap() public {
        vm.mockCall(
            address(adapters[0]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(
                mkArray(332.566667e6), // ASSET1 (ISOLATED)
                mkArray(218.666666666666666667e18) // DEBT2 (**COMMON**)
            )
        );
        vm.mockCall(
            address(adapters[1]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(
                mkArray(342.566666666666666667e18), // ASSET2 (ISOLATED)
                mkArray(228.666667e6) // DEBT1 (ISOLATED)
            )
        );
        vm.mockCall(
            address(adapters[2]),
            abi.encodeWithSelector(IOpalAdapter.maxExit.selector),
            abi.encode(
                mkArray(352.566666666666666667e18), // ASSET2 (ISOLATED)
                mkArray(238.666666666666666667e18) // DEBT2 (**COMMON**)
            )
        );

        // Check the manager aggregated maxJoin
        (uint256[] memory adapterMaxExitAssets1, uint256[] memory adapterMaxExitLiabilities1) = manager.maxExit();

        /*
        For ASSET2 (ISOLATED LIMIT):
            adapter1:
                combinedBalanceForToken: 1993200
                groupIdBalanceForToken: 996600
                adapterMaxForToken: 342.566666666666666667
                == 685.133333333333333334

            adapter2:
                combinedBalanceForToken: 1993200
                groupIdBalanceForToken: 996600
                adapterMaxForToken: 352.566666666666666667
                == 705.133333333333333334
        */
        expectArr(adapterMaxExitAssets1, 332.566665e6, 342.566666666666666665e18 * 2);

        /*
        FOR DEBT2 (COMMON LIMIT):
            adapter0:
                combinedBalanceForToken: 1,186,000
                groupIdBalanceForToken: 1,186,000
                adapterMaxForToken: 218.666666666666666667
                == 218.666666666666666667

            adapter2:
                combinedBalanceForToken: 1,186,000
                groupIdBalanceForToken: 1,186,000
                adapterMaxForToken: 238.666666666666666667
                == 238.666666666666666667
        */
        expectArr(adapterMaxExitLiabilities1, 218.666666666666666665e18, 228.666665e6);

        (adapterMaxExitAssets1, adapterMaxExitLiabilities1) = adapters[0].maxExit();
        assertEq(adapterMaxExitAssets1[0], 332.566667e6);
        assertEq(adapterMaxExitLiabilities1[0], 218.666666666666666667e18);
        (uint256[] memory adapterMaxExitAssets2, uint256[] memory adapterMaxExitLiabilities2) = adapters[1].maxExit();
        assertEq(adapterMaxExitAssets2[0], 342.566666666666666667e18);
        assertEq(adapterMaxExitLiabilities2[0], 228.666667e6);
        (uint256[] memory adapterMaxExitAssets3, uint256[] memory adapterMaxExitLiabilities3) = adapters[2].maxExit();
        assertEq(adapterMaxExitAssets3[0], 352.566666666666666667e18);
        assertEq(adapterMaxExitLiabilities3[0], 238.666666666666666667e18);

        uint256 maxExitWithShares = vault.maxExitWithShares(address(0));
        assertEq(maxExitWithShares, 184.373243395165823494e18);

        // DEBT2 restriction is the limiting factor for this vault.
        uint256[] memory maxExitWithAssets = new uint256[](2);
        maxExitWithAssets[0] = vault.maxExitWithToken(ASSET1_6DP, address(0));
        maxExitWithAssets[1] = vault.maxExitWithToken(ASSET2, address(0));
        uint256[] memory maxExitWithDebts = new uint256[](2);
        maxExitWithDebts[0] = vault.maxExitWithToken(DEBT2, address(0));
        maxExitWithDebts[1] = vault.maxExitWithToken(DEBT1_6DP, address(0));

        assertEq(maxExitWithAssets[0], 183.949184e6, "1.1"); // ASSET1
        assertLe(maxExitWithAssets[0], adapterMaxExitAssets1[0], "1.2");
        assertEq(maxExitWithDebts[0], adapterMaxExitLiabilities1[0] - 4, "1.3"); // DEBT2
        assertLe(maxExitWithDebts[0], adapterMaxExitLiabilities1[0], "1.4");

        assertEq(maxExitWithAssets[1], 367.492748735244519388e18, "2.1"); // ASSET 2
        assertLe(maxExitWithAssets[1], adapterMaxExitAssets2[0] + adapterMaxExitAssets3[0], "2.3");
        assertEq(maxExitWithDebts[1], 109.886453e6, "2.3"); // DEBT1
        assertLe(maxExitWithDebts[1], adapterMaxExitLiabilities2[0], "2.4");

        uint256[] memory previewAssets;
        uint256[] memory previewLiabilities;

        {
            (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares);
            expectArr(previewAssets, maxExitWithAssets[0], maxExitWithAssets[1]);
            expectArr(previewLiabilities, adapterMaxExitLiabilities1[0] - 3, maxExitWithDebts[1] + 1);

            // With an extra
            (previewAssets, previewLiabilities) = vault.previewExitWithShares(maxExitWithShares + 1);
            expectArr(previewAssets, maxExitWithAssets[0], maxExitWithAssets[1] + 2);
            expectArr(previewLiabilities, adapterMaxExitLiabilities1[0] - 1, maxExitWithDebts[1] + 1);
        }

        // ASSET1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAssets[0]);
            expectArr(previewAssets, maxExitWithAssets[0], 367.492746866593164279e18);
            expectArr(previewLiabilities, 218.666665554775984766e18, maxExitWithDebts[1]);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET1_6DP, maxExitWithAssets[0] + 1);
            expectArr(previewAssets, maxExitWithAssets[0] + 1, 367.492748864388092614e18);
            expectArr(previewLiabilities, 218.66666674351007317e18, maxExitWithDebts[1] + 1); // over
        }

        // ASSET2
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET2, maxExitWithAssets[1]);
            expectArr(previewAssets, maxExitWithAssets[0], maxExitWithAssets[1]);
            expectArr(previewLiabilities, adapterMaxExitLiabilities1[0] - 3, maxExitWithDebts[1] + 1);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(ASSET2, maxExitWithAssets[1] + 1);
            expectArr(previewAssets, maxExitWithAssets[0], maxExitWithAssets[1] + 1);
            expectArr(previewLiabilities, adapterMaxExitLiabilities1[0] - 1, maxExitWithDebts[1] + 1); // over
        }

        // DEBT2
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT2, maxExitWithDebts[0]);
            expectArr(previewAssets, maxExitWithAssets[0], maxExitWithAssets[1] - 2);
            expectArr(previewLiabilities, adapterMaxExitLiabilities1[0] - 4, maxExitWithDebts[1] + 1);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT2, maxExitWithDebts[0] + 1);
            expectArr(previewAssets, maxExitWithAssets[0], maxExitWithAssets[1]);
            expectArr(previewLiabilities, adapterMaxExitLiabilities1[0] - 3, maxExitWithDebts[1] + 1);
        }

        // DEBT1_6DP
        {
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebts[1]);
            expectArr(previewAssets, maxExitWithAssets[0], 367.492748522818791944e18);
            expectArr(previewLiabilities, 218.666666540268456375e18, maxExitWithDebts[1]);

            // With an extra
            (, previewAssets, previewLiabilities) = vault.previewExitWithToken(DEBT1_6DP, maxExitWithDebts[1] + 1);
            expectArr(previewAssets, maxExitWithAssets[0] + 2, 367.492751867114093959e18);
            expectArr(previewLiabilities, 218.666668530201342282e18, maxExitWithDebts[1] + 1); // over
        }
    }
}
