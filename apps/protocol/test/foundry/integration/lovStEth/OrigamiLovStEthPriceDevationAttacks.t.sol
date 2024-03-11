pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";
import { OrigamiLovStEthIntegrationTestBase } from "test/foundry/integration/lovStEth/OrigamiLovStEthIntegrationTestBase.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { console } from "forge-std/console.sol";
import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

contract OrigamiLovStEthIntegrationTest_PriceDeviationAttacksBase is OrigamiLovStEthIntegrationTestBase {
    using OrigamiMath for uint256;
    
    function setUp() public override {
        super.setUp();

        // Set stETH/ETH == 1 (at peg)
        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(921, 1e18, 1708008239, 1708008239, 921)
        );

        // Use a dummy swapper so we can easily control the rates, and fund it
        lovTokenContracts.swapper = new DummyLovTokenSwapper();
        doMint(externalContracts.wstEthToken, address(lovTokenContracts.swapper), 100_000e18);
        deal(address(externalContracts.wethToken), address(lovTokenContracts.swapper), 100_000e18);

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovStEthManager.setSwapper(address(lovTokenContracts.swapper));
        lovTokenContracts.lovStEthManager.setFeeConfig(0, 50, 15);
        lovTokenContracts.lovStEthManager.setRedeemableReservesBufferBps(0);

        vm.stopPrank();
    }

    function bootstrap() internal {
        uint256 amount = 100e18;
        uint256 aliceBalance = investLovStEth(alice, amount);
        uint256 bobBalance = investLovStEth(bob, amount);

        console.log("alice Balance [lovStEth]:", aliceBalance);
        console.log("bob Balance [lovStEthlovDSR]:", bobBalance);

        (uint256 depositFeeBps, uint256 exitFeeBps) = lovTokenContracts.lovStEth.getDynamicFeesBps();
        console.log("depositFeeBps:", depositFeeBps);
        console.log("exitFeeBps:", exitFeeBps);
    }

    function solveRebalanceDownAmount(uint256 targetAL, uint256 dexPrice, uint256 oraclePrice) internal view returns (uint256 reservesAmount) {
        console.log("solveRebalanceDownAmount:", targetAL, dexPrice);
        if (targetAL <= 1e18) revert InvalidRebalanceDownParam();
        uint256 currentAL = lovTokenContracts.lovStEthManager.assetToLiabilityRatio();
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
        uint256 _assets = lovTokenContracts.lovStEthManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovStEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;

        uint256 _netAssets = _assets - targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP);
        uint256 _priceScaledTargetAL = targetAL.mulDiv(dexPrice, oraclePrice, OrigamiMath.Rounding.ROUND_DOWN);
        console.log("\tassets:", _assets);
        console.log("\t_liabilities:", _liabilities);
        console.log("\t_netAssets:", _netAssets);
        console.log("\t_priceScaledTargetAL:", _priceScaledTargetAL);

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
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        uint256 oraclePrice = lovTokenContracts.wstEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        console.log("oraclePrice", oraclePrice);

        // The actual AL we want to solve for needs to take the diff in dex vs oracle price into consideration.
        // uint256 adjustedTargetAL = targetAL.mulDiv(dexPrice, oraclePrice, OrigamiMath.Rounding.ROUND_DOWN);
        reservesAmount = solveRebalanceDownAmount(targetAL, dexPrice, oraclePrice);
        console.log("reservesAmount", reservesAmount);

        // Use the dex price to calculate the wETH flash loan
        params.flashLoanAmount = reservesAmount.mulDiv(dexPrice, 1e18, OrigamiMath.Rounding.ROUND_DOWN);

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: reservesAmount
        }));

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps));
        params.minExpectedReserveToken = reservesAmount.subtractBps(swapSlippageBps);
    }

    function solveRebalanceUpAmount(uint256 targetAL, uint256 dexPrice, uint256 oraclePrice) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceUpParam();
        uint256 currentAL = lovTokenContracts.lovStEthManager.assetToLiabilityRatio();
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
        uint256 _assets = lovTokenContracts.lovStEthManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovStEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
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
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params
    ) {
        // The oracle price is used when solving for the correct balance of reserves to sell in order 
        // to hit the A/L
        uint256 oraclePrice = lovTokenContracts.wstEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // ideal reserves (wstETH) amount to remove
        params.collateralToWithdraw = solveRebalanceUpAmount(targetAL, dexPrice, oraclePrice);

        // Mock the swap amount we receive is 1:1 with the DEX price
        params.flashLoanAmount = params.collateralToWithdraw.mulDiv(dexPrice, 1e18, OrigamiMath.Rounding.ROUND_DOWN);
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.flashLoanAmount
        }));

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [wstETH] to the flashloan asset [wETH].
        // We need to be sure it can be paid off. Any remaining wETH is repaid on the wETH debt in Spark
        params.flashLoanAmount = params.flashLoanAmount.subtractBps(swapSlippageBps);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = 0;

        params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps));
        params.maxNewAL = uint128(targetAL.addBps(alSlippageBps));
    }

    function doRebalance(
        uint256 targetAL, 
        uint256 swapSlippageBps, 
        uint256 alSlippageBps,
        uint256 dexPrice
    ) internal {
        uint256 currentAL = lovTokenContracts.lovStEthManager.assetToLiabilityRatio();
        vm.startPrank(origamiMultisig);

        dexPrice = dexPrice.mulDiv(lovTokenContracts.wstEthToEthOracle.stEth().getPooledEthByShares(1e18), 1e18, OrigamiMath.Rounding.ROUND_DOWN);

        if (targetAL > currentAL) {
            IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, swapSlippageBps, alSlippageBps, dexPrice);
            lovTokenContracts.lovStEthManager.rebalanceUp(params);
            console.log("\t\tA/L after rebalanceUp:", lovTokenContracts.lovStEthManager.assetToLiabilityRatio());
        } else {
            (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params,) = rebalanceDownParams(targetAL, swapSlippageBps, alSlippageBps, dexPrice);
            lovTokenContracts.lovStEthManager.rebalanceDown(params);
            console.log("\t\tA/L after rebalanceDown:", lovTokenContracts.lovStEthManager.assetToLiabilityRatio());
        }
    }

    function logLovTokenMetrics() internal view {
        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovStEth.assetsAndLiabilities();
        console.log("assets           ", assets);
        console.log("liabilities      ", liabilities);
        console.log("A/L              ", ratio);
        console.log("reservesPerShare ", lovTokenContracts.lovStEth.reservesPerShare());
        console.log("totalSupply      ", lovTokenContracts.lovStEth.totalSupply());
    }
}

/// Attacker max invests when stETH/ETH oracle = $1, but dex price = $0.995
/// When dex price returns to $1, exit all (needs multiple rebalances to do this)
///
/// RESULT: Attacker loses funds, vault share price increases.
contract OrigamiLovStEthIntegrationTest_PriceDeviationAttacks_A is OrigamiLovStEthIntegrationTest_PriceDeviationAttacksBase {
    uint256 public constant SWAP_SLIPPAGE = 30; // 0.3%
    uint256 public constant AL_SLIPPAGE = 10; // 0.1%

    function run(bool withAttack, uint256 dexPrice) internal {
        bootstrap();
        doRebalance(1.113e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
        logLovTokenMetrics();

        if (withAttack) {
            console.log("-------------------ATTACK----------------------");
            (,int256 answer,,,) = externalContracts.clStEthToEthOracle.latestRoundData();
            console.log(
                "\tstETH/ETH spot price:", 
                uint256(answer)
            );

            // Attacker max invests
            address attacker = makeAddr("attacker");
            uint256 depositAmount = lovTokenContracts.lovStEth.maxInvest(address(externalContracts.wstEthToken));
            console.log("\tattacker invested [wstETH]:", depositAmount);
            uint256 attackerBalance = investLovStEth(attacker, depositAmount);
            console.log("\tattacker balance [lovStEth]:", attackerBalance);

            // The DEX stETH/ETH price has returned to 1e18.
            // Vault rebalances back down, now with a pegged stETH/ETH rate
            doRebalance(1.113e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);

            // Can't exit entire position in one go, because of the A/L caps
            uint256 totalExited;
            uint256 totalReceived;
            while (totalExited < attackerBalance) {
                uint256 remainingToExit = attackerBalance - totalExited;
                uint256 maxExitAmount = lovTokenContracts.lovStEth.maxExit(address(externalContracts.wstEthToken));
                uint256 receivedAmount = exitLovStEth(attacker, maxExitAmount > remainingToExit ? remainingToExit : maxExitAmount, attacker);
                console.log("\tattacker received [wstETH]:", receivedAmount);

                totalExited += maxExitAmount;
                totalReceived += receivedAmount;

                // Vault rebalances up again, attacker can now exit the remaining position
                doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);
            }

            console.log("\tAttacker Total Received [wstETH]:", totalReceived);
            if (totalReceived < depositAmount) {
                console.log("ATTACK NOT PROFITABLE");
            } else {
                console.log("*****ATTACK PROFITABLE*****");
            }
            assertLt(totalReceived, depositAmount);
        } else {
            doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);
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

/// Attacker max invests when stETH/ETH oracle and dex price = $1
/// Oracle remains at 1, dex price drops to 0.995
/// Attacker exits all (needs multiple rebalances to do this)
///
/// RESULT: Attacker loses funds, vault share price increases.
contract OrigamiLovStEthIntegrationTest_PriceDeviationAttacks_B is OrigamiLovStEthIntegrationTest_PriceDeviationAttacksBase {
    uint256 public constant SWAP_SLIPPAGE = 30; // 0.3%
    uint256 public constant AL_SLIPPAGE = 10; // 0.1%

    function run(bool withAttack, uint256 dexPrice) internal {
        bootstrap();
        doRebalance(1.113e18, SWAP_SLIPPAGE, AL_SLIPPAGE, 1e18);
        logLovTokenMetrics();

        if (withAttack) {
            console.log("------------------ATTACK---------------------");
            (,int256 answer,,,) = externalContracts.clStEthToEthOracle.latestRoundData();
            console.log(
                "\tstETH/ETH spot price:", 
                uint256(answer)
            );

            // Attacker max invests
            address attacker = makeAddr("attacker");
            uint256 depositAmount = lovTokenContracts.lovStEth.maxInvest(address(externalContracts.wstEthToken));
            console.log("\tattacker invested [wstETH]:", depositAmount);
            uint256 attackerBalance = investLovStEth(attacker, depositAmount);
            console.log("\tattacker balance [lovStEth]:", attackerBalance);

            console.log("\tstETH/ETH dex price:", dexPrice);

            // Vault rebalances back down, now with a pegged stETH/ETH rate
            doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);

            // Can't exit entire position in one go, because of the A/L caps
            uint256 totalExited;
            uint256 totalReceived;
            while (totalExited < attackerBalance) {
                uint256 remainingToExit = attackerBalance - totalExited;
                uint256 maxExitAmount = lovTokenContracts.lovStEth.maxExit(address(externalContracts.wstEthToken));
                uint256 receivedAmount = exitLovStEth(attacker, maxExitAmount > remainingToExit ? remainingToExit : maxExitAmount, attacker);
                console.log("\tattacker received [wstETH]:", receivedAmount);

                totalExited += maxExitAmount;
                totalReceived += receivedAmount;

                // Vault rebalances up again, attacker can now exit the remaining position
                doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
            }

            console.log("\tAttacker Total Received [wstETH]:", totalReceived);
            if (totalReceived < depositAmount) {
                console.log("ATTACK NOT PROFITABLE");
            } else {
                console.log("*****ATTACK PROFITABLE*****");
            }
            assertLt(totalReceived, depositAmount);
        } else {
            doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
        }

        console.log("-----------------------------------------------");
        logLovTokenMetrics();
    }

    function test_PriceDeviationAttacks_b_down_noAttack() public {
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

/// Attacker max invests when stETH/ETH oracle and dex price = $1
/// Oracle remains at 1, dex price drops to 0.995
/// Attacker exits all (needs multiple rebalances to do this)
///
/// RESULT: Attacker loses funds, vault share price increases.
contract OrigamiLovStEthIntegrationTest_PriceDeviationAttacks_C is OrigamiLovStEthIntegrationTest_PriceDeviationAttacksBase {
    uint256 public constant SWAP_SLIPPAGE = 30; // 0.3%
    uint256 public constant AL_SLIPPAGE = 10; // 0.1%

    function run(bool withAttack) internal {
        bootstrap();

        // Set both the oracle and the dex price to be 0.995
        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(921, 0.995e18, 1708008239, 1708008239, 921)
        );
        uint256 dexPrice = 0.995e18;

        // Rebalance to a very low A/L, simulating users existing. This means
        // there's a larger amount which is free, which allows the attacker to 
        // deposit a larger amount
        doRebalance(1.113e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
        logLovTokenMetrics();

        // dexPrice movs up 0.48%, chainlink price is still 0.995e18;
        dexPrice = 0.999975e18;

        if (withAttack) {
            console.log("------------------ATTACK---------------------");
            (,int256 answer,,,) = externalContracts.clStEthToEthOracle.latestRoundData();
            console.log(
                "\tstETH/ETH spot price:", 
                uint256(answer)
            );

            // Attacker max invests
            address attacker = makeAddr("attacker");
            uint256 depositAmount = lovTokenContracts.lovStEth.maxInvest(address(externalContracts.wstEthToken));
            console.log("\tattacker invested [wstETH]:", depositAmount);
            uint256 attackerBalance = investLovStEth(attacker, depositAmount);
            console.log("\tattacker balance [lovStEth]:", attackerBalance);

            console.log("\tstETH/ETH dex price:", dexPrice);

            // dexPrice drops back to 0.995
            // Vault rebalances back down
            dexPrice = 0.995e18;
            doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);

            // Can't exit entire position in one go, because of the A/L caps
            uint256 totalExited;
            uint256 totalReceived;
            while (totalExited < attackerBalance) {
                uint256 remainingToExit = attackerBalance - totalExited;
                uint256 maxExitAmount = lovTokenContracts.lovStEth.maxExit(address(externalContracts.wstEthToken));
                uint256 receivedAmount = exitLovStEth(attacker, maxExitAmount > remainingToExit ? remainingToExit : maxExitAmount, attacker);
                console.log("\tattacker received [wstETH]:", receivedAmount);

                totalExited += maxExitAmount;
                totalReceived += receivedAmount;

                // Vault rebalances up again, attacker can now exit the remaining position
                doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
            }

            console.log("\tAttacker Total Received [wstETH]:", totalReceived);
            if (totalReceived < depositAmount) {
                console.log("ATTACK NOT PROFITABLE");
            } else {
                console.log("*****ATTACK PROFITABLE*****");
            }
            assertLt(totalReceived, depositAmount);
        } else {
            doRebalance(1.125e18, SWAP_SLIPPAGE, AL_SLIPPAGE, dexPrice);
        }

        console.log("-----------------------------------------------");
        logLovTokenMetrics();
    }

    function test_PriceDeviationAttacks_c_noAttack() public {
        run(false);
    }

    function test_PriceDeviationAttacks_c_withAttack() public {
        run(true);  
    }
}