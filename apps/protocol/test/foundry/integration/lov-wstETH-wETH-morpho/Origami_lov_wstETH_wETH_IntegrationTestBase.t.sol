pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ExternalContracts, LovTokenContracts, Origami_lov_wstETH_wETH_TestDeployer } from "test/foundry/deploys/lov-wstETH-wETH-morpho/Origami_lov_wstETH_wETH_TestDeployer.t.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { Origami_lov_wstETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-wstETH-wETH-morpho/Origami_lov_wstETH_wETH_TestConstants.t.sol";

contract Origami_lov_wstETH_wETH_IntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error BadSwapParam(uint256 expected, uint256 found);
    error UnknownSwapAmount(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    Origami_lov_wstETH_wETH_TestDeployer internal deployer;
    ExternalContracts public externalContracts;
    LovTokenContracts public lovTokenContracts;

    function setUp() public virtual {
        fork("mainnet", 19473049);
        vm.warp(1710903020);

        deployer = new Origami_lov_wstETH_wETH_TestDeployer(); 
        origamiMultisig = address(deployer);
        (externalContracts, lovTokenContracts) = deployer.deployForked(origamiMultisig, feeCollector, overlord);
    }

    function investlovWstEth(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(externalContracts.wstEthToken, account, amount);
        vm.startPrank(account);
        externalContracts.wstEthToken.approve(address(lovTokenContracts.lovWstEth), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovWstEth.investQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovWstEth.investWithToken(quoteData);
    }

    function exitlovWstEth(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovWstEth.exitQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovWstEth.exitToToken(quoteData, recipient);
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        reservesAmount = LovTokenHelpers.solveRebalanceDownAmount(lovTokenContracts.lovWstEthManager, targetAL);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        params.borrowAmount = lovTokenContracts.wstEthToEthOracle.convertAmount(
            address(externalContracts.wstEthToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        (reservesAmount, params.swapData) = swapWEthToWstEthQuote(params.borrowAmount);
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
        lovTokenContracts.lovWstEthManager.rebalanceDown(params);
    }
    
    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params
    ) {
        // ideal reserves (wstETH) amount to remove
        params.withdrawCollateralAmount = LovTokenHelpers.solveRebalanceUpAmount(lovTokenContracts.lovWstEthManager, targetAL);

        (params.repayAmount, params.swapData) = swapWstEthToWEthQuote(params.withdrawCollateralAmount);

        // If there's a fee (currently disabled on Spark) then remove that from what we want to request
        uint256 feeBps = 0;
        params.repayAmount = params.repayAmount.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [wstETH] to the flashloan asset [wETH].
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

        lovTokenContracts.lovWstEthManager.rebalanceUp(params);
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiDexAggregatorSwapper.RouteData({
            router: Constants.ONE_INCH_ROUTER,
            data: data
        }));
    }

    function swapWEthToWstEthQuote(uint256 ethAmount) internal pure returns (uint256 wstEthAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&amount=463795587257521068400&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (ethAmount == 463.795587257521068400e18) {
            wstEthAmount = 399.842233817039274556e18;
            swapData = hex"e449022e0000000000000000000000000000000000000000000000192474ed50fe3ad97000000000000000000000000000000000000000000000000ad6767c99cfa7411e00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001800000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else if (ethAmount == 927.591174515042136800e18) {
            wstEthAmount = 799.648892665393124790e18;
            swapData = hex"e449022e00000000000000000000000000000000000000000000003248e9daa1fc75b2e0000000000000000000000000000000000000000000000015acadc794319c8adb00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001800000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else if (ethAmount == 928.591174515042136801e18) {
            wstEthAmount = 800.510878056076160998e18;
            swapData = hex"e449022e00000000000000000000000000000000000000000000003256ca9155a3d9b2e1000000000000000000000000000000000000000000000015b2a8f926dc3b17f300000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001800000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else {
            revert UnknownSwapAmount(ethAmount);
        }

        swapData = encode(swapData);
    }

    function swapWstEthToWEthQuote(uint256 wstEthAmount) internal pure returns (uint256 wEthAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=16573668788552807277&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */
        
        if (wstEthAmount == 16.573668788552807277e18) {
            wEthAmount = 19.224264116779406090e18;
            swapData = hex"12aa3caf000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e6017ff3beab336d0000000000000000000000000000000000000000000000008565272e0a7669850000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000017c00000000000000000000000000000000000000000000000000015e00013051204a585e0f7c18e2c414221d6402652d5e0990e5f87f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a4a5dcbcdf0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000eb1c92f9f5ec9d817968afddb4b46c564cdedbe000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc21111111254eeb25477b68fb85ed929f73a960582000000008b1ccac8";
        } else 
        if (wstEthAmount == 15.728428159802133224e18) {
            wEthAmount = 18.225775796180697309e18;
            swapData = hex"e449022e000000000000000000000000000000000000000000000000da469a141c41cae8000000000000000000000000000000000000000000000000fcae36469b2cea0300000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else if (wstEthAmount == 800.510878056076160998e18) {
            wEthAmount = 928.427098371953801359e18;
            swapData = hex"12aa3caf000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b6551f24db8762fe60000000000000000000000000000000000000000000000192a41d379d17a1c47000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003bd00000000000000000000000000000000000000039f00037100032700030d00a0c9e75c48000000000000000009010000000000000000000000000000000000000000000000000002df00004f00a0fbb7cd060093d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c27f39c581f595b53c5cb19bd0b3f8da6c935e2ca0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a007e5c0d200000000000000000000000000000000000000000000026c00005600003c41207f39c581f595b53c5cb19bd0b3f8da6c935e2ca00004de0e9a3e00000000000000000000000000000000000000000000000000000000000000000020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8400a0c9e75c48000000000000000020120000000000000000000000000000000000000000000000000001e80000f400a007e5c0d20000000000000000000000000000000000000000000000d00000b60000b05100dc24316b9ae028f1497c275eb9192a3ea0f67022ae7ab96520de3a18e5e111b5eaab095312d7fe8400443df021240000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000082759e5561b47ba1000206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db000a007e5c0d20000000000000000000000000000000000000000000000d00000b60000b0512021e27a5e5513d6e65c4f830167390997aa84843aae7ab96520de3a18e5e111b5eaab095312d7fe8400443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e7eaea604f309145500206b4be0b94041c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2d0e30db00020d6bdbf78c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b66c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000325483a6f3a2f4388f00000000000000000005841d37e1507c80a06c4eca27c02aaa39b223fe8d0a0e5c4f27ead9083c756cc21111111254eeb25477b68fb85ed929f73a9605820000008b1ccac8";
        } else {
            revert UnknownSwapAmount(wstEthAmount);
        }

        swapData = encode(swapData);
    }
}
