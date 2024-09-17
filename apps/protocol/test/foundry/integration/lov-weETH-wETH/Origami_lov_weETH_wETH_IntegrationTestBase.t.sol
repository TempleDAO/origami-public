pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ExternalContracts, LovTokenContracts, Origami_lov_weETH_wETH_TestDeployer } from "test/foundry/deploys/lov-weETH-wETH/Origami_lov_weETH_wETH_TestDeployer.t.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { Origami_lov_weETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-weETH-wETH/Origami_lov_weETH_wETH_TestConstants.t.sol";

contract Origami_lov_weETH_wETH_IntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error BadSwapParam(uint256 expected, uint256 found);
    error UnknownSwapAmount_BorrowToReserve(uint256 amount);
    error UnknownSwapAmount_ReserveToBorrow(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    Origami_lov_weETH_wETH_TestDeployer internal deployer;
    ExternalContracts public externalContracts;
    LovTokenContracts public lovTokenContracts;

    function setUp() public virtual {
        fork("mainnet", 19688458);
        vm.warp(1713517326);

        deployer = new Origami_lov_weETH_wETH_TestDeployer(); 
        origamiMultisig = address(deployer);
        (externalContracts, lovTokenContracts) = deployer.deployForked(origamiMultisig, feeCollector, overlord);

        // Bootstrap the morpho pool with some wETH
        supplyIntoMorpho(200e18);
    }

    function supplyIntoMorpho(uint256 amount) internal {
        deal(address(externalContracts.wEthToken), origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        IMorpho morpho = lovTokenContracts.borrowLend.morpho();
        SafeERC20.forceApprove(externalContracts.wEthToken, address(morpho), amount);
        morpho.supply(lovTokenContracts.borrowLend.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }

    function investLovToken(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(externalContracts.weEthToken, account, amount);
        vm.startPrank(account);
        externalContracts.weEthToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.weEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.weEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovToken.exitToToken(quoteData, recipient);
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        reservesAmount = LovTokenHelpers.solveRebalanceDownAmount(
            lovTokenContracts.lovTokenManager, 
            targetAL
        );

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        params.borrowAmount = lovTokenContracts.weEthToEthOracle.convertAmount(
            address(externalContracts.weEthToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        (reservesAmount, params.swapData) = swapBorrowTokenToReserveTokenQuote(params.borrowAmount);
        params.supplyAmount = reservesAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(targetAL.addBps(alSlippageBps, OrigamiMath.Rounding.ROUND_UP));

        // When to sweep surplus balances and supply as collateral
        params.supplyCollateralSurplusThreshold = 0;
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual returns (uint256 reservesAmount) {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, alSlippageBps);

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }
    
    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params
    ) {
        // ideal reserves (USDe) amount to remove
        params.withdrawCollateralAmount = LovTokenHelpers.solveRebalanceUpAmount(lovTokenContracts.lovTokenManager, targetAL);

        (params.repayAmount, params.swapData) = swapReserveTokenToBorrowTokenQuote(params.withdrawCollateralAmount);

        // If there's a fee (currently disabled on Spark) then remove that from what we want to request
        uint256 feeBps = 0;
        params.repayAmount = params.repayAmount.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [USDe] to the flashloan asset [wETH].
        // We need to be sure it can be paid off. Any remaining wETH is repaid on the wETH debt in Spark
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = 0;

        params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(targetAL.addBps(alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual {
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, slippageBps, alSlippageBps);
        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovTokenManager.rebalanceUp(params);
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiDexAggregatorSwapper.RouteData({
            router: Constants.ONE_INCH_ROUTER,
            data: data
        }));
    }

    function swapBorrowTokenToReserveTokenQuote(uint256 borrowAmount) internal pure returns (uint256 reservesAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee&amount=207067608000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (borrowAmount == 62.1202824e18) {
            reservesAmount = 59.910958105153936831e18;
            swapData = hex"83800a8e000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000035e1793b726f340000000000000000000000000000000000000000000000000019fb73d7cc5814edf2880000000000000000000007a415b19932c0105c82fdb6b720bb01b0cc2cae3053a717a";
        } else if (borrowAmount == 124.2405648e18) {
            reservesAmount = 119.824072001947245495e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006bc2f276e4de680000000000000000000000000000000000000000000000000033f724f50b8728ddb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001f10000000000000000000000000000000000000001d30001a500017700012d00a0c9e75c4800000000000000002e040000000000000000000000000000000000000000000000000000ff0000b0510013947303f63b363876868d070f14dc865c36463bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc200443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042888a7d7ae242d602a0000000000000000000000000000000000000000000000002fce9c4d33d904b05ee63c1e5017a415b19932c0105c82fdb6b720bb01b0cc2cae3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66cd5fe23c85820f7b72d0926fc9b05b43e359b7ee0000000000000000000000000000000000000000000000067ee49ea170e51bb70000000000000000000571c2167b455980a06c4eca27cd5fe23c85820f7b72d0926fc9b05b43e359b7ee111111125421ca6dc452d289314280a0f8842a650020d6bdbf78cd5fe23c85820f7b72d0926fc9b05b43e359b7ee111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000053a717a";
        } else if (borrowAmount == 207.067608e18) {
            reservesAmount = 199.703373442361801408e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b39a3ec6281d5800000000000000000000000000000000000000000000000000569b8740937939d600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001f10000000000000000000000000000000000000001d30001a500017700012d00a0c9e75c4800000000000000002f030000000000000000000000000000000000000000000000000000ff0000b0510013947303f63b363876868d070f14dc865c36463bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc200443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000053294323ddf9b44602a0000000000000000000000000000000000000000000000005168f30e55999e91aee63c1e5017a415b19932c0105c82fdb6b720bb01b0cc2cae3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66cd5fe23c85820f7b72d0926fc9b05b43e359b7ee00000000000000000000000000000000000000000000000ad370e8126f273ac0000000000000000000056fbe2022343d80a06c4eca27cd5fe23c85820f7b72d0926fc9b05b43e359b7ee111111125421ca6dc452d289314280a0f8842a650020d6bdbf78cd5fe23c85820f7b72d0926fc9b05b43e359b7ee111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000053a717a";
        } else if (borrowAmount == 125.240564800000000001e18) {
            reservesAmount = 120.788499610941869980e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006ca0fde21f54a800100000000000000000000000000000000000000000000000346237a37334ca7ce0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001f10000000000000000000000000000000000000001d30001a500017700012d00a0c9e75c4800000000000000002e040000000000000000000000000000000000000000000000000000ff0000b0510013947303f63b363876868d070f14dc865c36463bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc200443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000043119bbed90deea002a00000000000000000000000000000000000000000000000030311de785a3eb92dee63c1e5017a415b19932c0105c82fdb6b720bb01b0cc2cae3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66cd5fe23c85820f7b72d0926fc9b05b43e359b7ee0000000000000000000000000000000000000000000000068c46f46e66994f9c000000000000000000056fbe2022343d80a06c4eca27cd5fe23c85820f7b72d0926fc9b05b43e359b7ee111111125421ca6dc452d289314280a0f8842a650020d6bdbf78cd5fe23c85820f7b72d0926fc9b05b43e359b7ee111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000053a717a";
        } else {
            revert UnknownSwapAmount_BorrowToReserve(borrowAmount);
        }

        swapData = encode(swapData);
    }

    function swapReserveTokenToBorrowTokenQuote(uint256 reservesAmount) internal pure returns (uint256 borrowAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=120788499610941869980&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */
        
        if (reservesAmount == 10.159834321810510220e18) {
            borrowAmount = 10.523890307924024086e18;
            swapData = hex"83800a8e000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee0000000000000000000000000000000000000000000000008cfefb7c9056518c00000000000000000000000000000000000000000000000049062f3d117e6d8b2800000000000000000000007a415b19932c0105c82fdb6b720bb01b0cc2cae3053a717a";
        } else if (reservesAmount == 120.788499610941869980e18) {
            borrowAmount = 125.125353647622305466e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000cd5fe23c85820f7b72d0926fc9b05b43e359b7ee000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000068c46f46e66994f9c000000000000000000000000000000000000000000000003643b471998d3db5d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000025d00000000000000000000000000000000000000023f0002110001e300019900a007e5c0d200000000000000000000000000017500015b0001550000a500008b00004f02a0000000000000000000000000000000000000000000000002ea17a90ed82720ffee63c1e500f47f04a8605be181e525d6391233cba1f7474182cd5fe23c85820f7b72d0926fc9b05b43e359b7ee41207f39c581f595b53c5cb19bd0b3f8da6c935e2ca00004de0e9a3e00000000000000000000000000000000000000000000000000000000000000000020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe845120dc24316b9ae028f1497c275eb9192a3ea0f67022ae7ab96520de3a18e5e111b5eaab095312d7fe8400443df02124000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003643b471998d3db5d00206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db000a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000006c8768e3331a7b6ba00000000000000000005a2197d2a8fad80a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a65000000053a717a";
        } else {
            revert UnknownSwapAmount_ReserveToBorrow(reservesAmount);
        }

        swapData = encode(swapData);
    }
}
