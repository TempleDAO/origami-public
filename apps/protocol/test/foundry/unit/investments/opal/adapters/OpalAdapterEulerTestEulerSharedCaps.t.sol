pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEVC } from "contracts/interfaces/external/ethereum-vault-connector/IEthereumVaultConnector.sol";

import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { IOpalAdapterEuler } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterEuler.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterEuler } from "contracts/investments/opal/adapters/OpalAdapterEuler.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";

import { OpalManager } from "contracts/investments/opal/OpalManager.sol";
import { OpalVault } from "contracts/investments/opal/OpalVault.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";

import "forge-std/console.sol";

contract OpalAdapterEulerTestEulerSharedCaps is OrigamiTest, OrigamiBundlerTestUtils {
    error E_BorrowCapExceeded();

    OpalManager internal manager;
    OpalVault internal vault;
    TokenPrices internal tokenPrices;

    OpalAdapterFactory internal adapterFactory;
    OpalAdapterEuler internal adapterImpl;
    OpalAdapterEuler internal adapter1;
    OpalAdapterEuler internal adapter2;
    OpalAdapterEuler internal adapter3;

    uint16 internal PERFORMANCE_FEE = 330; // 3.3%

    IEVC internal constant EULER_EVC = IEVC(0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383);

    // These are from the `Sentora PYUSD` market: https://app.euler.finance/market/sentora-pyusd?network=ethereum
    IERC20 internal constant SUSDE_VAULT = IERC20(0x56B829e465170c3aCcAd33a3E0512b239b202242);
    IERC20 internal constant SUSDE = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 internal constant PT_SUSDE_NOV_VAULT = IERC20(0x9D4265a05a6A0C7F3EcB179F4BA5C3197CBb8F16);
    IERC20 internal constant PT_SUSDE_NOV = IERC20(0xe6A934089BBEe34F832060CE98848359883749B3);

    IERC20 internal constant USDC_VAULT = IERC20(0x9bD52F2805c6aF014132874124686e7b248c2Cbb);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint256 internal constant MAX_LOAN_UR_ON_JOIN = 0.93e18; // 93%

    uint32 internal constant OP_NONE_DISABLED = 0;

    bytes32 internal tokenHash;

    function setUp() public virtual {
        fork("mainnet", 23_609_410);

        // deploy
        {
            tokenPrices = new TokenPrices(30);
            vault = new OpalVault(
                origamiMultisig, "OPAL", "everLov", PERFORMANCE_FEE, feeCollector, address(tokenPrices)
            );
            adapterFactory = new OpalAdapterFactory(origamiMultisig);
            manager = new OpalManager(origamiMultisig, address(vault), address(adapterFactory));

            adapterImpl = new OpalAdapterEuler("EulerV2.1", address(EULER_EVC));
            vm.label(address(adapterImpl), "EULERV2.1 [IMPL]");
        }

        // Setup
        {
            vm.startPrank(origamiMultisig);
            vault.setManager(address(manager));
            adapterFactory.addImplementation(address(adapterImpl));

            adapter1 = OpalAdapterEuler(
                manager.addAdapter(
                    address(adapterImpl),
                    "[PT-sUSDe-Nov]/[USDC]",
                    adapterImpl.encodeImmutableArgs(address(PT_SUSDE_NOV_VAULT), address(USDC_VAULT)),
                    adapterImpl.encodeInitArgs(origamiMultisig, MAX_LOAN_UR_ON_JOIN)
                )
            );

            adapter2 = OpalAdapterEuler(
                manager.addAdapter(
                    address(adapterImpl),
                    "[sUSDe]/[USDC]",
                    adapterImpl.encodeImmutableArgs(address(SUSDE_VAULT), address(USDC_VAULT)),
                    adapterImpl.encodeInitArgs(origamiMultisig, MAX_LOAN_UR_ON_JOIN)
                )
            );
            vm.stopPrank();

            tokenHash = vault.currentTokensHash();
        }

        seedDeposit(origamiMultisig, type(uint256).max);

        // Deal alice some assets
        {
            vm.startPrank(alice);
            deal(address(PT_SUSDE_NOV), alice, 1_000_000e18);
            PT_SUSDE_NOV.approve(address(vault), 1_000_000e18);
            deal(address(SUSDE), alice, 1_000_000e18);
            SUSDE.approve(address(vault), 1_000_000e18);
            vm.stopPrank();
        }
    }

    function seedDeposit(address account, uint256 maxSupply) internal {
        uint256[] memory assetAmounts = mkArray(200e18, 200e18);
        uint256[] memory liabilityAmounts = mkArray(100e6, 100e6);

        vm.startPrank(account);
        deal(address(PT_SUSDE_NOV), account, assetAmounts[0]);
        PT_SUSDE_NOV.approve(address(vault), assetAmounts[0]);
        deal(address(SUSDE), account, assetAmounts[1]);
        SUSDE.approve(address(vault), assetAmounts[1]);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        (perAdapterBS[0].assets, perAdapterBS[0].liabilities) = (mkArray(assetAmounts[0]), mkArray(liabilityAmounts[0]));
        (perAdapterBS[1].assets, perAdapterBS[1].liabilities) = (mkArray(assetAmounts[1]), mkArray(liabilityAmounts[1]));

        vault.seed(
            assetAmounts,
            mkArray(liabilityAmounts[0] + liabilityAmounts[1]),
            400e18,
            account,
            maxSupply,
            abi.encode(perAdapterBS)
        );
        vm.stopPrank();
    }

    function updateVaultParameters(IEVault evault, uint32 hookedOps, uint16 supplyCap, uint16 borrowCap) internal {
        address governor = evault.governorAdmin();
        vm.startPrank(governor);
        evault.setHookConfig(address(0), hookedOps);

        // Update caps (0 = unlimited, per AmountCap rules)
        // Disabling operational flags superceeds caps
        evault.setCaps(supplyCap, borrowCap);
    }

    function test_sharedCap() public {
        assertEq(address(adapter1.borrowVault()), address(adapter2.borrowVault()));

        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter1.groupIds();
        expectArr(assetGroupIds, 0x0000000000000000000000009d4265a05a6a0c7f3ecb179f4ba5c3197cbb8f16);
        expectArr(liabilityGroupIds, 0x0000000000000000000000009bd52f2805c6af014132874124686e7b248c2cbb);

        (assetGroupIds, liabilityGroupIds) = adapter2.groupIds();
        expectArr(assetGroupIds, 0x00000000000000000000000056b829e465170c3accad33a3e0512b239b202242);
        expectArr(liabilityGroupIds, 0x0000000000000000000000009bd52f2805c6af014132874124686e7b248c2cbb);

        // Check join metrics
        uint256[] memory maxAssets;
        uint256[] memory maxLiabilities;
        {
            (
                IOpalAdapterEuler.AssetSupplyMetrics memory supplyMetrics,
                IOpalAdapterEuler.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter1.joinMetrics();
            assertEq(supplyMetrics.supplyingDisabled, false);
            assertEq(supplyMetrics.eulerSupplyCap, 10_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 449_630.371001588041470963e18);
            assertEq(borrowMetrics.borrowingDisabled, false);
            assertEq(borrowMetrics.eulerBorrowCap, 108_000_000.0e6);
            assertEq(borrowMetrics.alreadyBorrowed, 91_667_265.018571e6);
            assertEq(borrowMetrics.availableSupply, 18_693_772.008043e6);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);

            (supplyMetrics, borrowMetrics) = adapter2.joinMetrics();
            assertEq(supplyMetrics.supplyingDisabled, false);
            assertEq(supplyMetrics.eulerSupplyCap, 80_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 200e18);
            assertEq(borrowMetrics.borrowingDisabled, false);
            assertEq(borrowMetrics.eulerBorrowCap, 108_000_000.0e6);
            assertEq(borrowMetrics.alreadyBorrowed, 91_667_265.018571e6);
            assertEq(borrowMetrics.availableSupply, 18_693_772.008043e6);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);

            (maxAssets, maxLiabilities) = manager.maxJoin();
            console.log("after max join");
            expectArr(maxAssets, 9_550_369.628998411958529036e18, 79_999_799.999999999999999999e18);
            expectArr(maxLiabilities, 10_968_499.416179e6);
        }

        // Set a more restrictive borrow cap
        // 91_700_000e6 cap == AmountCap(58701)
        uint16 cap = 58_701;
        updateVaultParameters(adapter1.borrowVault(), OP_NONE_DISABLED, 0, cap);

        // Check updated join metrics
        {
            (
                IOpalAdapterEuler.AssetSupplyMetrics memory supplyMetrics,
                IOpalAdapterEuler.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter1.joinMetrics();
            assertEq(supplyMetrics.supplyingDisabled, false);
            assertEq(supplyMetrics.eulerSupplyCap, 10_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 449_630.371001588041470963e18);
            assertEq(borrowMetrics.borrowingDisabled, false);
            assertEq(borrowMetrics.eulerBorrowCap, 91_700_000e6);
            assertEq(borrowMetrics.alreadyBorrowed, 91_667_265.018571e6);
            assertEq(borrowMetrics.availableSupply, 18_693_772.008043e6);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);

            (supplyMetrics, borrowMetrics) = adapter2.joinMetrics();
            assertEq(supplyMetrics.supplyingDisabled, false);
            assertEq(supplyMetrics.eulerSupplyCap, 80_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 200e18);
            assertEq(borrowMetrics.borrowingDisabled, false);
            assertEq(borrowMetrics.eulerBorrowCap, 91_700_000e6);
            assertEq(borrowMetrics.alreadyBorrowed, 91_667_265.018571e6);
            assertEq(borrowMetrics.availableSupply, 18_693_772.008043e6);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);

            (maxAssets, maxLiabilities) = manager.maxJoin();
            expectArr(maxAssets, 9_550_369.628998411958529036e18, 79_999_799.999999999999999999e18);
            expectArr(maxLiabilities, 32_734.981428e6);
        }

        vm.startPrank(alice);
        vault.joinWithToken(address(USDC), maxLiabilities[0], alice, tokenHash);

        {
            (
                IOpalAdapterEuler.AssetSupplyMetrics memory supplyMetrics,
                IOpalAdapterEuler.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter1.joinMetrics();
            assertEq(supplyMetrics.supplyingDisabled, false);
            assertEq(supplyMetrics.eulerSupplyCap, 10_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 482_365.352429588041470963e18);
            assertEq(borrowMetrics.borrowingDisabled, false);
            assertEq(borrowMetrics.eulerBorrowCap, 91_700_000e6);
            assertEq(borrowMetrics.alreadyBorrowed, 91_699_999.999999e6);
            assertEq(borrowMetrics.availableSupply, 18_661_037.026615e6);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);

            (supplyMetrics, borrowMetrics) = adapter2.joinMetrics();
            assertEq(supplyMetrics.supplyingDisabled, false);
            assertEq(supplyMetrics.eulerSupplyCap, 80_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 32_934.981428e18);
            assertEq(borrowMetrics.borrowingDisabled, false);
            assertEq(borrowMetrics.eulerBorrowCap, 91_700_000e6);
            assertEq(borrowMetrics.alreadyBorrowed, 91_699_999.999999e6);
            assertEq(borrowMetrics.availableSupply, 18_661_037.026615e6);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);

            (maxAssets, maxLiabilities) = manager.maxJoin();
            expectArr(maxAssets, 9_517_634.647570411958529036e18, 79_967_065.018571999999999999e18);
            expectArr(maxLiabilities, 0);
        }
    }
}
