pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiAutoStakingToErc4626 } from "contracts/investments/staking/OrigamiAutoStakingToErc4626.sol";
import { OrigamiAutoStaking } from "contracts/investments/staking/OrigamiAutoStaking.sol";
import { IOrigamiAutoStakingFactory } from "contracts/interfaces/factories/infrared/autostaking/IOrigamiAutoStakingFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiAutoStakingToErc4626Common } from "test/foundry/unit/investments/staking/OrigamiAutoStakingToErc4626Common.t.sol";
import { OrigamiSwapperWithCallbackDeployer } from "contracts/factories/swappers/OrigamiSwapperWithCallbackDeployer.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";

contract OrigamiAutoStakingToErc4626FactoryTestBase is OrigamiAutoStakingToErc4626Common {
    function setUp() public {
        fork("berachain_mainnet", BERACHAIN_FORK_BLOCK_NUMBER);
        setUpContracts();
    }

    function checkOneVault(IERC20 asset, address expectedVault) internal view {
        address[] memory expectedVaults = new address[](1);
        expectedVaults[0] = expectedVault;
        checkMultipleVaults(asset, expectedVaults);
    }

    function checkMultipleVaults(IERC20 asset, address[] memory expectedVaults) internal view {
        address[] memory allVaults = vaultFactory.allVaultsForAsset(address(asset));
        assertEq(allVaults.length, expectedVaults.length);
        for (uint256 i; i < allVaults.length; ++i) {
            assertEq(allVaults[i], expectedVaults[i]);
        }

        (address vault, uint256 version) = vaultFactory.currentVaultForAsset(address(asset));
        assertEq(vault, expectedVaults[expectedVaults.length-1]);
        assertEq(version, expectedVaults.length);
    }
}

contract OrigamiAutoStakingToErc4626FactoryTest_Admin is OrigamiAutoStakingToErc4626FactoryTestBase {
    function test_initialization() public view {
        assertEq(vaultDeployer.underlyingPrimaryRewardToken(), address(IBGT));
        assertEq(vaultDeployer.primaryRewardToken4626(), address(ORI_BGT));
        assertEq(vaultFactory.owner(), origamiMultisig);
        assertEq(vaultFactory.feeCollector(), feeCollector);
        assertEq(vaultFactory.rewardsDuration(), 10 minutes);
        assertEq(address(vaultFactory.vaultDeployer()), address(vaultDeployer));
        assertEq(address(vaultFactory.swapperDeployer()), address(swapperDeployer));

        assertEq(vaultDeployer.underlyingPrimaryRewardToken(), address(IBGT));
        assertEq(vaultDeployer.primaryRewardToken4626(), address(ORI_BGT));
    }
    
    function test_setVaultDeployer() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vaultFactory));
        emit IOrigamiAutoStakingFactory.VaultDeployerSet(alice);
        vaultFactory.setVaultDeployer(alice);
        assertEq(address(vaultFactory.vaultDeployer()), alice);
    }
    
    function test_setSwapperDeployer() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vaultFactory));
        emit IOrigamiAutoStakingFactory.SwapperDeployerSet(alice);
        vaultFactory.setSwapperDeployer(alice);
        assertEq(address(vaultFactory.swapperDeployer()), alice);
    }

    function test_updateRewardsDuration_revertZeroDuration() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        vaultFactory.updateRewardsDuration(0);
    }

    function test_updateRewardsDuration_success() public {
        vm.startPrank(origamiMultisig);
        assertEq(vaultFactory.rewardsDuration(), 10 minutes);
        vm.expectEmit(address(vaultFactory));
        emit IOrigamiAutoStakingFactory.RewardsDurationUpdated(8 minutes);
        vaultFactory.updateRewardsDuration(8 minutes);
        assertEq(vaultFactory.rewardsDuration(), 8 minutes);
    }

    function test_updateFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vaultFactory));
        emit IOrigamiAutoStakingFactory.FeeCollectorSet(bob);
        vaultFactory.updateFeeCollector(bob);
        assertEq(vaultFactory.feeCollector(), bob);
    }

    function test_updateFeeCollector_revertZeroAddress() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vaultFactory.updateFeeCollector(address(0));
    }

    function test_recoverToken() public {
        check_recoverToken(address(vaultFactory));
    }

    function test_proposeNewOwner() public {
        OrigamiSwapperWithCallback testSwapper = new OrigamiSwapperWithCallback(address(vaultFactory));
        assertEq(testSwapper.owner(), address(vaultFactory));

        vm.prank(origamiMultisig);
        vaultFactory.proposeNewOwner(address(testSwapper), alice);

        vm.prank(alice);
        testSwapper.acceptOwner();

        assertEq(testSwapper.owner(), alice);
    }
}

contract OrigamiAutoStakingToErc4626FactoryTest_Access is OrigamiAutoStakingToErc4626FactoryTestBase {
    function test_registerVault_access() public {
        expectElevatedAccess();
        vaultFactory.registerVault(
            address(WBERA),
            address(IR_WBERA_HONEY),
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
    }

    function test_manualRegisterVault_access() public {
        expectElevatedAccess();
        vaultFactory.manualRegisterVault(address(WBERA), address(IR_WBERA_HONEY));
    }

    function test_migrateVault_access() public {
        expectElevatedAccess();
        vaultFactory.migrateVault(address(WBERA), address(IR_WBERA_HONEY));
    }

    function test_setVaultDeployer_access() public {
        expectElevatedAccess();
        vaultFactory.setVaultDeployer(alice);
    }

    function test_setSwapperDeployer_access() public {
        expectElevatedAccess();
        vaultFactory.setSwapperDeployer(alice);
    }

    function test_updateRewardsDuration_access() public {
        expectElevatedAccess();
        vaultFactory.updateRewardsDuration(11 minutes);
    }

    function test_updateFeeCollector_access() public {
        expectElevatedAccess();
        vaultFactory.updateFeeCollector(alice);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        vaultFactory.recoverToken(address(WBERA), alice, 1);
    }

    function test_proposeNewOwner_access() public {
        expectElevatedAccess();
        vaultFactory.proposeNewOwner(alice, alice);
    }
}

contract OrigamiAutoStakingToErc4626FactoryTest_Registration is OrigamiAutoStakingToErc4626FactoryTestBase {
    function test_registerVault_successWithoutSwapper() public {
        vm.startPrank(origamiMultisig);

        // Mock data for the test
        address[] memory _rewardTokens = new address[](2); // Assuming you have reward token addresses
        _rewardTokens[0] = address(IBGT);
        _rewardTokens[1] = address(WBERA);

        // Expect the NewVault event to be emitted with correct parameters
        address expectedNewAddress = 0x3C8Ca53ee5661D29d3d3C0732689a4b86947EAF0;
        vm.expectEmit();
        emit IOrigamiAutoStakingFactory.VaultCreated(
            expectedNewAddress,
            address(BYUSD_HONEY),
            address(0)
        );

        // Register the vault and capture the return value
        OrigamiAutoStakingToErc4626 newVault = OrigamiAutoStakingToErc4626(address(
            vaultFactory.registerVault(
                address(BYUSD_HONEY),
                address(IR_BYUSD_HONEY),
                DEFAULT_FEE_BPS,
                address(0),
                new address[](0)
            )
        ));

        // Validate that the returned vault address matches the expected new vault address
        assertEq(address(newVault), expectedNewAddress, "Vault not registered correctly");

        // Validate that the vault is correctly registered in the vaultRegistry with the asset address
        checkOneVault(BYUSD_HONEY, expectedNewAddress);

        assertEq(address(newVault.underlyingPrimaryRewardToken()), address(IBGT));
        assertEq(newVault.primaryRewardToken(), address(ORI_BGT));
        assertEq(newVault.rewardsVault(), address(IR_BYUSD_HONEY));
        assertEq(newVault.feeCollector(), feeCollector);
        assertEq(newVault.swapper(), address(0));
        assertEq(newVault.performanceFeeBps(address(ORI_BGT)), DEFAULT_FEE_BPS);

        vm.startPrank(origamiMultisig);
        newVault.acceptOwner();
        assertEq(newVault.owner(), origamiMultisig);
    }

    function test_registerVault_successWithSwapper() public {
        vm.startPrank(origamiMultisig);
        swapperDeployer = new OrigamiSwapperWithCallbackDeployer();
        vaultFactory.setSwapperDeployer(address(swapperDeployer));

        // Mock data for the test
        address[] memory _rewardTokens = new address[](2); // Assuming you have reward token addresses
        _rewardTokens[0] = address(IBGT);
        _rewardTokens[1] = address(WBERA);

        // Expect the NewVault event to be emitted with correct parameters
        address expectedNewAddress = 0x3C8Ca53ee5661D29d3d3C0732689a4b86947EAF0;
        vm.expectEmit(true, true, true, false, address(vaultFactory));
        emit IOrigamiAutoStakingFactory.VaultCreated(
            expectedNewAddress,
            address(BYUSD_HONEY),
            address(0x997e2AE3Ce38d42C64f362B05e17AdAeB2021ADB)
        );

        // Register the vault and capture the return value
        address[] memory routers = new address[](1);
        routers[0] = address(router);
        OrigamiAutoStakingToErc4626 newVault = OrigamiAutoStakingToErc4626(address(
            vaultFactory.registerVault(
                address(BYUSD_HONEY),
                address(IR_BYUSD_HONEY),
                DEFAULT_FEE_BPS,
                overlord,
                routers
            )
        ));

        // Validate that the returned vault address matches the expected new vault address
        assertEq(address(newVault), expectedNewAddress, "Vault not registered correctly");

        // Validate that the vault is correctly registered in the vaultRegistry with the asset address
        checkOneVault(BYUSD_HONEY, expectedNewAddress);

        assertEq(address(newVault.underlyingPrimaryRewardToken()), address(IBGT));
        assertEq(newVault.primaryRewardToken(), address(ORI_BGT));
        assertEq(newVault.rewardsVault(), address(IR_BYUSD_HONEY));
        assertEq(newVault.feeCollector(), feeCollector);
        assertNotEq(newVault.swapper(), address(0));
        assertEq(newVault.performanceFeeBps(address(ORI_BGT)), DEFAULT_FEE_BPS);

        vm.startPrank(origamiMultisig);
        newVault.acceptOwner();
        assertEq(newVault.owner(), origamiMultisig);
        OrigamiSwapperWithCallback(newVault.swapper()).acceptOwner();
        assertEq(OrigamiSwapperWithCallback(newVault.swapper()).owner(), origamiMultisig);
        assertTrue(OrigamiSwapperWithCallback(newVault.swapper()).whitelistedRouters(address(router)));
    }

    function test_registerVault_revertZeroAsset() public {
        // Define reward tokens assuming you have them set up for the test
        address[] memory _rewardTokens = new address[](1); // Modify as per your test setup
        _rewardTokens[0] = address(WBERA); // Example reward token address

        // Expect a revert due to passing a zero asset address to registerVault
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vaultFactory.registerVault(
            address(0),
            address(IR_OHM_HONEY),
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
    }

    function test_registerVault_revertInvalidRewardVault() public {
        DummyMintableToken mockAsset = new DummyMintableToken(origamiMultisig, "MockAsset", "MAS", 18); // Mock asset token
        // Setup for the asset and reward tokens
        address assetAddress = address(mockAsset); // Your mock asset address
        address rewardVault = address(0);

        // Expect a revert due to invalid reward vault
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vaultFactory.registerVault(
            assetAddress,
            rewardVault,
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
    }

    function test_registerVault_revertDuplicateAsset() public {
        // Because stakingAsset is already registered, expect a revert
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiAutoStakingFactory.AlreadyRegistered.selector));
        vaultFactory.registerVault(
            address(OHM_HONEY),
            address(IR_OHM_HONEY),
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
        vm.expectRevert(abi.encodeWithSelector(IOrigamiAutoStakingFactory.AlreadyRegistered.selector));
        vaultFactory.registerVault(
            address(WBERA_HONEY),
            address(IR_WBERA_HONEY),
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
    }

    function test_manualRegisterVault_revertZeroAsset() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vaultFactory.manualRegisterVault(
            address(0),
            address(IR_OHM_HONEY)
        );
    }

    function test_manualRegisterVault_revertInvalidRewardVault() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vaultFactory.manualRegisterVault(
            address(OTHER_REWARD_TOKEN),
            address(0)
        );
    }

    function test_manualRegisterVault_revertDuplicateAsset() public {
        // Already created in setup
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiAutoStakingFactory.AlreadyRegistered.selector));
        vaultFactory.manualRegisterVault(
            address(OHM_HONEY),
            address(IR_OHM_HONEY)
        );
    }

    function test_manualRegisterVault_wrongAsset() public {
        // Already created in setup
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice));
        vaultFactory.manualRegisterVault(
            address(alice),
            address(IR_OHM_HONEY)
        );
    }

    function test_manualRegisterVault_badStakingToken() public {
        address stakingAsset = address(new DummyMintableToken(origamiMultisig, "Random Token", "RND", 18));

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(stakingAsset)));
        vaultFactory.manualRegisterVault(
            stakingAsset,
            0xbbB228B0D7D83F86e23a5eF3B1007D0100581613
        );
    }

    function test_manualRegisterVault_success() public {
        vm.startPrank(origamiMultisig);

        OrigamiAutoStakingToErc4626 vault = new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: origamiMultisig,
                stakingToken: address(BYUSD_HONEY),
                primaryRewardToken: address(ORI_BGT),
                rewardsVault: address(IR_BYUSD_HONEY),
                primaryPerformanceFeeBps: 100,
                feeCollector: feeCollector,
                rewardsDuration: 1 days,
                swapper: address(0)
            }),
            address(IBGT)
        );

        vm.expectEmit();
        emit IOrigamiAutoStakingFactory.VaultCreated(
            address(vault),
            address(BYUSD_HONEY),
            address(0)
        );

        vaultFactory.manualRegisterVault(
            address(BYUSD_HONEY),
            address(vault)
        );
        checkOneVault(BYUSD_HONEY, address(vault));
    }

    function test_migrateVault_fail_notRegistered() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiAutoStakingFactory.NotRegistered.selector));
        vaultFactory.migrateVault(
            address(alice),
            address(0)
        );
    }

    function test_migrateVault_fail_badStakingToken() public {
        vm.startPrank(origamiMultisig);

        OrigamiAutoStakingToErc4626 newVault = new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: origamiMultisig,
                stakingToken: address(BYUSD_HONEY),
                primaryRewardToken: address(ORI_BGT),
                rewardsVault: address(IR_BYUSD_HONEY),
                primaryPerformanceFeeBps: DEFAULT_FEE_BPS,
                feeCollector: feeCollector,
                rewardsDuration: 1 days,
                swapper: address(0)
            }),
            address(IBGT)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(OHM_HONEY)));
        vaultFactory.migrateVault(
            address(OHM_HONEY),
            address(newVault)
        );        
    }

    function test_migrateVault_fail_sameVault() public {
        vm.startPrank(origamiMultisig);

        (address oldVault,) = vaultFactory.currentVaultForAsset(address(OHM_HONEY));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, oldVault));
        vaultFactory.migrateVault(
            address(OHM_HONEY),
            oldVault
        );        
    }

    function test_migrateVault_success() public {
        vm.startPrank(origamiMultisig);

        OrigamiAutoStakingToErc4626 newVault = new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: origamiMultisig,
                stakingToken: address(OHM_HONEY),
                primaryRewardToken: address(ORI_BGT),
                rewardsVault: address(IR_OHM_HONEY),
                primaryPerformanceFeeBps: DEFAULT_FEE_BPS,
                feeCollector: feeCollector,
                rewardsDuration: 1 days,
                swapper: address(0)
            }),
            address(IBGT)
        );

        (address oldVault,) = vaultFactory.currentVaultForAsset(address(OHM_HONEY));
        vm.expectEmit(address(vaultFactory));
        emit IOrigamiAutoStakingFactory.VaultMigrated(oldVault, address(newVault), address(OHM_HONEY));
        vaultFactory.migrateVault(
            address(OHM_HONEY),
            address(newVault)
        );

        address[] memory expectedVaults = new address[](2);
        expectedVaults[0] = oldVault;
        expectedVaults[1] = address(newVault);
        checkMultipleVaults(OHM_HONEY, expectedVaults);
    }
}