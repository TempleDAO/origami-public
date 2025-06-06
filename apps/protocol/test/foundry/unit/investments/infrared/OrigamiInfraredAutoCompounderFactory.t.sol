pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiDelegated4626VaultDeployer } from "contracts/factories/infrared/OrigamiDelegated4626VaultDeployer.sol";
import { OrigamiInfraredVaultManagerDeployer } from "contracts/factories/infrared/OrigamiInfraredVaultManagerDeployer.sol";
import { OrigamiSwapperWithLiquidityManagementDeployer } from "contracts/factories/swappers/OrigamiSwapperWithLiquidityManagementDeployer.sol";
import { OrigamiInfraredAutoCompounderFactory } from "contracts/factories/infrared/OrigamiInfraredAutoCompounderFactory.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiInfraredVaultManager } from "contracts/investments/infrared/OrigamiInfraredVaultManager.sol";
import { OrigamiSwapperWithLiquidityManagement } from "contracts/common/swappers/OrigamiSwapperWithLiquidityManagement.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";
import { IOrigamiSwapperWithLiquidityManagement } from "contracts/interfaces/common/swappers/IOrigamiSwapperWithLiquidityManagement.sol";
import { IKodiakIsland } from "contracts/interfaces/external/kodiak/IKodiakIsland.sol";
import { IKodiakIslandRouter } from "contracts/interfaces/external/kodiak/IKodiakIslandRouter.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";

contract OrigamiInfraredAutoCompounderFactoryTest is OrigamiTest {
    TokenPrices internal tokenPrices;

    OrigamiDelegated4626VaultDeployer internal vaultDeployer;
    OrigamiInfraredVaultManagerDeployer internal managerDeployer;
    OrigamiSwapperWithLiquidityManagementDeployer internal swapperDeployer;
    OrigamiInfraredAutoCompounderFactory internal factory;
    
    address internal constant OOGA_BOOGA_ROUTER = 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;
    IKodiakIslandRouter internal constant KODIAK_ISLAND_ROUTER = IKodiakIslandRouter(0x679a7C63FC83b6A4D9C1F931891d705483d4791F);
    IERC20 internal constant OHM_TOKEN = IERC20(0x18878Df23e2a36f81e820e4b47b4A40576D3159C);
    IERC20 internal constant HONEY_TOKEN = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
    IERC20 internal constant IBGT_TOKEN = IERC20(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    IInfraredVault internal constant INFRARED_VAULT = IInfraredVault(0xa57Cb177Beebc35A1A26A286951a306d9B752524);
    IInfraredVault internal constant INFRARED_VAULT2 = IInfraredVault(0xbbB228B0D7D83F86e23a5eF3B1007D0100581613);

    uint16 internal constant PERF_FEE_FOR_ORIGAMI = 100; // 1%

    event TokenPricesSet(address indexed tokenPrices);
    event FeeCollectorSet(address indexed feeCollector);
    event ManagerDeployerSet(address indexed deployer);
    event VaultDeployerSet(address indexed deployer);
    event SwapperDeployerSet(address indexed deployer);

    event VaultCreated(
        address vault,
        address asset,
        address manager,
        address swapper
    );

    function setUp() public virtual {
        fork("berachain_mainnet", 3_099_123);

        tokenPrices = new TokenPrices(30);

        vaultDeployer = new OrigamiDelegated4626VaultDeployer();
        managerDeployer = new OrigamiInfraredVaultManagerDeployer();
        swapperDeployer = new OrigamiSwapperWithLiquidityManagementDeployer();
        factory = new OrigamiInfraredAutoCompounderFactory(
            origamiMultisig,
            address(tokenPrices),
            feeCollector,
            address(vaultDeployer),
            address(managerDeployer),
            address(swapperDeployer)
        );
    }

    function create(IInfraredVault rewardVault) internal returns (OrigamiDelegated4626Vault newVault) {
        address[] memory swapRouters = new address[](2);
        swapRouters[0] = address(KODIAK_ISLAND_ROUTER);
        swapRouters[1] = address(OOGA_BOOGA_ROUTER);

        newVault = factory.create(
            "New Vault",
            "NEW_VAULT",
            rewardVault,
            PERF_FEE_FOR_ORIGAMI,
            overlord,
            swapRouters
        );
    }
}

contract OrigamiInfraredAutoCompounderFactoryTest_Admin is OrigamiInfraredAutoCompounderFactoryTest {
    function test_initialization() public view {
        assertEq(factory.owner(), address(origamiMultisig));
        assertEq(factory.tokenPrices(), address(tokenPrices));
        assertEq(factory.feeCollector(), address(feeCollector));
        assertEq(address(factory.vaultDeployer()), address(vaultDeployer));
        assertEq(address(factory.managerDeployer()), address(managerDeployer));
        assertEq(address(factory.swapperDeployer()), address(swapperDeployer));
    }

    function test_setFeeCollector() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(factory));
        emit FeeCollectorSet(alice);
        factory.setFeeCollector(alice);
        assertEq(address(factory.feeCollector()), alice);
    }

    function test_setTokenPrices_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(factory));
        emit TokenPricesSet(alice);
        factory.setTokenPrices(alice);
        assertEq(address(factory.tokenPrices()), alice);
    }

    function test_setVaultDeployer_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(factory));
        emit VaultDeployerSet(alice);
        factory.setVaultDeployer(alice);
        assertEq(address(factory.vaultDeployer()), alice);
    }

    function test_setManagerDeployer_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(factory));
        emit ManagerDeployerSet(alice);
        factory.setManagerDeployer(alice);
        assertEq(address(factory.managerDeployer()), alice);
    }

    function test_setSwapperDeployer_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(factory));
        emit SwapperDeployerSet(alice);
        factory.setSwapperDeployer(alice);
        assertEq(address(factory.swapperDeployer()), alice);
    }
}

contract OrigamiInfraredAutoCompounderFactoryTest_Access is OrigamiInfraredAutoCompounderFactoryTest {
    function test_setTokenPrices_access() public {
        expectElevatedAccess();
        factory.setTokenPrices(alice);
    }

    function test_setFeeCollector_access() public {
        expectElevatedAccess();
        factory.setFeeCollector(alice);
    }

    function test_setVaultDeployer_access() public {
        expectElevatedAccess();
        factory.setVaultDeployer(alice);
    }

    function test_setManagerDeployer_access() public {
        expectElevatedAccess();
        factory.setManagerDeployer(alice);
    }

    function test_setSwapperDeployer_access() public {
        expectElevatedAccess();
        factory.setSwapperDeployer(alice);
    }

    function test_create_access() public {
        expectElevatedAccess();
        factory.create(
            "XXX",
            "XXX",
            INFRARED_VAULT,
            0,
            address(0),
            new address[](0)
        );
    }

    function test_seedVault_access() public {
        expectElevatedAccess();
        factory.seedVault(IERC20(alice), 0, alice, 0);
    }
}

contract OrigamiInfraredAutoCompounderFactoryTest_Create is OrigamiInfraredAutoCompounderFactoryTest {
    function test_create_new() public {
        address[] memory swapRouters = new address[](2);
        swapRouters[0] = address(KODIAK_ISLAND_ROUTER);
        swapRouters[1] = address(OOGA_BOOGA_ROUTER);

        address expectedVault = 0xffD4505B3452Dc22f8473616d50503bA9E1710Ac;
        address expectedManager = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address expectedSwapper = 0x5B0091f49210e7B2A57B03dfE1AB9D08289d9294;
        address expectedAsset = INFRARED_VAULT.stakingToken();

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(factory));
        emit VaultCreated(
            expectedVault,
            expectedAsset,
            expectedManager,
            expectedSwapper
        );
        OrigamiDelegated4626Vault newVault = factory.create(
            "New Vault",
            "NEW_VAULT",
            INFRARED_VAULT,
            PERF_FEE_FOR_ORIGAMI,
            overlord,
            swapRouters
        );
        assertEq(address(newVault), expectedVault);
        assertEq(address(factory.registeredVaults(expectedAsset)), expectedVault);

        assertEq(newVault.manager(), expectedManager);
        assertEq(OrigamiInfraredVaultManager(expectedManager).swapper(), expectedSwapper);

        OrigamiInfraredVaultManager manager = OrigamiInfraredVaultManager(expectedManager);
        OrigamiSwapperWithLiquidityManagement swapper = OrigamiSwapperWithLiquidityManagement(expectedSwapper);

        // Check the vault initialization
        {
            assertEq(newVault.owner(), address(factory));
            assertEq(newVault.name(), "New Vault");
            assertEq(newVault.symbol(), "NEW_VAULT");
            assertEq(address(newVault.asset()), expectedAsset);
            assertEq(address(newVault.tokenPrices()), address(tokenPrices));
        }

        // Check the manager initialization
        {
            assertEq(newVault.owner(), address(factory));
            assertEq(address(manager.vault()), address(newVault));
            assertEq(address(manager.asset()), expectedAsset);
            assertEq(address(manager.rewardVault()), address(INFRARED_VAULT));
            assertEq(manager.feeCollector(), feeCollector);
            assertEq(manager.swapper(), expectedSwapper);
            (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
            assertEq(forCaller, 0);
            assertEq(forOrigami, PERF_FEE_FOR_ORIGAMI);
        }

        // Check overlord access
        {
            assertTrue(swapper.explicitFunctionAccess(overlord, OrigamiSwapperWithLiquidityManagement.execute.selector));
            assertTrue(swapper.explicitFunctionAccess(overlord, OrigamiSwapperWithLiquidityManagement.addLiquidity.selector));
        }
        
        // Check the routers are whitelisted
        {
            assertTrue(swapper.whitelistedRouters(OOGA_BOOGA_ROUTER));
            assertTrue(swapper.whitelistedRouters(address(KODIAK_ISLAND_ROUTER)));
        }

        // Check the ownership is transferred
        {
            newVault.acceptOwner();
            assertEq(newVault.owner(), origamiMultisig);
            manager.acceptOwner();
            assertEq(manager.owner(), origamiMultisig);
            swapper.acceptOwner();
            assertEq(swapper.owner(), origamiMultisig);
        }
    }

    function test_create_existing() public {
        vm.startPrank(origamiMultisig);

        address[] memory swapRouters = new address[](2);
        swapRouters[0] = address(KODIAK_ISLAND_ROUTER);
        swapRouters[1] = address(OOGA_BOOGA_ROUTER);

        // Create twice
        OrigamiDelegated4626Vault newVault = create(INFRARED_VAULT);
        OrigamiDelegated4626Vault newVault2 = factory.create(
            "XXX",
            "XXX",
            INFRARED_VAULT,
            0,
            address(0),
            new address[](0)
        );

        address expectedAsset = INFRARED_VAULT.stakingToken();
        assertEq(address(newVault), address(newVault2));
        assertEq(address(factory.registeredVaults(expectedAsset)), address(newVault));

        // Check the vault initialization
        {
            assertEq(newVault.owner(), address(factory));
            assertEq(newVault.name(), "New Vault");
            assertEq(newVault.symbol(), "NEW_VAULT");
            assertEq(address(newVault.asset()), expectedAsset);
            assertEq(address(newVault.tokenPrices()), address(tokenPrices));
        }

        // Another create for a different reward vault gives a different vault
        OrigamiDelegated4626Vault newVault3 = create(INFRARED_VAULT2);
        assertNotEq(address(newVault3), address(newVault));
        assertEq(address(newVault3), 0x8d2C17FAd02B7bb64139109c6533b7C2b9CADb81);
        assertEq(address(factory.registeredVaults(INFRARED_VAULT2.stakingToken())), 0x8d2C17FAd02B7bb64139109c6533b7C2b9CADb81);
    }
}

contract OrigamiInfraredAutoCompounderFactoryTest_Interact is OrigamiInfraredAutoCompounderFactoryTest {

    DummyDexRouter internal router;
    OrigamiDelegated4626Vault internal vault;
    IERC20 internal asset;
    OrigamiInfraredVaultManager internal manager;
    OrigamiSwapperWithLiquidityManagement internal swapper;

    function setUp() public override {
        super.setUp();

        router = new DummyDexRouter();
        deal(address(OHM_TOKEN), address(router), 1_000_000e9, true);
        deal(address(HONEY_TOKEN), address(router), 1_000_000e18, true);

        vm.startPrank(origamiMultisig);
        asset = IERC20(INFRARED_VAULT.stakingToken());
        vault = create(INFRARED_VAULT);
        manager = OrigamiInfraredVaultManager(vault.manager());
        swapper = OrigamiSwapperWithLiquidityManagement(manager.swapper());

        swapper.acceptOwner();
        swapper.whitelistRouter(address(router), true);
    }

    function encodeSwap(
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 minBuyTokenAmount,
        uint256 buyTokenToReceiveAmount
    ) internal view returns (bytes memory) {
        return abi.encode(
            IOrigamiSwapperWithLiquidityManagement.SwapParams({
                minBuyAmount: minBuyTokenAmount,
                router: address(router),
                swapData: abi.encodeCall(
                    DummyDexRouter.doExactSwap, (sellToken, sellAmount, buyToken, buyTokenToReceiveAmount)
                )
            })
        );
    }

    function seedDeposit(uint256 amount, uint256 maxSupply) internal {
        deal(address(asset), origamiMultisig, amount);
        asset.approve(address(factory), amount);
        vm.startPrank(origamiMultisig);
        uint256 shares = factory.seedVault(asset, amount, origamiMultisig, maxSupply);

        assertEq(vault.totalAssets(), amount);
        assertEq(vault.maxTotalSupply(), maxSupply);
        assertEq(vault.balanceOf(origamiMultisig), amount);
        assertEq(shares, amount);
    }

    function test_seedVault_fail_notRegistered() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(OrigamiInfraredAutoCompounderFactory.AssetNotRegistered.selector, OHM_TOKEN));
        factory.seedVault(OHM_TOKEN, 123, origamiMultisig, 123);
    }

    function test_seedVault_and_harvest() public {
        uint256 seedAmount = 1_000e18;
        seedDeposit(seedAmount, 1_000_000e18);

        assertEq(vault.convertToAssets(1e18), 1e18);
        skip(1 weeks);

        manager.harvestRewards(alice);
        uint256 ibgtRewards = IBGT_TOKEN.balanceOf(address(swapper));
        assertEq(ibgtRewards, 578.524461956512238000e18);

        IKodiakIsland lpToken = IKodiakIsland(vault.asset());
        (uint256 ohmToPair, uint256 honeyToPair, uint256 mintAmount) = lpToken.getMintAmounts(100e9, type(uint256).max);
        assertEq(ohmToPair, 100e9, "ohm to receive");
        assertEq(honeyToPair, 981.303565229489259204e18, "honey to receive");
        assertEq(mintAmount, 0.016750347226252938e18, "expected lp to receive");

        vm.startPrank(origamiMultisig);
        // swap ~half the iBGT for 100 ohm
        swapper.execute(
            IBGT_TOKEN, 250, OHM_TOKEN, 
            encodeSwap(
                address(IBGT_TOKEN), 
                250, address(OHM_TOKEN), 100e9, 100e9
            )
        );
        // swap ~half of the iBGT for 983 honey
        swapper.execute(
            IBGT_TOKEN, ibgtRewards - 250, HONEY_TOKEN,
            encodeSwap(
                address(IBGT_TOKEN),
                ibgtRewards - 250, address(HONEY_TOKEN), honeyToPair, honeyToPair
            )
        );

        IOrigamiSwapperWithLiquidityManagement.TokenAmount[] memory tokenAmounts;
        {
            tokenAmounts = new IOrigamiSwapperWithLiquidityManagement.TokenAmount[](2);
            tokenAmounts[0] = IOrigamiSwapperWithLiquidityManagement.TokenAmount(address(OHM_TOKEN), 100e18);
            tokenAmounts[1] = IOrigamiSwapperWithLiquidityManagement.TokenAmount(address(HONEY_TOKEN), honeyToPair);
        }

        bytes memory routerData = abi.encodeCall(
            KODIAK_ISLAND_ROUTER.addLiquidity,
            (address(lpToken), 100e9, honeyToPair, 0, 0, mintAmount, address(swapper))
        );
        bytes memory addLiquidityData = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(KODIAK_ISLAND_ROUTER),
                receiver: address(manager),
                minLpOutputAmount: mintAmount,
                callData: routerData
            })
        );

        swapper.addLiquidity(tokenAmounts, addLiquidityData);
        assertEq(vault.convertToAssets(1e18), 1e18, "No immediate change in share price");

        // Skip to the end of the drip duration
        skip(10 minutes);

        assertEq(vault.convertToAssets(1e18), 1.000016582843753990e18, "new share price");
    }
}
