pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { TimestampStore } from "test/foundry/invariant/stores/TimestampStore.sol";
import { StateStore } from "test/foundry/invariant/stores/StateStore.sol";
import { BaseHandler } from "test/foundry/invariant/handlers/BaseHandler.sol";

import { ExternalContracts, OUsdcContracts, LovTokenContracts } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestDeployer.t.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { OrigamiLovTokenTestConstants as Constants } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestConstants.t.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/// @notice Invariant Handler ovUSDC
contract OvUsdcHandler is BaseHandler {
    using OrigamiMath for uint256;

    ExternalContracts public externalContracts;
    OUsdcContracts public oUsdcContracts;
    LovTokenContracts public lovTokenContracts;

    uint256 public totalUsdcDeposits;
    uint256 public totalUsdcExits;

    constructor(
        TimestampStore timestampStore_,
        StateStore stateStore_,
        ExternalContracts memory _externalContracts,
        OUsdcContracts memory _oUsdcContracts,
        LovTokenContracts memory _lovTokenContracts
    )
        BaseHandler(timestampStore_, stateStore_)
    {
        externalContracts = _externalContracts;
        oUsdcContracts = _oUsdcContracts;
        lovTokenContracts = _lovTokenContracts;
    }

    function investOvUsdc_usdc(
        uint256 amount, 
        uint256 timeJumpSeed
    ) external 
        instrument
        adjustTimestamp(timeJumpSeed) 
        useSender
    returns (uint256 amountOut) {
        // Debt token is capped to uint128 (18 dps)
        // So for a USDC deposit, it needs to be bound to max uint128, divided by 1e12 since it's scaled up
        // So use max uint18 as an approximation
        amount = _bound(amount, 1, type(uint80).max);

        totalUsdcDeposits += amount;

        doMint(externalContracts.usdcToken, msg.sender, amount);
        externalContracts.usdcToken.approve(address(oUsdcContracts.ovUsdc), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = oUsdcContracts.ovUsdc.investQuote(
            amount,
            address(externalContracts.usdcToken),
            0,
            0
        );

        amountOut = oUsdcContracts.ovUsdc.investWithToken(quoteData);

        assertEq(amountOut, amount * 1e12, "Invariant violation: investOvUsdc(usdc) unexpected amountOut");
        assertEq(oUsdcContracts.ovUsdc.totalSupply(), oUsdcContracts.ovUsdc.totalReserves(), "Invariant violation: investOvUsdc(usdc) totalSupply != totalReserves");
    }

    function getMaxAvailalbleToExit() internal view returns (uint256 maxAvailableToExit) {
        // Min amount of user balance and the remaining circuit breaker capacity
        uint256 maxActorAmount = min(
            oUsdcContracts.ovUsdc.balanceOf(msg.sender),
            oUsdcContracts.cbOUsdcExit.available()
        );
        if (maxActorAmount == 0) return 0;

        // Amount of USDC free to remove from the lendingClerk
        uint256 usdcAvailable = oUsdcContracts.lendingClerk.totalAvailableToWithdraw();
        if (usdcAvailable == 0) return 0;

        // Convert the free USDC to ovUSDC assuming no slippage
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oUsdcContracts.ovUsdc.investQuote(
            usdcAvailable,
            address(externalContracts.usdcToken),
            0,
            0
        );

        // Use the min of the user balance, circuit breaker capacity, free USDC->ovUSDC 
        maxAvailableToExit = maxActorAmount < quoteData.expectedInvestmentAmount 
            ? maxActorAmount 
            : quoteData.expectedInvestmentAmount;
    }

    function exitOvUsdc_usdc(
        uint256 amount, 
        uint256 timeJumpSeed
    ) external 
        instrument
        adjustTimestamp(timeJumpSeed) 
        useSender
    returns (uint256 amountOut) {
        uint256 maxAvailableToExit = getMaxAvailalbleToExit();

        amount = _bound(amount, 0, maxAvailableToExit);
        if (amount == 0) {
            stateStore.setFinishedEarly();
            return 0;
        }

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oUsdcContracts.ovUsdc.exitQuote(
            amount,
            address(externalContracts.usdcToken),
            0,
            0
        );

        amountOut = oUsdcContracts.ovUsdc.exitToToken(quoteData, msg.sender);

        totalUsdcExits += amountOut;

        uint256 expectedAmountOut = amount
            .subtractBps(Constants.OUSDC_EXIT_FEE_BPS, OrigamiMath.Rounding.ROUND_DOWN)
            .scaleDown(1e12, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(amountOut, expectedAmountOut, "Invariant violation: exitOvUsdc(usdc) unexpected amountOut");
        assertEq(oUsdcContracts.ovUsdc.totalSupply(), oUsdcContracts.ovUsdc.totalReserves(), "Invariant violation: exitOvUsdc(usdc) totalSupply != totalReserves");
    }
}
