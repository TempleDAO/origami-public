pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { IKodiakIsland } from "contracts/interfaces/external/kodiak/IKodiakIsland.sol";
import { IKodiakIslandRouter } from "contracts/interfaces/external/kodiak/IKodiakIslandRouter.sol";

import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiInfraredVaultManager } from "contracts/investments/infrared/OrigamiInfraredVaultManager.sol";
import { OrigamiSwapperWithLiquidityManagement } from "contracts/common/swappers/OrigamiSwapperWithLiquidityManagement.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";
import { IOrigamiSwapperWithLiquidityManagement } from "contracts/interfaces/common/swappers/IOrigamiSwapperWithLiquidityManagement.sol";

contract OrigamiOhmHoneyVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;
    using SafeERC20 for IERC20;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    OrigamiDelegated4626Vault internal vault;
    OrigamiInfraredVaultManager internal manager;
    TokenPrices internal tokenPrices;

    IKodiakIsland internal constant asset = IKodiakIsland(0x98bDEEde9A45C28d229285d9d6e9139e9F505391);
    IKodiakIslandRouter internal constant kodiakIslandRouter =
        IKodiakIslandRouter(0x679a7C63FC83b6A4D9C1F931891d705483d4791F);
    IERC20 internal constant ohmToken = IERC20(0x18878Df23e2a36f81e820e4b47b4A40576D3159C);
    IERC20 internal constant honeyToken = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
    IERC20 internal constant ibgtToken = IERC20(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    IInfraredVault internal rewardVault = IInfraredVault(0xa57Cb177Beebc35A1A26A286951a306d9B752524);

    uint16 internal constant PERF_FEE_FOR_ORIGAMI = 100; // 1%

    uint256 internal constant DEPOSIT_FEE = 0;
    uint256 internal constant SEED_AMOUNT = 0.1e18;
    address internal swapper = makeAddr("swapper");

    function setUp() public virtual {
        fork("berachain_mainnet", 3_099_123);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig,
            "Origami OHM-HONEY LP Auto-Compounding Vault",
            "ori-KODI OHM-HONEY",
            asset,
            address(tokenPrices)
        );

        manager = new OrigamiInfraredVaultManager(
            origamiMultisig,
            address(vault),
            address(asset),
            address(rewardVault),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager), 0);
        vm.stopPrank();

        seedDeposit(origamiMultisig, SEED_AMOUNT, type(uint256).max);
    }

    function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
        vm.startPrank(account);
        deal(address(asset), account, amount);
        asset.approve(address(vault), amount);
        vault.seedDeposit(amount, account, maxSupply);
        vm.stopPrank();
    }

    function deposit(address user, uint256 amount) internal returns (uint256 shares) {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit Deposit(user, user, amount, expectedShares);
        shares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(shares, expectedShares);
    }

    function mint(address user, uint256 shares) internal returns (uint256 assetsDeposited) {
        assetsDeposited = vault.previewMint(shares);
        deal(address(asset), user, assetsDeposited);
        vm.startPrank(user);
        asset.approve(address(vault), assetsDeposited);

        vm.expectEmit(address(vault));
        emit Deposit(user, user, assetsDeposited, shares);
        uint256 actualAssets = vault.mint(shares, user);
        vm.stopPrank();

        assertEq(actualAssets, assetsDeposited);
    }

    function withdraw(address user, uint256 assets) internal {
        vm.startPrank(user);
        uint256 expectedShares = vault.previewWithdraw(assets);

        vm.expectEmit(address(vault));
        emit Withdraw(user, user, user, assets, expectedShares);
        uint256 actualShares = vault.withdraw(assets, user, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function redeem(address user, uint256 shares) internal {
        vm.startPrank(user);
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.expectEmit(address(vault));
        emit Withdraw(user, user, user, expectedAssets, shares);
        uint256 actualAssets = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    /// @notice Simulates the manager receiving assets (either from donation or from rewards)
    function donateAndReinvest(uint256 amount) internal {
        doMint(asset, address(manager), amount);
        manager.reinvest();
        skip(10 minutes);
    }
}

// Basic vault tests are covered in test/foundry/unit/investments/infrared/OrigamiIBGTVault.t.sol

contract OrigamiOhmHoneyVaultTest_Compound is OrigamiOhmHoneyVaultTestBase {
    using OrigamiMath for uint256;

    OrigamiSwapperWithLiquidityManagement public compoundingSwapper;
    DummyDexRouter public router;

    function encodeSwap(
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 minBuyTokenAmount,
        uint256 buyTokenToReceiveAmount
    )
        internal
        view
        returns (bytes memory)
    {
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

    function setUp() public override {
        super.setUp();

        router = new DummyDexRouter();
        compoundingSwapper = new OrigamiSwapperWithLiquidityManagement(origamiMultisig, address(asset));

        vm.startPrank(origamiMultisig);
        manager.setSwapper(address(compoundingSwapper));
        compoundingSwapper.whitelistRouter(address(router), true);
        compoundingSwapper.whitelistRouter(address(kodiakIslandRouter), true);

        doMint(ohmToken, address(router), 1_000_000e9);
        doMint(honeyToken, address(router), 1_000_000e18);
    }

    function test_compoundingIncreasesSharePrice() public {
        // Initial deposit
        deposit(alice, 1000e18);

        uint256 initialSharePrice = vault.convertToAssets(1e18);
        assertEq(initialSharePrice, 1e18);

        // Skip time to accumulate rewards
        skip(1 weeks);

        // Harvest rewards which sends HONEY to the compounding swapper
        vm.startPrank(alice);
        manager.harvestRewards(alice);

        // share price has not changed until the rewards are swapped to the base asset
        uint256 newSharePrice = vault.convertToAssets(1e18);
        assertEq(newSharePrice, initialSharePrice);

        uint256 ibgtRewards = 578.542942057702274744e18;
        assertEq(ibgtToken.balanceOf(address(compoundingSwapper)), ibgtRewards);

        // Simulate swapping iBGT rewards for a ohm and honey as prescribed by the island
        // assume we'll get enough of each
        assertEq(address(asset.token0()), address(ohmToken));
        assertEq(address(asset.token1()), address(honeyToken));
        (uint256 ohmToPair, uint256 honeyToPair, uint256 mintAmount) = asset.getMintAmounts(100e9, type(uint256).max);
        uint256 honeyToPairWithOhm = 981.303565229489259204e18;
        uint256 expectedLpToReceive = 0.016750347226252938e18;
        assertEq(ohmToPair, 100e9, "ohm to receive");
        assertEq(honeyToPair, honeyToPairWithOhm, "honey to receive");
        assertEq(mintAmount, expectedLpToReceive, "expected lp to receive");

        vm.startPrank(origamiMultisig);
        // swap ~half the iBGT for 100 ohm
        compoundingSwapper.execute(
            ibgtToken, 250, ohmToken, encodeSwap(address(ibgtToken), 250, address(ohmToken), 100e9, 100e9)
        );
        // swap ~half of the iBGT for 983 honey
        compoundingSwapper.execute(
            ibgtToken,
            ibgtRewards - 250,
            honeyToken,
            encodeSwap(
                address(ibgtToken), ibgtRewards - 250, address(honeyToken), honeyToPairWithOhm, honeyToPairWithOhm
            )
        );

        // do not expect any change yet as the deposit tokens are in the swapper
        assertEq(vault.convertToAssets(1e18), initialSharePrice);
        {
            (uint256 vested, uint256 unvested, uint256 future) = manager.vestingStatus();
            assertEq(vested, 0);
            assertEq(unvested, 0);
            assertEq(future, 0);
        }

        IOrigamiSwapperWithLiquidityManagement.TokenAmount[] memory tokenAmounts =
            new IOrigamiSwapperWithLiquidityManagement.TokenAmount[](2);
        tokenAmounts[0] =
            IOrigamiSwapperWithLiquidityManagement.TokenAmount({ token: address(ohmToken), amount: 100e18 });
        tokenAmounts[1] =
            IOrigamiSwapperWithLiquidityManagement.TokenAmount({ token: address(honeyToken), amount: honeyToPairWithOhm });

        compoundingSwapper.addLiquidity(
            tokenAmounts,
            abi.encode(
                IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                    liquidityRouter: address(kodiakIslandRouter),
                    receiver: address(manager),
                    minLpOutputAmount: expectedLpToReceive,
                    callData: abi.encodeCall(
                        kodiakIslandRouter.addLiquidity,
                        (address(asset), 100e9, honeyToPairWithOhm, 0, 0, expectedLpToReceive, address(compoundingSwapper))
                    )
                })
            )
        );

        // 1% perf fee taken on the expected output amount
        uint256 expectedPendingReserves = expectedLpToReceive.subtractBps(100, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedTotalAssets = 1000e18 + SEED_AMOUNT + expectedPendingReserves;
        {
            (uint256 vested, uint256 unvested, uint256 future) = manager.vestingStatus();
            assertEq(vested, 0);
            assertEq(unvested, expectedPendingReserves);
            assertEq(future, 0);
        }

        assertEq(rewardVault.balanceOf(address(manager)), expectedTotalAssets, "LP was staked");
        assertEq(manager.stakedAssets(), expectedTotalAssets, "Staked assets matches total assets");
        assertEq(manager.unallocatedAssets(), 0, "No unallocated assets");
        assertEq(manager.totalAssets(), 1000e18 + SEED_AMOUNT, "Total assets doesn't change immediately");
        assertEq(asset.balanceOf(address(manager)), 0, "Manager doesn't hold the asset");
        assertEq(asset.balanceOf(address(feeCollector)), 167_503_472_262_530, "1% fees were collected");
        (,uint256 expectedFees) = expectedLpToReceive.splitSubtractBps(100, OrigamiMath.Rounding.ROUND_DOWN);
        assertEq(
            asset.balanceOf(address(feeCollector)),
            expectedFees,
            "1% fees were collected"
        );
        assertEq(vault.convertToAssets(1e18), 1e18, "No immediate change in share price");

        // Skip to the end of the drip duration
        skip(10 minutes);

        {
            (uint256 vested, uint256 unvested, uint256 future) = manager.vestingStatus();
            assertEq(vested, expectedPendingReserves);
            assertEq(unvested, 0);
            assertEq(future, 0);
        }

        // Verify share price increased
        newSharePrice = vault.convertToAssets(1e18);
        assertGt(newSharePrice, initialSharePrice);
        assertEq(newSharePrice, 1.000016581185635426e18, "new share price");
        assertEq(manager.totalAssets(), expectedTotalAssets); // total assets now includes the dripped in reserves

        // reinvesting rewards again causes no impact on the share price or total assets
        manager.reinvest();
        assertEq(vault.convertToAssets(1e18), newSharePrice);
    }
}
