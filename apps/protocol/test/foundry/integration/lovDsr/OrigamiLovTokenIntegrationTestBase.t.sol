pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { ExternalContracts, OUsdcContracts, LovTokenContracts, OrigamiLovTokenTestDeployer } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestDeployer.t.sol";

import { OrigamiAaveV3IdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovTokenTestConstants as Constants } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestConstants.t.sol";

contract OrigamiLovTokenIntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error UnknownSwapAmount(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    OrigamiLovTokenTestDeployer internal deployer;
    ExternalContracts public externalContracts;
    OUsdcContracts public oUsdcContracts;
    LovTokenContracts public lovTokenContracts;

    IERC20 public aToken;

    function setUp() public virtual {
        fork("mainnet", 18730850);
        vm.warp(1701909032); // The unix ts of block #18730850

        deployer = new OrigamiLovTokenTestDeployer(); 
        origamiMultisig = address(deployer);
        (externalContracts, oUsdcContracts, lovTokenContracts) = deployer.deployForked(origamiMultisig, feeCollector, overlord);
        aToken = OrigamiAaveV3IdleStrategy(address(oUsdcContracts.idleStrategy)).aToken();
    }

    function investOvUsdc(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(externalContracts.usdcToken, account, amount);
        vm.startPrank(account);
        externalContracts.usdcToken.approve(address(oUsdcContracts.ovUsdc), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = oUsdcContracts.ovUsdc.investQuote(
            amount,
            address(externalContracts.usdcToken),
            0,
            0
        );

        amountOut = oUsdcContracts.ovUsdc.investWithToken(quoteData);
    }

    function exitOvUsdc(address account, uint256 amount) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oUsdcContracts.ovUsdc.exitQuote(
            amount,
            address(externalContracts.usdcToken),
            0,
            0
        );

        amountOut = oUsdcContracts.ovUsdc.exitToToken(quoteData, account);
    }

    function investLovDsr(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(externalContracts.daiToken, account, amount);
        vm.startPrank(account);
        externalContracts.daiToken.approve(address(lovTokenContracts.lovDsr), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovDsr.investQuote(
            amount,
            address(externalContracts.daiToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovDsr.investWithToken(quoteData);
    }

    function solveRebalanceDownAmount(uint256 targetAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceDownParam();
        uint256 currentAL = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();
        if (targetAL >= currentAL) revert InvalidRebalanceDownParam();

        /*
          targetAL == (assets+X) / (liabilities+X);
          targetAL*(liabilities+X) == (assets+X)
          targetAL*liabilities + targetAL*X == assets+X
          targetAL*liabilities + targetAL*X - X == assets
          targetAL*X - X == assets - targetAL*liabilities
          X * (targetAL - 1) == assets - targetAL*liabilities
          X == (assets - targetAL*liabilities) / (targetAL - 1)
        */
        uint256 _assets = lovTokenContracts.lovDsrManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;

        uint256 _netAssets = _assets - targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP);
        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function solveRebalanceUpAmount(uint256 targetAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceUpParam();
        uint256 currentAL = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();
        if (targetAL <= currentAL) revert InvalidRebalanceUpParam();

        /*
          targetAL == (assets-X) / (liabilities-X);
          targetAL*(liabilities-X) == (assets-X)
          targetAL*liabilities - targetAL*X == assets-X
          targetAL*X - X == targetAL*liabilities - assets
          X - targetAL*X == targetAL*liabilities - assets
          X * (targetAL - 1) == targetAL*liabilities - assets
          X = (targetAL*liabilities - assets) / (targetAL - 1)
        */
        uint256 _assets = lovTokenContracts.lovDsrManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;
        
        uint256 _netAssets = targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP) - _assets;
        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function mintSDai(uint256 sDaiAmount, address to) internal {
        uint256 daiAmount = externalContracts.sDaiToken.previewMint(sDaiAmount);
        doMint(externalContracts.daiToken, to, daiAmount);
        vm.startPrank(to);
        externalContracts.daiToken.approve(address(externalContracts.sDaiToken), daiAmount);
        externalContracts.sDaiToken.mint(sDaiAmount, to);
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        reservesAmount = solveRebalanceDownAmount(targetAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = externalContracts.sDaiToken.previewMint(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        params.borrowAmount = lovTokenContracts.daiUsdcOracle.convertAmount(
            address(externalContracts.daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        (daiDepositAmount, params.swapData) = swapUsdcToDaiQuote(params.borrowAmount);
        
        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
        params.minReservesOut = OrigamiMath.subtractBps(reservesAmount, swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(uint256 targetAL, uint256 swapSlippageBps, uint256 alSlippageBps) internal virtual returns (uint256) {
        vm.startPrank(origamiMultisig);
        (IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params, uint256 _reservesAmount) = rebalanceDownParams(targetAL, swapSlippageBps, alSlippageBps);
        lovTokenContracts.lovDsrManager.rebalanceDown(params);
        return _reservesAmount;
    }
    
    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (IOrigamiLovTokenErc4626Manager.RebalanceUpParams memory params) {
        // reserves (sDAI) amount
        params.minReserveAssetShares = solveRebalanceUpAmount(targetAL);

        // How much DAI to sell for that reserves amount
        params.depositAssetsToWithdraw = externalContracts.sDaiToken.previewRedeem(params.minReserveAssetShares);
        (params.minDebtAmountToRepay, params.swapData) = swapDaiToUsdcQuote(params.depositAssetsToWithdraw);
        params.minDebtAmountToRepay = OrigamiMath.subtractBps(params.minDebtAmountToRepay, swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(uint256 targetAL, uint256 swapSlippageBps, uint256 alSlippageBps) internal virtual returns (uint256) {
        vm.startPrank(origamiMultisig);
        IOrigamiLovTokenErc4626Manager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, swapSlippageBps, alSlippageBps);
        lovTokenContracts.lovDsrManager.rebalanceUp(params);
        return params.minReserveAssetShares;
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiDexAggregatorSwapper.RouteData({
            router: Constants.ONE_INCH_ROUTER,
            data: data
        }));
    }

    function swapDaiToUsdcQuote(uint256 daiAmount) internal pure returns (uint256 usdcAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&amount=90940470138313788303434&from=0x0000000000000000000000000000000000000000&slippage=0.1&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (daiAmount == 90_940.470138313788303434e18) {
            usdcAmount = 90_931.486313e6;
            swapData = hex"e449022e000000000000000000000000000000000000000000001341e48c37891c17284a000000000000000000000000000000000000000000000000000000152684dd4a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005777d92f208679db4b9778590fa3cab3ac9e21688b1ccac8";
        } else if (daiAmount == 14_209.740229376744426659e18) {
            usdcAmount = 14_208.338840e6;
            swapData = hex"e449022e0000000000000000000000000000000000000000000003024fc27c30128d0ca3000000000000000000000000000000000000000000000000000000034e093e45000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005777d92f208679db4b9778590fa3cab3ac9e21688b1ccac8";
        } else {
            revert UnknownSwapAmount(daiAmount);
        }

        swapData = encode(swapData);
    }

    function swapUsdcToDaiQuote(uint256 usdcAmount) internal pure returns (uint256 daiAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&amount=90889809999&from=0x0000000000000000000000000000000000000000&slippage=0.1&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */
        
        if (usdcAmount == 90_889.809999e6) {
            daiAmount = 90_880.379225821236844346e18;
            swapData = hex"e449022e000000000000000000000000000000000000000000000000000000152974704f000000000000000000000000000000000000000000001339b5667199109d08cd000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000018000000000000000000000005777d92f208679db4b9778590fa3cab3ac9e21688b1ccac8";
        } else {
            revert UnknownSwapAmount(usdcAmount);
        }

        swapData = encode(swapData);
    }
}
