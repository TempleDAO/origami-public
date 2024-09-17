pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ExternalContracts, LovTokenContracts, Origami_lov_ezETH_wETH_TestDeployer } from "test/foundry/deploys/lov-ezETH-wETH/Origami_lov_ezETH_wETH_TestDeployer.t.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { Origami_lov_ezETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-ezETH-wETH/Origami_lov_ezETH_wETH_TestConstants.t.sol";

contract Origami_lov_ezETH_wETH_IntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error BadSwapParam(uint256 expected, uint256 found);
    error UnknownSwapAmount_BorrowToReserve(uint256 amount);
    error UnknownSwapAmount_ReserveToBorrow(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    Origami_lov_ezETH_wETH_TestDeployer internal deployer;
    ExternalContracts public externalContracts;
    LovTokenContracts public lovTokenContracts;

    function setUp() public virtual {
        fork("mainnet", 19688458);
        vm.warp(1713517326);

        deployer = new Origami_lov_ezETH_wETH_TestDeployer(); 
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
        doMint(externalContracts.ezEthToken, account, amount);
        vm.startPrank(account);
        externalContracts.ezEthToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.ezEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.ezEthToken),
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
        params.borrowAmount = lovTokenContracts.ezEthToEthOracle.convertAmount(
            address(externalContracts.ezEthToken),
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
        // @note Ensure sDAI is listed as a connector token

        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0xbf5495Efe5DB9ce00f80364C8B423567e58d2110&amount=121959464800000000001&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (borrowAmount == 60.4797324e18) {
            reservesAmount = 60.040669200512086450e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000347532c2eb4aee000000000000000000000000000000000000000000000000001a09da743aea138d90000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000c90000000000000000000000000000000000000000000000ab00007d00004f00a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bf5495efe5db9ce00f80364c8b423567e58d211080a06c4eca27bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650020d6bdbf78bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000053a717a";
        } else if (borrowAmount == 201.599108e18) {
            reservesAmount = 200.129699396229718038e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aedbfe89baf9c40000000000000000000000000000000000000000000000000056cadc2a256fd700b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000c90000000000000000000000000000000000000000000000ab00007d00004f00a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bf5495efe5db9ce00f80364c8b423567e58d211080a06c4eca27bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650020d6bdbf78bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000053a717a";
        } else if (borrowAmount == 120.9594648e18) {
            reservesAmount = 120.079814957751842817e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000068ea6585d695dc000000000000000000000000000000000000000000000000003413899bf39b7dc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000c90000000000000000000000000000000000000000000000ab00007d00004f00a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bf5495efe5db9ce00f80364c8b423567e58d211080a06c4eca27bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650020d6bdbf78bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650000000000000000000000000000000000000000000000053a717a";
        } else if (borrowAmount == 121.959464800000000001e18) {
            reservesAmount = 121.025316500287251207e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000069c870f1110c1c00100000000000000000000000000000000000000000000000347c82611966bf1830000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000002220001f40001c600017c00a0c9e75c48000000000000001e0d0700000000000000000000000000000000000000000000014e0000ff0000b0510085de3add465a219ee25e04d22c39ab027cf5c12ec02aaa39b223fe8d0a0e5c4f27ead9083c756cc200443df02124000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000759542872554d56302a0000000000000000000000000000000000000000000000000da595c4f4ded96fdee63c1e500be80225f09645f172b079394312220637c440a63c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bf5495efe5db9ce00f80364c8b423567e58d211000a0f2fa6b66bf5495efe5db9ce00f80364c8b423567e58d21100000000000000000000000000000000000000000000000068f904c232cd7e30700000000000000000005980ffe76621580a06c4eca27bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a650020d6bdbf78bf5495efe5db9ce00f80364c8b423567e58d2110111111125421ca6dc452d289314280a0f8842a65053a717a";
        } else {
            revert UnknownSwapAmount_BorrowToReserve(borrowAmount);
        }

        swapData = encode(swapData);
    }

    function swapReserveTokenToBorrowTokenQuote(uint256 reservesAmount) internal pure returns (uint256 borrowAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0xbf5495Efe5DB9ce00f80364C8B423567e58d2110&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=9864435998293045174&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */
        
        if (reservesAmount == 121.025316500287251207e18) {
            borrowAmount = 121.912996252808613350e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d2110000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000068f904c232cd7e3070000000000000000000000000000000000000000000000034df0fc15a817c6f30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001900000000000000000000000000000000000000001720001440001160000cc00a0c9e75c480000000000000000280a00000000000000000000000000000000000000000000000000009e00004f02a0000000000000000000000000000000000000000000000000a9317a2e235f58f6ee63c1e501be80225f09645f172b079394312220637c440a63bf5495efe5db9ce00f80364c8b423567e58d211000a0fbb7cd0600596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659bf5495efe5db9ce00f80364c8b423567e58d2110c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000069be1f82b502f8de600000000000000000005a35d818645e680a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a650020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2111111125421ca6dc452d289314280a0f8842a6500000000000000000000000000000000053a717a";
        } else if (reservesAmount == 9.864435998293045174e18) {
            borrowAmount = 9.937401985537386650e18;
            swapData = hex"83800a8e000000000000000000000000bf5495efe5db9ce00f80364c8b423567e58d211000000000000000000000000000000000000000000000000088e58446c3d52fb600000000000000000000000000000000000000000000000044f45f3a451bd44d288000000000000000000000be80225f09645f172b079394312220637c440a63053a717a";
        } else {
            revert UnknownSwapAmount_ReserveToBorrow(reservesAmount);
        }

        swapData = encode(swapData);
    }
}
