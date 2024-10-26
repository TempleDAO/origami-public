pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ExternalContracts, LovTokenContracts, Origami_lov_USDe_DAI_TestDeployer } from "test/foundry/deploys/lov-USDe-DAI/Origami_lov_USDe_DAI_TestDeployer.t.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { Origami_lov_USDe_DAI_TestConstants as Constants } from "test/foundry/deploys/lov-USDe-DAI/Origami_lov_USDe_DAI_TestConstants.t.sol";

contract Origami_lov_USDe_DAI_IntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error BadSwapParam(uint256 expected, uint256 found);
    error UnknownSwapAmount_BorrowToReserve(uint256 amount);
    error UnknownSwapAmount_ReserveToBorrow(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    Origami_lov_USDe_DAI_TestDeployer internal deployer;
    ExternalContracts public externalContracts;
    LovTokenContracts public lovTokenContracts;

    function setUp() public virtual {
        fork("mainnet", 19615168);
        vm.warp(1712628826);

        deployer = new Origami_lov_USDe_DAI_TestDeployer(); 
        origamiMultisig = address(deployer);
        (externalContracts, lovTokenContracts) = deployer.deployForked(origamiMultisig, feeCollector, overlord);

        // Bootstrap the morpho pool with some DAI
        supplyIntoMorpho(500_000e18);
    }

    function supplyIntoMorpho(uint256 amount) internal {
        doMint(externalContracts.daiToken, origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        IMorpho morpho = lovTokenContracts.borrowLend.morpho();
        SafeERC20.forceApprove(externalContracts.daiToken, address(morpho), amount);
        morpho.supply(lovTokenContracts.borrowLend.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }

    function investLovToken(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(externalContracts.usdeToken, account, amount);
        vm.startPrank(account);
        externalContracts.usdeToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.usdeToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.usdeToken),
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
        params.borrowAmount = lovTokenContracts.usdeToDaiOracle.convertAmount(
            address(externalContracts.usdeToken),
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
"https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&amount=200416930000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (borrowAmount == 200_416.93e18) {
            reservesAmount = 199_960.950811050801985097e18;
            swapData = hex"83800a8e0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000002a709fa0ac98889d000000000000000000000000000000000000000000000000152ccd9290b41ba990f1481000010008010802000000f36a4ba50c603204c3fc6d2da8b78a7b69cbc67d8b1ccac8";
        } else if (borrowAmount == 400_833.86e18) {
            reservesAmount = 399_943.183073951018774546e18;
            swapData = hex"83800a8e0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000054e13f415931113a0000000000000000000000000000000000000000000000002a587b509ffab76af809481000010008010802000000f36a4ba50c603204c3fc6d2da8b78a7b69cbc67d8b1ccac8";
        } else if (borrowAmount == 401_833.860000000000000001e18) {
            reservesAmount = 400_940.852442086194862513e18;
            swapData = hex"83800a8e0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000005517750b06f6efda0001000000000000000000000000000000000000000000002a7386096e330c366cd8481000010008010802000000f36a4ba50c603204c3fc6d2da8b78a7b69cbc67d8b1ccac8";
        } else if (borrowAmount == 200.41693e18) {
            reservesAmount = 199.992677359955992715e18;
            swapData = hex"83800a8e0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000add57f7fb085420000000000000000000000000000000000000000000000000056bba5c39e3bdf045481000010008010802000000f36a4ba50c603204c3fc6d2da8b78a7b69cbc67d8b1ccac8";
        } else {
            revert UnknownSwapAmount_BorrowToReserve(borrowAmount);
        }

        swapData = encode(swapData);
    }

    function swapReserveTokenToBorrowTokenQuote(uint256 reservesAmount) internal pure returns (uint256 borrowAmount, bytes memory swapData) {
        // @note Ensure sDAI is listed as a connector token

        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&amount=400940852442086194862513&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */
        
        if (reservesAmount == 33_358.893728444150987197e18) {
            borrowAmount = 33_401.491373523270306672e18;
            swapData = hex"83800a8e0000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b300000000000000000000000000000000000000000000071063a60f06afc039bd0000000000000000000000000000000000000000000003895967a5c44c6985b8481001000108000802000000f36a4ba50c603204c3fc6d2da8b78a7b69cbc67d8b1ccac8";
        } else if (reservesAmount == 400_940.852442086194862513e18) {
            borrowAmount = 401_520.766447832894814759e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b30000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000054e70c12dc66186cd9b1000000000000000000000000000000000000000000002a833dffa40dff281d130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002c40000000000000000000000000000000000000002a600027800024a00020000a007e5c0d20000000000000000000000000000000000000000000001dc0001600000b051205dc1bf6f1e983c0b21efb003c105133736fa07434c9edd5852cd905f086c759e8383e09bff1e68b300443df02124000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a99b8e4ea7f05b5c4325120ce6431d21e3fb1036ce9973a3312368ed96f5ce7853d955acef822db058eb8505911ed77f175b99e00443df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000027b43a0eeaa8269aa040412083f20f44975d03b1b09e64809b757c47f942beea0004ba0876520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd0900a0f2fa6b666b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000055067bff481bfe503a2700000000000000004582b589dee110dc80a06c4eca276b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a650020d6bdbf786b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000008b1ccac8";
        } else {
            revert UnknownSwapAmount_ReserveToBorrow(reservesAmount);
        }

        swapData = encode(swapData);
    }
}
