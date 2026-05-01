pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiHOhmCommon } from "test/foundry/unit/investments/olympus/OrigamiHOhmCommon.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IUniswapV3QuoterV2 } from "contracts/interfaces/external/uniswap/IUniswapV3QuoterV2.sol";
import { IUniswapV3SwapRouter } from "contracts/interfaces/external/uniswap/IUniswapV3SwapRouter.sol";
import { IUniswapV3Factory } from "contracts/interfaces/external/uniswap/IUniswapV3Factory.sol";
import { IUniswapV3NonfungiblePositionManager } from "contracts/interfaces/external/uniswap/IUniswapV3NonfungiblePositionManager.sol";
import { OrigamiHOhmArbBot } from "contracts/investments/olympus/OrigamiHOhmArbBot.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";

import { OrigamiHOhmCommon } from "test/foundry/unit/investments/olympus/OrigamiHOhmCommon.t.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiHOhmArbBot } from "contracts/interfaces/external/olympus/IOrigamiHOhmArbBot.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import { MockGohm } from "contracts/test/external/olympus/test/mocks/MockGohm.sol";
import { ICoolerLtvOracle } from "contracts/interfaces/external/olympus/ICoolerLtvOracle.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiHOhmArbBotTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    OrigamiHOhmArbBot internal arbBot;

    OrigamiHOhmVault internal constant vault = OrigamiHOhmVault(0x1DB1591540d7A6062Be0837ca3C808aDd28844F6);
    MockERC20 internal constant USDS = MockERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    MockERC20 internal constant DAI = MockERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC4626 internal constant sUSDS = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
    IERC20 internal constant OHM = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    MockGohm internal constant gOHM = MockGohm(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
    IOlympusStaking internal constant olympusStaking = IOlympusStaking(0xB63cac384247597756545b500253ff8E607a8020);
    ICoolerLtvOracle internal constant COOLER_LTV_ORACLE = ICoolerLtvOracle(0x9ee9f0c2e91E4f6B195B988a9e6e19efcf91e8dc);
    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    IUniswapV3SwapRouter internal constant uniV3Router = IUniswapV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3QuoterV2 internal constant uniV3Quoter = IUniswapV3QuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IUniswapV3Factory internal constant uniV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IUniswapV3NonfungiblePositionManager internal constant uniV3PositionManager = IUniswapV3NonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint24 internal constant SUSDS_HOHM_FEE = 10_000; // 1%
    uint24 internal constant SUSDS_OHM_FEE = 3_000; // 0.3%

    function setUp() public {
        fork("mainnet", 22670625);

        arbBot = new OrigamiHOhmArbBot(
            origamiMultisig,
            address(vault),
            address(olympusStaking),
            address(sUSDS),
            address(uniV3Router),
            address(uniV3Quoter),
            MORPHO
        );
    }

    function joinWithShares(address account, uint256 shares) internal {
        (
            uint256[] memory previewAssets,
            // uint256[] memory previewLiabilities
        ) = vault.previewJoinWithShares(shares);

        deal(address(gOHM), account, previewAssets[0]);
        gOHM.approve(address(vault), previewAssets[0]);
        
        vault.joinWithShares(shares, account);
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
        deal(asset, origamiMultisig, assetAmount, true);
        IERC20(asset).approve(address(svault), assetAmount);
        svault.mint(sharesAmount, to);
    }
}

contract OrigamiHOhmArbBotTestUniV3Quote is OrigamiHOhmArbBotTestBase {
    function test_sUsdsToOhmQuote() public {
        uint256 sUsdsAmountIn = 10_000e18;
        uint256 ohmAmountOut = arbBot.uniV3Quote(sUSDS, sUsdsAmountIn, OHM, SUSDS_OHM_FEE);

        // 10k sUSDS = 526.1 OHM
        assertEq(ohmAmountOut, 526.128052922e9);

        // 1 OHM = 19 sUSDS
        assertEq(1e36 / (1e27 * ohmAmountOut / sUsdsAmountIn), 19.006779707833843289e18);
    }

    function test_ohmToSusdsQuote() public {
        uint256 ohmAmountIn = 460.533751861e9;
        uint256 sUsdsAmountOut = arbBot.uniV3Quote(OHM, ohmAmountIn, sUSDS, SUSDS_OHM_FEE);
        assertApproxEqAbs(sUsdsAmountOut, 8_684.029789423941717575e18, 1e6);
    }
    function test_sUsdsToHohmQuote() public {
        uint256 sUsdsAmountIn = 10_364.966608991626893752e18;
        uint256 hohmAmountOut = arbBot.uniV3Quote(sUSDS, sUsdsAmountIn, vault, SUSDS_HOHM_FEE);
        assertEq(hohmAmountOut, 1_288_497.836442159807852043e18);

        // 1 hOHM = 0.008 sUSDS
        assertEq(1e36 / (1e18 * hohmAmountOut / sUsdsAmountIn), 0.008044225078104666e18);
    }

    function test_hohmToSusdsQuote() public {
        uint256 hohmAmountIn = 1_000_000e18;
        uint256 sUsdsAmountOut = arbBot.uniV3Quote(vault, hohmAmountIn, sUSDS, SUSDS_HOHM_FEE);
        assertEq(sUsdsAmountOut, 7_794.325576848117635061e18);
    }
}

contract OrigamiHOhmArbBotTestAdmin is OrigamiHOhmArbBotTestBase {
    function test_notMorpho_callback() public {
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        arbBot.onMorphoFlashLoan(123, bytes(""));
    }
    
    function test_approveToken_access() public {
        expectElevatedAccess();
        arbBot.approveToken(sUSDS, alice, 123);
    }
    
    function test_recoverToken_access() public {
        expectElevatedAccess();
        arbBot.recoverToken(sUSDS, alice, 123);
    }
    
    function test_executeRoute1_access() public {
        expectElevatedAccess();
        arbBot.executeRoute1(0, 0, 0, 0, 0, 0);
    }
    
    function test_executeRoute2_access() public {
        expectElevatedAccess();
        arbBot.executeRoute2(0, 0, 0, 0, 0);
    }

    function test_recoverToken() public {
        check_recoverToken(address(arbBot));
    }
}

contract OrigamiHOhmArbBotTestRoute1 is OrigamiHOhmArbBotTestBase {
    function test_quoteRoute1_noProfit() public {
        {
            vm.startPrank(origamiMultisig);
            uint256 susdsSellAmount = 50_000e18;
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
            assertEq(received, 6_065_469.668157697804999336e18);
        }

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(10_000e18, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(quoteData.profit, -278.808576317535428679e18, 1e6);
        assertEq(quoteData.usdsToExitHohm, 12_733.896265085495858745e18);
        assertEq(quoteData.ohmSold, 1_157.385183094e9);
    }

    function test_quoteRoute1_inProfit() public {
        vm.startPrank(origamiMultisig);

        uint256 arbInputAmount = 10_000e18;
        uint256 expectedProfit = 336.691175154239640585e18;
        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(uint256(quoteData.profit), expectedProfit, 1e6);
        assertEq(quoteData.usdsToExitHohm, 13_544.509057575927118474e18);
        assertEq(quoteData.ohmSold, 1_231.061865841e9);
    }

    function test_executeRoute1_success_noStartingBalance() public {
        vm.startPrank(origamiMultisig);

        uint256 startingSUsdsBalance = sUSDS.balanceOf(address(arbBot));
        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 336.691175154239640585e18);
        assertEq(quoteData.usdsToExitHohm, 13_544.509057575927118474e18);
        assertEq(quoteData.ohmSold, 1_231.061865841e9);

        uint256 endGas;
        uint256 startGas = gasleft();

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);
        arbBot.approveToken(sUSDS, MORPHO, sUsdsFlashAmount);

        int256 profit = arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            sUsdsFlashAmount: sUsdsFlashAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        endGas = gasleft();
        assertLt(startGas - endGas, 1_000_000);

        assertApproxEqAbs(profit, quoteData.profit, 1e6);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingSUsdsBalance + uint256(quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(DAI.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute1_success_withStartingBalance() public {
        vm.startPrank(origamiMultisig);

        mintErc4626(sUSDS, 5_000e18, address(arbBot));
        uint256 startingSUsdsBalance = sUSDS.balanceOf(address(arbBot));
        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 336.691175154239640585e18);
        assertEq(quoteData.usdsToExitHohm, 13_544.509057575927118474e18);
        assertEq(quoteData.ohmSold, 1_231.061865841e9);

        uint256 endGas;
        uint256 startGas = gasleft();

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);
        arbBot.approveToken(sUSDS, MORPHO, sUsdsFlashAmount);

        int256 profit = arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            sUsdsFlashAmount: sUsdsFlashAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        endGas = gasleft();
        assertLt(startGas - endGas, 1_000_000);

        assertApproxEqAbs(profit, quoteData.profit, 1e6);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingSUsdsBalance + uint256(quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(DAI.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute1_fail_slippage() public {
        vm.startPrank(origamiMultisig);

        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 336.691175154239640585e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);
        arbBot.approveToken(sUSDS, MORPHO, sUsdsFlashAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmArbBot.MinProfitNotMet.selector, quoteData.profit+1, quoteData.profit));
        arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            sUsdsFlashAmount: sUsdsFlashAmount,
            minProfit: quoteData.profit + 1,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }

    function test_executeRoute1_loss_failNoStartingBalance() public {
        vm.startPrank(origamiMultisig);

        {
            uint256 susdsSellAmount = 50_000e18;
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
            assertEq(received, 6_065_469.668157697804999336e18);
        }

        uint256 startingSUsdsBalance = sUSDS.balanceOf(address(arbBot));
        assertEq(startingSUsdsBalance, 0);
        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -278.808576317535428679e18);
        assertEq(quoteData.usdsToExitHohm, 12_733.896265085495858745e18);
        assertEq(quoteData.ohmSold, 1_157.385183094e9);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);
        arbBot.approveToken(sUSDS, MORPHO, sUsdsFlashAmount);

        // Didn't have enough sUSDS to cover the flashloan repayment
        vm.expectRevert("transferFrom reverted");
        arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            sUsdsFlashAmount: sUsdsFlashAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }

    function test_executeRoute1_loss_withStartingBalance() public {
        vm.startPrank(origamiMultisig);

        {
            uint256 susdsSellAmount = 50_000e18;
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
            assertEq(received, 6_065_469.668157697804999336e18);
        }

        mintErc4626(sUSDS, 5_000e18, address(arbBot));
        uint256 startingSUsdsBalance = sUSDS.balanceOf(address(arbBot));
        assertEq(startingSUsdsBalance, 5_000e18);
        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -278.808576317535428679e18);
        assertEq(quoteData.usdsToExitHohm, 12_733.896265085495858745e18);
        assertEq(quoteData.ohmSold, 1_157.385183094e9);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), sUsdsFlashAmount * 2); // Covers any remaining flash balance back to sUSDS
        arbBot.approveToken(sUSDS, MORPHO, sUsdsFlashAmount);

        int256 profit = arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            sUsdsFlashAmount: sUsdsFlashAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        assertEq(profit, quoteData.profit);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), uint256(int256(startingSUsdsBalance) + quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute1_loss_fail_slippage() public {
        vm.startPrank(origamiMultisig);

        mintErc4626(sUSDS, 5_000e18, address(arbBot));
        uint256 startingSUsdsBalance = sUSDS.balanceOf(address(arbBot));
        assertEq(startingSUsdsBalance, 5_000e18);

        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;

        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 336.691175154239640585e18);
        assertEq(quoteData.usdsToExitHohm, 13_544.509057575927118474e18);
        assertEq(quoteData.ohmSold, 1_231.061865841e9);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(uniV3Router), quoteData.ohmSold);
        arbBot.approveToken(USDS, address(vault), quoteData.usdsToExitHohm);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsToExitHohm);
        arbBot.approveToken(sUSDS, MORPHO, sUsdsFlashAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmArbBot.MinProfitNotMet.selector, quoteData.profit+1, quoteData.profit));
        arbBot.executeRoute1({
            sUsdsSold: arbInputAmount,
            sUsdsFlashAmount: sUsdsFlashAmount,
            minProfit: quoteData.profit+1,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });
    }
        
    function test_multicall() public {
        vm.startPrank(origamiMultisig);

        uint256 startingSUsdsBalance = sUSDS.balanceOf(address(arbBot));
        uint256 arbInputAmount = 10_000e18;
        uint256 sUsdsFlashAmount = 30_000e18;
        IOrigamiHOhmArbBot.Route1Quote memory quoteData = arbBot.quoteRoute1(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 336.691175154239640585e18);

        bytes[] memory operations = new bytes[](6);
        (operations[0], operations[1], operations[2], operations[3], operations[4], operations[5]) = (
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (sUSDS, address(uniV3Router), arbInputAmount)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (OHM, address(uniV3Router), quoteData.ohmSold)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (USDS, address(vault), quoteData.usdsToExitHohm)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (USDS, address(sUSDS), quoteData.usdsToExitHohm * 2)),
            abi.encodeCall(IOrigamiHOhmArbBot.approveToken, (sUSDS, MORPHO, sUsdsFlashAmount)),
            abi.encodeCall(IOrigamiHOhmArbBot.executeRoute1, (
                arbInputAmount,
                sUsdsFlashAmount,
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

        assertLt(startGas - endGas, 1_000_000);

        int256 profit = abi.decode(results[5], (int256));
        assertApproxEqAbs(profit, quoteData.profit, 1e6);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingSUsdsBalance + uint256(quoteData.profit), 1e6);
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
        assertApproxEqAbs(quoteData.profit, -401.497276128400361474e18, 1e6);
        assertEq(quoteData.ohmBought, 526.128052922e9);
        assertEq(quoteData.gOhmReceived, 1.954133741203852849e18);
        assertEq(quoteData.hOhmMinted, 526_091.859308886723559698e18);
        assertEq(quoteData.usdsReceived, 5_788.617433432809679706e18);
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
            assertEq(received, 11_784_741.503357165003792619e18);
        }

        uint256 arbInputAmount = 10_000e18;
        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertApproxEqAbs(quoteData.profit, 82.629655977628177928e18, 1e6);
        assertEq(quoteData.ohmBought, 526.128052922e9);
        assertEq(quoteData.gOhmReceived, 1.954133741203852849e18);
        assertEq(quoteData.hOhmMinted, 526_091.859308886723559698e18);
        assertEq(quoteData.usdsReceived, 5_788.617433432809679706e18);
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
            assertEq(received, 11_784_741.503357165003792619e18);
        }

        uint256 startingSUsdsBalance = 30_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 82.629655977628177928e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);
        arbBot.approveToken(sUSDS, MORPHO, arbInputAmount);

        mintErc4626(sUSDS, startingSUsdsBalance, address(arbBot));

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

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), startingSUsdsBalance + uint256(quoteData.profit), 1e6);
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
            assertEq(received, 11_784_741.503357165003792619e18);
        }

        uint256 startingSUsdsBalance = 10_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, 82.629655977628177928e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);
        arbBot.approveToken(sUSDS, MORPHO, arbInputAmount);

        mintErc4626(sUSDS, startingSUsdsBalance, address(arbBot));

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

        uint256 startingSUsdsBalance = 10_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -401.497276128400361474e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);
        arbBot.approveToken(sUSDS, MORPHO, arbInputAmount);

        mintErc4626(sUSDS, startingSUsdsBalance, address(arbBot));

        int256 profit = arbBot.executeRoute2({
            sUsdsSold: arbInputAmount,
            minProfit: quoteData.profit,
            susdsHohmPoolFee: SUSDS_HOHM_FEE,
            ohmSusdsPoolFee: SUSDS_OHM_FEE,
            deadline: vm.getBlockTimestamp() + 1 days
        });

        assertEq(profit, quoteData.profit);

        assertApproxEqAbs(sUSDS.balanceOf(address(arbBot)), uint256(int256(startingSUsdsBalance) + quoteData.profit), 1e6);
        assertEq(USDS.balanceOf(address(arbBot)), 0);
        assertEq(OHM.balanceOf(address(arbBot)), 0);
        assertEq(gOHM.balanceOf(address(arbBot)), 0);
        assertEq(vault.balanceOf(address(arbBot)), 0);
    }

    function test_executeRoute2_loss_fail_slippage() public {
        vm.startPrank(origamiMultisig);

        uint256 startingSUsdsBalance = 10_000e18;
        uint256 arbInputAmount = 10_000e18;

        IOrigamiHOhmArbBot.Route2Quote memory quoteData = arbBot.quoteRoute2(arbInputAmount, SUSDS_HOHM_FEE, SUSDS_OHM_FEE);
        assertEq(quoteData.profit, -401.497276128400361474e18);

        arbBot.approveToken(sUSDS, address(uniV3Router), arbInputAmount);
        arbBot.approveToken(OHM, address(olympusStaking), quoteData.ohmBought);
        arbBot.approveToken(USDS, address(sUSDS), quoteData.usdsReceived);
        arbBot.approveToken(gOHM, address(vault), quoteData.gOhmReceived);
        arbBot.approveToken(vault, address(uniV3Router), quoteData.hOhmMinted);
        arbBot.approveToken(sUSDS, MORPHO, arbInputAmount);

        mintErc4626(sUSDS, startingSUsdsBalance, address(arbBot));

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