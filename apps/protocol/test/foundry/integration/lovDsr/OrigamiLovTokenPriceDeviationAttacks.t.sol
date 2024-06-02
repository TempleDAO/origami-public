pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";
import { OrigamiLovTokenIntegrationTestBase } from "test/foundry/integration/lovDsr/OrigamiLovTokenIntegrationTestBase.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { console } from "forge-std/console.sol";

contract OrigamiLovTokenIntegrationTest_PriceDeviationAttacksBase is OrigamiLovTokenIntegrationTestBase {
    using OrigamiMath for uint256;
    
    function setUp() public override {
        super.setUp();

        // Set both USDC/USD and DAI/USD == 1 (at peg)
        vm.mockCall(
            address(externalContracts.clDaiUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(5876, 1e8, 1701907679, 1701907679, 5876)
        );

        vm.mockCall(
            address(externalContracts.clUsdcUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(5876, 1e8, 1701907679, 1701907679, 5876)
        );

        // Use a dummy swapper so we can easily control the rates, and fund it
        lovTokenContracts.swapper = new DummyLovTokenSwapper();
        doMint(externalContracts.usdcToken, address(lovTokenContracts.swapper), 100_000_000e6);
        doMint(externalContracts.daiToken, address(lovTokenContracts.swapper), 100_000_000e18);

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovDsrManager.setSwapper(address(lovTokenContracts.swapper));
        lovTokenContracts.lovDsrManager.setFeeConfig(0, 50, 15);

        // @note massively increase the caps, just to test the extreme rebalances to allow the attacker
        // This is another line of defence that we're relaxing here.
        oUsdcContracts.cbUsdcBorrow.updateCap(100_000_000e6);
        oUsdcContracts.lendingClerk.setBorrowerDebtCeiling(address(lovTokenContracts.lovDsrManager), 100_000_000e18);
        lovTokenContracts.lovDsrManager.setRedeemableReservesBufferBps(0);

        vm.stopPrank();
    }

    function bootstrap() internal {
        investOusdc(bob, 100_000_000e6);

        uint256 amount = 250_000e18;
        uint256 aliceBalance = investLovDsr(alice, amount);
        uint256 bobBalance = investLovDsr(bob, amount);

        console.log("alice Balance [lovDSR]:", aliceBalance);
        console.log("bob Balance [lovDSR]:", bobBalance);

        (uint256 depositFeeBps, uint256 exitFeeBps) = lovTokenContracts.lovDsr.getDynamicFeesBps();
        console.log("depositFeeBps:", depositFeeBps);
        console.log("exitFeeBps:", exitFeeBps);
    }

    function solveRebalanceDownAmount(uint256 targetAL, uint256 dexPrice, uint256 oraclePrice) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceDownParam();
        uint256 currentAL = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();
        if (targetAL >= currentAL) revert InvalidRebalanceDownParam();

        // Note there may be a difference between the DEX executed price
        // vs the observed oracle price.
        // To account for this, the amount added to the liabilities needs to be scaled
        /*
          targetAL == (assets+X) / (liabilities+X*dexPrice/oraclePrice);
          targetAL*(liabilities+X*dexPrice/oraclePrice) == (assets+X)
          targetAL*liabilities + targetAL*X*dexPrice/oraclePrice == assets+X
          targetAL*liabilities + targetAL*X*dexPrice/oraclePrice - X == assets
          X*targetAL*dexPrice/oraclePrice - X == assets - targetAL*liabilities
          X * (targetAL*dexPrice/oraclePrice - 1) == assets - targetAL*liabilities
          X == (assets - targetAL*liabilities) / (targetAL*dexPrice/oraclePrice - 1)
        */
        uint256 _assets = lovTokenContracts.lovDsrManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;

        uint256 _netAssets = _assets - targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP);
        uint256 _priceScaledTargetAL = targetAL.mulDiv(dexPrice, oraclePrice, OrigamiMath.Rounding.ROUND_DOWN);

        reservesAmount = _netAssets.mulDiv(
            _precision,
            _priceScaledTargetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps,
        uint256 dexPrice
    ) internal virtual view returns (
        IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        uint256 oraclePrice = lovTokenContracts.daiUsdcOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // The actual AL we want to solve for needs to take the diff in dex vs oracle price into consideration.
        // uint256 adjustedTargetAL = targetAL.mulDiv(dexPrice, oraclePrice, OrigamiMath.Rounding.ROUND_DOWN);
        reservesAmount = solveRebalanceDownAmount(targetAL, dexPrice, oraclePrice);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = externalContracts.sDaiToken.previewMint(reservesAmount);

        // Use the dex price to calculate the USDC borrow amount
        params.borrowAmount = daiDepositAmount.mulDiv(dexPrice, 1e30, OrigamiMath.Rounding.ROUND_DOWN);
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: daiDepositAmount
        }));

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps));
        params.minReservesOut = OrigamiMath.subtractBps(reservesAmount, swapSlippageBps);
    }

    function solveRebalanceUpAmount(uint256 targetAL, uint256 dexPrice, uint256 oraclePrice) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceUpParam();
        uint256 currentAL = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();
        if (targetAL <= currentAL) revert InvalidRebalanceUpParam();

        // Note there may be a difference between the DEX executed price
        // vs the observed oracle price.
        // To account for this, the amount taken off the liabilities needs to be scaled
        /*
          targetAL == (assets-X) / (liabilities-X*dexPrice/oraclePrice);
          targetAL*(liabilities-X*dexPrice/oraclePrice) == (assets-X)
          targetAL*liabilities - targetAL*X*dexPrice/oraclePrice == assets-X
          X*targetAL*dexPrice/oraclePrice - X == targetAL*liabilities - assets
          X * (targetAL*dexPrice/oraclePrice - 1) == targetAL*liabilities - assets
          X = (targetAL*liabilities - assets) / (targetAL*dexPrice/oraclePrice - 1)
        */
        uint256 _assets = lovTokenContracts.lovDsrManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;
        
        uint256 _netAssets = targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP) - _assets;
        uint256 _priceScaledTargetAL = targetAL.mulDiv(dexPrice, oraclePrice, OrigamiMath.Rounding.ROUND_DOWN);

        reservesAmount = _netAssets.mulDiv(
            _precision,
            _priceScaledTargetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps,
        uint256 dexPrice
    ) internal virtual view returns (
        IOrigamiLovTokenErc4626Manager.RebalanceUpParams memory params
    ) {
        // The oracle price is used when solving for the correct balance of reserves to sell in order 
        // to hit the A/L
        uint256 oraclePrice = lovTokenContracts.daiUsdcOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // reserves (sDAI) amount
        params.minReserveAssetShares = solveRebalanceUpAmount(targetAL, dexPrice, oraclePrice);

        // How much DAI to sell for that reserves amount
        params.depositAssetsToWithdraw = externalContracts.sDaiToken.previewRedeem(params.minReserveAssetShares);

        // Intentionally calculate the min debt amount to repay based on the ORACLE price
        // This allows us to ensure the dex price isn't too far away from the oracle price
        // when the rebalance executes.
        params.minDebtAmountToRepay = lovTokenContracts.daiUsdcOracle.convertAmount(
            address(externalContracts.daiToken),
            params.depositAssetsToWithdraw,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        ).subtractBps(swapSlippageBps);

        // Mock the swap amount we receive is 1:1 with the DEX price
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.depositAssetsToWithdraw.mulDiv(dexPrice, 1e30, OrigamiMath.Rounding.ROUND_DOWN)
        }));

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps));
    }

    function doRebalance(
        uint256 targetAL, 
        uint256 swapSlippageBps, 
        uint256 alSlippageBps,
        uint256 dexPrice
    ) internal {
        uint256 currentAL = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();
        vm.startPrank(origamiMultisig);

        if (targetAL > currentAL) {
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, swapSlippageBps, alSlippageBps, dexPrice);
            lovTokenContracts.lovDsrManager.rebalanceUp(params);
            console.log("\t\tA/L after rebalanceUp:", lovTokenContracts.lovDsrManager.assetToLiabilityRatio());
        } else {
            (IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,) = rebalanceDownParams(targetAL, swapSlippageBps, alSlippageBps, dexPrice);
            lovTokenContracts.lovDsrManager.rebalanceDown(params);
            console.log("\t\tA/L after rebalanceDown:", lovTokenContracts.lovDsrManager.assetToLiabilityRatio());
        }
    }

    function exitLovDsr(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovDsr.exitQuote(
            amount,
            address(externalContracts.daiToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovDsr.exitToToken(quoteData, recipient);
    }

    function logLovTokenMetrics() internal view {
        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovDsr.assetsAndLiabilities();
        console.log("assets           ", assets);
        console.log("liabilities      ", liabilities);
        console.log("A/L              ", ratio);
        console.log("reservesPerShare ", lovTokenContracts.lovDsr.reservesPerShare());
        console.log("totalSupply      ", lovTokenContracts.lovDsr.totalSupply());
    }
}

/// Attacker max invests when DAI/USDC oracle = $1, but dex price = $0.995
/// When dex price returns to $1, exit all (needs multiple rebalances to do this)
///
/// RESULT: Attacker loses funds, vault share price increases.
contract OrigamiLovTokenIntegrationTest_PriceDeviationAttacks_A is OrigamiLovTokenIntegrationTest_PriceDeviationAttacksBase {
    uint256 public constant SWAP_SLIPPAGE = 30; // 0.3%
    uint256 public constant AL_SLIPPAGE = 10; // 0.1%

    function run(bool withAttack, uint256 dexPrice) internal {
        bootstrap();
        doRebalance(1.052e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
        logLovTokenMetrics();

        if (withAttack) {
            console.log("-------------------ATTACK----------------------");
            // Oracle price still at peg
            console.log(
                "\tDAI/USDC spot price:", 
                lovTokenContracts.daiUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN)
            );

            // Attacker max invests
            address attacker = makeAddr("attacker");
            uint256 depositAmount = lovTokenContracts.lovDsr.maxInvest(address(externalContracts.daiToken));
            console.log("\tattacker invested [DAI]:", depositAmount);
            uint256 attackerBalance = investLovDsr(attacker, depositAmount);
            console.log("\tattacker balance [lovDSR]:", attackerBalance);

            // The DEX price has returned to 1e18.
            // Vault rebalances back down, now with a pegged DAI/USDC rate
            doRebalance(1.128e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);

            // Can't exit entire position in one go, because of the A/L caps
            uint256 totalExited;
            uint256 totalReceived;
            while (totalExited < attackerBalance) {
                uint256 remainingToExit = attackerBalance - totalExited;
                uint256 maxExitAmount = lovTokenContracts.lovDsr.maxExit(address(externalContracts.daiToken));
                uint256 receivedAmount = exitLovDsr(attacker, maxExitAmount > remainingToExit ? remainingToExit : maxExitAmount, attacker);
                console.log("\tattacker received [DAI]:", receivedAmount);

                totalExited += maxExitAmount;
                totalReceived += receivedAmount;

                // Vault rebalances up again, attacker can now exit the remaining position
                doRebalance(1.11e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);
            }

            console.log("\tAttacker Total Received [DAI]:", totalReceived);
            if (totalReceived < depositAmount) {
                console.log("ATTACK NOT PROFITABLE");
            } else {
                console.log("*****ATTACK PROFITABLE*****");
            }
            assertLt(totalReceived, depositAmount);
        } else {
            doRebalance(1.11e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);
        }

        console.log("-----------------------------------------------");
        logLovTokenMetrics();
    }

    function test_PriceDeviationAttacks_a_down_noAttack() public {
        run(false, 0.995e18);
    }

    function test_PriceDeviationAttacks_a_down_withAttack() public {
        run(true, 0.995e18);  
    }

    function test_PriceDeviationAttacks_a_up_noAttack() public {
        run(false, 1.005e18);
    }

    function test_PriceDeviationAttacks_a_up_withAttack() public {
        run(true, 1.005e18);  
    }
}

/// Attacker max invests when DAI/USDC oracle and dex price = $1
/// Oracle remains at 1, dex price drops to 0.995
/// Attacker exits all (needs multiple rebalances to do this)
///
/// RESULT: Attacker loses funds, vault share price increases.
contract OrigamiLovTokenIntegrationTest_PriceDeviationAttacks_B is OrigamiLovTokenIntegrationTest_PriceDeviationAttacksBase {
    uint256 public constant SWAP_SLIPPAGE = 30; // 0.3%
    uint256 public constant AL_SLIPPAGE = 10; // 0.1%

    function run(bool withAttack, uint256 dexPrice) internal {
        bootstrap();
        doRebalance(1.052e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);
        logLovTokenMetrics();

        if (withAttack) {
            console.log("------------------ATTACK---------------------");
            // Oracle price still at peg
            console.log(
                "\tDAI/USDC oracle price:", 
                lovTokenContracts.daiUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN)
            );

            // Attacker max invests
            address attacker = makeAddr("attacker");
            uint256 depositAmount = lovTokenContracts.lovDsr.maxInvest(address(externalContracts.daiToken));
            console.log("\tattacker invested [DAI]:", depositAmount);
            uint256 attackerBalance = investLovDsr(attacker, depositAmount);
            console.log("\tattacker balance [lovDSR]:", attackerBalance);

            console.log("\tDAI/USDC dex price:", dexPrice);

            // Vault rebalances back down, now with a pegged DAI/USDC rate
            doRebalance(1.11e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);

            // Can't exit entire position in one go, because of the A/L caps
            uint256 totalExited;
            uint256 totalReceived;
            while (totalExited < attackerBalance) {
                uint256 remainingToExit = attackerBalance - totalExited;
                uint256 maxExitAmount = lovTokenContracts.lovDsr.maxExit(address(externalContracts.daiToken));
                uint256 receivedAmount = exitLovDsr(attacker, maxExitAmount > remainingToExit ? remainingToExit : maxExitAmount, attacker);
                console.log("\tattacker received [DAI]:", receivedAmount);

                totalExited += maxExitAmount;
                totalReceived += receivedAmount;

                // Vault rebalances up again, attacker can now exit the remaining position
                doRebalance(1.11e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
            }

            console.log("\tAttacker Total Received [DAI]:", totalReceived);
            if (totalReceived < depositAmount) {
                console.log("ATTACK NOT PROFITABLE");
            } else {
                console.log("*****ATTACK PROFITABLE*****");
            }
            assertLt(totalReceived, depositAmount);
        } else {
            doRebalance(1.11e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
        }

        console.log("-----------------------------------------------");
        logLovTokenMetrics();
    }

    function test_PriceDeviationAttacks_b_down_noAttack() public {
        // Dex prices can't be further than SWAP_SLIPPAGE away from the oracle price
        // or the rebalanceUp will (intentionally) fail from slippage
        run(false, 0.997e18);
    }

    function test_PriceDeviationAttacks_b_down_withAttack() public {
        run(true, 0.997e18);  
    }

    function test_PriceDeviationAttacks_b_up_noAttack() public {
        run(false, 1.003e18);
    }

    function test_PriceDeviationAttacks_b_up_withAttack() public {
        run(true, 1.003e18);  
    }
}
