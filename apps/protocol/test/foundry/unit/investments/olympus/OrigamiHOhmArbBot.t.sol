pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiHOhmCommon } from "test/foundry/unit/investments/olympus/OrigamiHOhmCommon.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IUniswapV3QuoterV2 } from "contracts/interfaces/external/uniswap/IUniswapV3QuoterV2.sol";
import { IUniswapV3SwapRouter } from "contracts/interfaces/external/uniswap/IUniswapV3SwapRouter.sol";
import { IUniswapV3Factory } from "contracts/interfaces/external/uniswap/IUniswapV3Factory.sol";
import { IUniswapV3NonfungiblePositionManager } from "contracts/interfaces/external/uniswap/IUniswapV3NonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";
import { OrigamiHOhmArbBot } from "contracts/investments/olympus/OrigamiHOhmArbBot.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";

import { OrigamiHOhmCommon } from "test/foundry/unit/investments/olympus/OrigamiHOhmCommon.t.sol";
import { OrigamiHOhmManager } from "contracts/investments/olympus/OrigamiHOhmManager.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { sqrt } from "@prb/math/src/Common.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiHOhmArbBot } from "contracts/interfaces/external/olympus/IOrigamiHOhmArbBot.sol";

contract OrigamiHOhmArbBotTestBase is OrigamiHOhmCommon {
    using OrigamiMath for uint256;

    OrigamiHOhmArbBot internal arbBot;

    IERC4626 internal sUSDS;
    IERC20 internal OHM;
    IOlympusStaking internal olympusStaking;

    IUniswapV3SwapRouter internal uniV3Router = IUniswapV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3QuoterV2 internal uniV3Quoter = IUniswapV3QuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IUniswapV3Factory internal uniV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IUniswapV3NonfungiblePositionManager internal uniV3PositionManager = IUniswapV3NonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint24 internal constant SUSDS_HOHM_FEE = 10_000; // 1%
    uint24 internal constant SUSDS_OHM_FEE = 3_000; // 0.3%

    MonoCooler internal cooler;

    OrigamiHOhmManager internal hohmManager;
    TokenPrices internal tokenPrices;

    address internal immutable OTHERS = makeAddr("OTHERS");

    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = 887272;

    function setUp() public {
        fork("mainnet", 22070837);

        OlympusMonoCoolerDeployerLib.Contracts memory coolerContracts;
        OlympusMonoCoolerDeployerLib.deploy(coolerContracts, bytes32(0), origamiMultisig, OTHERS);

        sUSDS = IERC4626(address(coolerContracts.sUSDS));
        USDS = coolerContracts.USDS;
        OHM = IERC20(address(coolerContracts.OHM));
        gOHM = coolerContracts.gOHM;
        olympusStaking = IOlympusStaking(address(coolerContracts.staking));
        cooler = coolerContracts.monoCooler;

        vm.prank(origamiMultisig);
        coolerContracts.ltvOracle.setOriginationLtvAt(uint96(uint256(11.5e18) * OHM_PER_GOHM / 1e18), uint32(vm.getBlockTimestamp()) + 182.5 days);

        tokenPrices = new TokenPrices(30);
        tokenPrices.transferOwnership(origamiMultisig);

        deployVault();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);

        seedUniV3();

        arbBot = new OrigamiHOhmArbBot(
            origamiMultisig,
            address(vault),
            address(olympusStaking),
            address(sUSDS),
            address(uniV3Router),
            address(uniV3Quoter)
        );
    }

    function deployVault() internal {
        vault = new OrigamiHOhmVault(
            origamiMultisig, 
            "Origami hOHM", 
            "hOHM",
            address(gOHM),
            address(tokenPrices)
        );

        hohmManager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(hohmManager));
        hohmManager.setExitFees(EXIT_FEE_BPS);

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

    function joinWithShares(address account, uint256 shares) internal {
        (
            uint256[] memory previewAssets,
            // uint256[] memory previewLiabilities
        ) = vault.previewJoinWithShares(shares);

        gOHM.mint(account, previewAssets[0]);
        gOHM.approve(address(vault), previewAssets[0]);
        
        vault.joinWithShares(shares, account);
    }

    function calculateSqrtPriceX96(uint256 token0Amount, uint256 token1Amount) internal pure returns (uint160) {
        return uint160(
            sqrt(
                token1Amount.mulDiv(
                    1 << 192,
                    token0Amount,
                    OrigamiMath.Rounding.ROUND_DOWN)
            )
        );
    }

    function calcMaxTick(int24 tickSpacing) internal pure returns (int24) {
        return (MAX_TICK / tickSpacing) * tickSpacing;
    }

    function mintLiquidity(
        IERC20 token0,
        IERC20 token1,
        uint256 token0Amount,
        uint256 token1Amount,
        uint24 fee,
        int24 tickSpacing
    ) internal {
        token0.approve(address(uniV3PositionManager), token0Amount);
        token1.approve(address(uniV3PositionManager), token1Amount);

        int24 maxTick = calcMaxTick(tickSpacing);

        uniV3PositionManager.mint(IUniswapV3NonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: fee,
            tickLower: -maxTick,
            tickUpper: maxTick,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: origamiMultisig,
            deadline: vm.getBlockTimestamp() + 1 days
        }));
    }

    function swap(
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint24 fee,
        address account
    ) internal returns (uint256 amountOut) {
        tokenIn.approve(address(uniV3Router), amountIn);
        return uniV3Router.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: fee,
            recipient: account,
            deadline: vm.getBlockTimestamp() + 1 days,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
    }

    function mintErc4626(IERC4626 svault, uint256 sharesAmount, address to) internal {
        address asset = svault.asset();
        uint256 assetAmount = svault.previewMint(sharesAmount);
        deal(asset, origamiMultisig, assetAmount);
        IERC20(asset).approve(address(svault), assetAmount);
        svault.mint(sharesAmount, to);
    }

    function seedUniV3() internal {
        vm.startPrank(origamiMultisig);
        {
            IUniswapV3Pool pool = IUniswapV3Pool(uniV3Factory.createPool(address(sUSDS), address(OHM), SUSDS_OHM_FEE));
            int24 tickSpacing = pool.tickSpacing();
            address token0 = pool.token0();
            assertEq(tickSpacing, 60);

            mintErc4626(sUSDS, 100_000_000e18, origamiMultisig);
            deal(address(OHM), origamiMultisig, 100_000_000e9);

            // 1 OHM == 22.5 USDS == 21.62 sUSDS
            if (address(token0) == address(sUSDS)) {
                pool.initialize(calculateSqrtPriceX96(21.627230947e18, 1e9));
                mintLiquidity(sUSDS, OHM, 100_000_000e18, 100_000_000e9, SUSDS_OHM_FEE, tickSpacing);
            } else {
                pool.initialize(calculateSqrtPriceX96(1e9, 21.627230947e18));
                mintLiquidity(OHM, sUSDS, 100_000_000e9, 100_000_000e18, SUSDS_OHM_FEE, tickSpacing);
            }

            assertApproxEqAbs(sUSDS.balanceOf(address(pool)), 99_999_999.999999999999947877e18, 1e6);
            assertEq(OHM.balanceOf(address(pool)), 4_623_800.441446278e9);
        }

        {
            IUniswapV3Pool pool = IUniswapV3Pool(uniV3Factory.createPool(address(sUSDS), address(vault), SUSDS_HOHM_FEE));
            int24 tickSpacing = pool.tickSpacing();
            address token0 = pool.token0();
            assertEq(tickSpacing, 200);

            mintErc4626(sUSDS, 100_000_000e18, origamiMultisig);
            joinWithShares(origamiMultisig, 100_000_000e18);

            // 1mm hOHM == 11_000 USDS == 10,573 sUSDS
            if (address(token0) == address(sUSDS)) {
                pool.initialize(calculateSqrtPriceX96(10_573.3129074956e18, 1_000_000e18));
                mintLiquidity(sUSDS, vault, 100_000_000e18, 100_000_000e18, SUSDS_HOHM_FEE, tickSpacing);
            } else {
                pool.initialize(calculateSqrtPriceX96(1_000_000e18, 10_573.3129074956e18));
                mintLiquidity(vault, sUSDS, 100_000_000e18, 100_000_000e18, SUSDS_HOHM_FEE, tickSpacing);
            }
            
            assertEq(vault.balanceOf(address(pool)), 99_999_999.999999999999999995e18);
            assertEq(sUSDS.balanceOf(address(pool)), 1_057_331.290749559999446460e18);
        }
    }
}

contract OrigamiHOhmArbBotTestUniV3Quote is OrigamiHOhmArbBotTestBase {
    function test_sUsdsToOhmQuote() public {
        uint256 sUsdsAmountIn = 10_000e18;
        uint256 ohmAmountOut = arbBot.uniV3Quote(sUSDS, sUsdsAmountIn, OHM, SUSDS_OHM_FEE);

        // 10k sUSDS = 478.1 OHM
        assertEq(ohmAmountOut, 460.946947601e9);

        // 1 OHM = 21.69 sUSDS
        assertEq(1e36 / (1e27 * ohmAmountOut / sUsdsAmountIn), 21.694470593731089780e18);
    }

    function test_ohmToSusdsQuote() public {
        uint256 ohmAmountIn = 460.533751861e9;
        uint256 sUsdsAmountOut = arbBot.uniV3Quote(OHM, ohmAmountIn, sUSDS, SUSDS_OHM_FEE);

        // 10k sUSDS = 478.1 OHM
        assertApproxEqAbs(sUsdsAmountOut, 9_929.203612201505178436e18, 1e6);
    }
    function test_sUsdsToHohmQuote() public {
        uint256 sUsdsAmountIn = 10_364.966608991626893752e18;
        uint256 hohmAmountOut = arbBot.uniV3Quote(sUSDS, sUsdsAmountIn, vault, SUSDS_HOHM_FEE);

        // 11k USDS ~= 10_364 ~= 961,164 hOHM
        assertEq(hohmAmountOut, 961_164.105948704571241982e18);

        // 1 hOHM = 0.01078 sUSDS
        assertEq(1e36 / (1e18 * hohmAmountOut / sUsdsAmountIn), 0.010783763714065269e18);
    }

    function test_hohmToSusdsQuote() public {
        uint256 hohmAmountIn = 1_000_000e18;
        uint256 sUsdsAmountOut = arbBot.uniV3Quote(vault, hohmAmountIn, sUSDS, SUSDS_HOHM_FEE);

        // 1mm hOHM = 10,573 sUSDS minus fees 10_364.97 sUSDS
        assertEq(sUsdsAmountOut, 10_364.966608991626893752e18);
    }
}

contract OrigamiHOhmArbBotTestRoute1 is OrigamiHOhmArbBotTestBase {
    function test_quoteRoute1_noProfit() public {
        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(10_000e18, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(quoteData.profit, -304.016044576897613258e18, 1e6);
        assertEq(quoteData.usdsToExitHohm, 10_101.933942011758664260e18);
        assertEq(quoteData.ohmSold, 918.352542004e9);
    }

    function test_quoteRoute1_inProfit() public {
        vm.startPrank(origamiMultisig);

        {
            uint256 hOhmSellAmount = 10_000_000e18;
            joinWithShares(origamiMultisig, hOhmSellAmount);

            // Sell hOHM to receive sUSDS, in order to skew the pool such that
            // it's trading at a discount
            uint256 received = swap(
                vault,
                hOhmSellAmount,
                sUSDS,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 95_246.403807285204731622e18);
        }

        uint256 arbInputAmount = 10_000e18;
        uint256 expectedProfit = 1_699.096704925011986727e18;
        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(uint256(quoteData.profit), expectedProfit, 1e6);
        assertEq(quoteData.usdsToExitHohm, 12_189.931200755044532104e18);
        assertEq(quoteData.ohmSold, 1_108.169422739e9);
    }

    function test_executeRoute1_success() public {
        vm.startPrank(origamiMultisig);

        {
            uint256 hOhmSellAmount = 10_000_000e18;
            joinWithShares(origamiMultisig, hOhmSellAmount);

            // Sell hOHM to receive sUSDS, in order to skew the pool such that
            // it's trading at a discount
            uint256 received = swap(
                vault,
                hOhmSellAmount,
                sUSDS,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 95_246.403807285204731622e18);
        }

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 1_699.096704925011986586e18);
        assertEq(quoteData.usdsToExitHohm, 12_189.931200755044532104e18);
        assertEq(quoteData.ohmSold, 1_108.169422739e9);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        uint256 endGas;
        uint256 startGas = gasleft();

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);

        int256 profit = arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        endGas = gasleft();
        // ~626,082 optimized - includes the approvals
        assertLt(startGas - endGas, 720_000);

        assertApproxEqAbs(profit, quoteData.profit, 1e6);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingUsdsBalance + uint256(quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute1_fail_slippage() public {
        vm.startPrank(origamiMultisig);

        {
            uint256 hOhmSellAmount = 10_000_000e18;
            joinWithShares(origamiMultisig, hOhmSellAmount);

            // Sell hOHM to receive sUSDS, in order to skew the pool such that
            // it's trading at a discount
            uint256 received = swap(
                vault,
                hOhmSellAmount,
                sUSDS,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 95_246.403807285204731622e18);
        }

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 1_699.096704925011986586e18);
        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmArbBot.MinProfitNotMet.selector, quoteData.profit+1, quoteData.profit));
        arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit + 1,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }

    function test_executeRoute1_loss_success() public {
        vm.startPrank(origamiMultisig);

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -304.016044576897613356e18);
        assertEq(quoteData.usdsToExitHohm, 10_101.933942011758664260e18);
        assertEq(quoteData.ohmSold, 918.352542004e9);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);

        int256 profit = arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        assertEq(profit, quoteData.profit);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), uint256(int256(startingUsdsBalance) + quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute1_loss_fail_slippage() public {
        vm.startPrank(origamiMultisig);

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -304.016044576897613356e18);
        assertEq(quoteData.usdsToExitHohm, 10_101.933942011758664260e18);
        assertEq(quoteData.ohmSold, 918.352542004e9);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmArbBot.MinProfitNotMet.selector, quoteData.profit+1, quoteData.profit));
        arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit+1,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }
        
    function test_multicall() public {
        vm.startPrank(origamiMultisig);

        {
            uint256 hOhmSellAmount = 10_000_000e18;
            joinWithShares(origamiMultisig, hOhmSellAmount);

            // Sell hOHM to receive sUSDS, in order to skew the pool such that
            // it's trading at a discount
            uint256 received = swap(
                vault,
                hOhmSellAmount,
                sUSDS,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 95_246.403807285204731622e18);
        }

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;
        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 1_699.096704925011986586e18);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        bytes[] memory operations = new bytes[](5);
        (operations[0], operations[1], operations[2], operations[3], operations[4]) = (
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (sUSDS, address(uniV3Router), arbInputAmount)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (OHM, address(uniV3Router), quoteData.ohmSold)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (USDS, address(vault), quoteData.usdsToExitHohm)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (USDS, address(sUSDS), quoteData.usdsToExitHohm)),
            abi.encodeCall(IOrigamiHOhmArbBot.executeRoute1, (
                arbInputAmount,
                quoteData.profit,
                SUSDS_HOHM_FEE,
                SUSDS_OHM_FEE,
                vm.getBlockTimestamp() + 1 days
            ))
        );

        uint256 endGas;
        uint256 startGas = gasleft();
        bytes[] memory results = arbBot.multicall(operations);
        endGas = gasleft();

        // ~634,953 optimized - includes the approvals
        assertLt(startGas - endGas, 725_000);

        int256 profit = abi.decode(results[4], (int256));
        assertApproxEqAbs(profit, quoteData.profit, 1e6);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingUsdsBalance + uint256(quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }
}

contract OrigamiHOhmArbBotTestRoute2 is OrigamiHOhmArbBotTestBase {
    function test_quoteRoute2_noProfit() public {
        uint256 arbInputAmount = 10_000e18;
        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(quoteData.profit, -126.448292579863068463e18, 1e6);
        assertEq(quoteData.ohmBought, 460.946947601e9);
        assertEq(quoteData.gOhmReceived, 1.712039451630566316e18);
        assertEq(quoteData.hOhmMinted, 460_949.501957013674919117e18);
        assertEq(quoteData.usdsReceived, 5_070.444521527150424110e18);
    }

    function test_quoteRoute2_inProfit() public {
        vm.startPrank(origamiMultisig);
        {
            uint256 susdsSellAmount = 100_000e18;
            mintErc4626(sUSDS, susdsSellAmount, origamiMultisig);

            // Sell sUSDS to receive hOHM, in order to skew the pool such that
            // it's trading at a premium
            uint256 received = swap(
                sUSDS,
                susdsSellAmount,
                vault,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 8_561_560.237276461582693829e18);
        }

        uint256 arbInputAmount = 10_000e18;
        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(quoteData.profit, 812.666555959302459279e18, 1e6);
        assertEq(quoteData.ohmBought, 460.946947601e9);
        assertEq(quoteData.gOhmReceived, 1.712039451630566316e18);
        assertEq(quoteData.hOhmMinted, 460_949.501957013674919117e18);
        assertEq(quoteData.usdsReceived, 5070.444521527150424110e18);
    }

    function test_executeRoute2_success() public {
        vm.startPrank(origamiMultisig);
        {
            uint256 susdsSellAmount = 100_000e18;
            mintErc4626(sUSDS, susdsSellAmount, origamiMultisig);

            // Sell sUSDS to receive hOHM, in order to skew the pool such that
            // it's trading at a premium
            uint256 received = swap(
                sUSDS,
                susdsSellAmount,
                vault,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 8_561_560.237276461582693829e18);
        }

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 812.666555959302459279e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        uint256 startGas = gasleft();
        uint256 endGas;

        int256 profit = arbBot.executeRoute2({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        endGas = gasleft();
        assertLt(startGas - endGas, 725_000);

        assertApproxEqAbs(profit, quoteData.profit, 1e6);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingUsdsBalance + uint256(quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute2_fail_slippage() public {
        vm.startPrank(origamiMultisig);
        {
            uint256 susdsSellAmount = 100_000e18;
            mintErc4626(sUSDS, susdsSellAmount, origamiMultisig);

            // Sell sUSDS to receive hOHM, in order to skew the pool such that
            // it's trading at a premium
            uint256 received = swap(
                sUSDS,
                susdsSellAmount,
                vault,
                SUSDS_HOHM_FEE,
                origamiMultisig
            );
            assertEq(received, 8_561_560.237276461582693829e18);
        }

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 812.666555959302459279e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmArbBot.MinProfitNotMet.selector, quoteData.profit+1, quoteData.profit));
        arbBot.executeRoute2({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit + 1,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }

    function test_executeRoute2_loss_success() public {
        vm.startPrank(origamiMultisig);

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -126.448292579863068463e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        int256 profit = arbBot.executeRoute2({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        assertEq(profit, quoteData.profit);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), uint256(int256(startingUsdsBalance) + quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute2_loss_fail_slippage() public {
        vm.startPrank(origamiMultisig);

        uint256 startingUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -126.448292579863068463e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);

        mintErc4626(sUSDS, startingUsdsBalance, address(arbBot));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmArbBot.MinProfitNotMet.selector, quoteData.profit+1, quoteData.profit));
        arbBot.executeRoute2({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit + 1,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }
}