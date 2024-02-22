pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ExternalContracts, LovTokenContracts, OrigamiLovStEthTestDeployer } from "test/foundry/deploys/lovStEth/OrigamiLovStEthTestDeployer.t.sol";
import { OrigamiAaveV3IdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";

contract OrigamiLovStEthIntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error BadSwapParam(uint256 expected, uint256 found);
    error UnknownSwapAmount(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    OrigamiLovStEthTestDeployer internal deployer;
    ExternalContracts public externalContracts;
    LovTokenContracts public lovTokenContracts;

    // IERC20 public aToken;

    function setUp() public virtual {
        fork("mainnet", 19238000);
        vm.warp(1708056616);

        deployer = new OrigamiLovStEthTestDeployer(); 
        origamiMultisig = address(deployer);
        (externalContracts, lovTokenContracts) = deployer.deployForked(origamiMultisig, feeCollector, overlord);
        // aToken = OrigamiAaveV3IdleStrategy(address(oUsdcContracts.idleStrategy)).aToken();
    }

    function investLovStEth(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(externalContracts.wstEthToken, account, amount);
        vm.startPrank(account);
        externalContracts.wstEthToken.approve(address(lovTokenContracts.lovStEth), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovStEth.investQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovStEth.investWithToken(quoteData);
    }

    function exitLovStEth(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovStEth.exitQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovStEth.exitToToken(quoteData, recipient);
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        reservesAmount = LovTokenHelpers.solveRebalanceDownAmount(lovTokenContracts.lovStEthManager, targetAL);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        params.flashLoanAmount = lovTokenContracts.wstEthToEthOracle.convertAmount(
            address(externalContracts.wstEthToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        (reservesAmount, params.swapData) = swapWEthToWstEthQuote(params.flashLoanAmount);

        params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps));
        params.maxNewAL = uint128(targetAL.addBps(alSlippageBps));
        params.minExpectedReserveToken = reservesAmount.subtractBps(swapSlippageBps);
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual returns (uint256 reservesAmount) {
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params;
        (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, alSlippageBps);

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovStEthManager.rebalanceDown(params);
    }
    
    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params
    ) {
        // ideal reserves (wstETH) amount to remove
        params.collateralToWithdraw = LovTokenHelpers.solveRebalanceUpAmount(lovTokenContracts.lovStEthManager, targetAL);

        (params.flashLoanAmount, params.swapData) = swapWstEthToWEthQuote(params.collateralToWithdraw);

        // If there's a fee (currently disabled on Spark) then remove that from what we want to request
        uint256 feeBps = 0;
        params.flashLoanAmount = params.flashLoanAmount.inverseSubtractBps(feeBps);

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [wstETH] to the flashloan asset [wETH].
        // We need to be sure it can be paid off. Any remaining wETH is repaid on the wETH debt in Spark
        params.flashLoanAmount = params.flashLoanAmount.subtractBps(swapSlippageBps);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = 0;

        params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps));
        params.maxNewAL = uint128(targetAL.addBps(alSlippageBps));
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual {
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, slippageBps, alSlippageBps);
        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovStEthManager.rebalanceUp(params);
    }

    function swapWEthToWstEthQuote(uint256 ethAmount) internal pure returns (uint256 wstEthAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&dst=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&amount=926490121494033092800&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (ethAmount == 462.745060747016546400e18) {
            wstEthAmount = 399.895276763268114781e18;
            swapData = hex"12aa3caf000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001915e0b505607a286000000000000000000000000000000000000000000000000ad6d4b5bd778ef4ae000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002ba00000000000000000000000000000000000000029c00026e00022400020a00a0c9e75c48000000000000000007030000000000000000000000000000000000000000000000000001dc00016600a007e5c0d20000000000000000000000000000000000000001420000f20000d800003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004160dc24316b9ae028f1497c275eb9192a3ea0f6702200443df02124000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c36791c4896f519a0020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8451207f39c581f595b53c5cb19bd0b3f8da6c935e2ca0ae7ab96520de3a18e5e111b5eaab095312d7fe840004ea598cb0000000000000000000000000000000000000000000000000000000000000000000a007e5c0d200000000000000000000000000000000000000000000000000005200003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d000000000000000000000000000000000000000000000000000000000000000040607f39c581f595b53c5cb19bd0b3f8da6c935e2ca00020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca000a0f2fa6b667f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000015ada96b7aef1de95d000000000000000000056456d6a0293a80a06c4eca277f39c581f595b53c5cb19bd0b3f8da6c935e2ca01111111254eeb25477b68fb85ed929f73a9605820000000000008b1ccac8";
        } else if (ethAmount == 925.490121494033092800e18) {
            wstEthAmount = 799.786173537908446329e18;
            swapData = hex"12aa3caf000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000322bc16a0ac0f450c0000000000000000000000000000000000000000000000015ada1a3b125fa2a3c0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000037f0000000000000000000000000000000000000000000003610003330002e900a0c9e75c48000000000000000005050000000000000000000000000000000000000000000000000002bb00026c00a007e5c0d200000000000000000000000000000000000000024800022e0001de0001c400a0c9e75c48000000000000000021110000000000000000000000000000000000000000000000000001960000fc00a007e5c0d20000000000000000000000000000000000000000000000000000d800003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004140dc24316b9ae028f1497c275eb9192a3ea0f6702200443df0212400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000443d8207051cd536e00a007e5c0d200000000000000000000000000000000000000000000000000007600003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004060ae7ab96520de3a18e5e111b5eaab095312d7fe84a1903eab00000000000000000000000042f527f50f16a103b6ccab48bccca214500c10210020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8451207f39c581f595b53c5cb19bd0b3f8da6c935e2ca0ae7ab96520de3a18e5e111b5eaab095312d7fe840004ea598cb000000000000000000000000000000000000000000000000000000000000000000020d6bdbf787f39c581f595b53c5cb19bd0b3f8da6c935e2ca002a000000000000000000000000000000000000000000000000ad6cc75caa9ada339ee63c1e500109830a1aaad605bbf02a9dfa7b0b92ec2fb7daac02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b667f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000002b5b4347624bf45479000000000000000000056456d6a0293a80a06c4eca277f39c581f595b53c5cb19bd0b3f8da6c935e2ca01111111254eeb25477b68fb85ed929f73a960582008b1ccac8";
        } else if (ethAmount == 926.490121494033092800e18) {
            wstEthAmount = 800.585207235220226188e18;
            swapData = hex"12aa3caf000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003239a220be685850c0000000000000000000000000000000000000000000000015b32d02262be52046000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002520000000000000000000000000000000000000000000002340002060001bc00a0c9e75c4800000000000000240a0400000000000000000000000000000000000000000000018e00013f0000f051104370e48e610d2e02d3d091a9d79c8eb9a54c5b1cc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2004475d39ecb000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d25000000000000000000000000000000000000000000000001bc70b0f001caadec0000000000000000000000000000000000000000000000000000000065d7e9db00a0fbb7cd060093d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2c02aaa39b223fe8d0a0e5c4f27ead9083c756cc27f39c581f595b53c5cb19bd0b3f8da6c935e2ca002a000000000000000000000000000000000000000000000000f9fb36d9c98d41167ee63c1e500109830a1aaad605bbf02a9dfa7b0b92ec2fb7daac02aaa39b223fe8d0a0e5c4f27ead9083c756cc200a0f2fa6b667f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000002b665a044c57ca408c0000000000000000000581602e71a94580a06c4eca277f39c581f595b53c5cb19bd0b3f8da6c935e2ca01111111254eeb25477b68fb85ed929f73a96058200000000000000000000000000008b1ccac8";
        } else {
            revert UnknownSwapAmount(ethAmount);
        }
    }

    function swapWstEthToWEthQuote(uint256 wstEthAmount) internal pure returns (uint256 wEthAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&dst=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=800585207235220226188&from=0x0000000000000000000000000000000000000000&slippage=0.1&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */
        
        if (wstEthAmount == 16.190178744091424724e18) {
            wEthAmount = 18.730857679374077044e18;
            swapData = hex"e449022e000000000000000000000000000000000000000000000000e0af11c9dba637d400000000000000000000000000000000000000000000000103aed434072c057600000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else if (wstEthAmount == 799.786173537908446329e18) {
            wEthAmount = 925.342005943326071238e18;
            swapData = hex"e449022e00000000000000000000000000000000000000000000002b5b4347624bf454790000000000000000000000000000000000000000000000321cdbba14e75a044e00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else if (wstEthAmount == 800.585207235220226188e18) {
            wEthAmount = 926.266441229050160143e18;
            swapData = hex"e449022e00000000000000000000000000000000000000000000002b665a044c57ca408c00000000000000000000000000000000000000000000003229acb24ea1f302de00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000109830a1aaad605bbf02a9dfa7b0b92ec2fb7daa8b1ccac8";
        } else {
            revert UnknownSwapAmount(wstEthAmount);
        }
    }
}
