
import { AutotaskResult, createdTransaction, noop, timeout } from "@/autotask-result";
import { CommonConfig } from "@/config";
import { AutotaskConnection } from "@/connect";
import { 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,   
    IOrigamiInvestment, IOrigamiInvestment__factory,
    DummyDex, DummyDex__factory,
} from "@/typechain";
import { zeroExQuote, ZeroExQuoteParams } from '@/common/zero-ex'
import { sendTransaction } from '@/ethers';
import { bpsToFraction, waitForLastTransactionToFinish } from "@/utils";
import { BigNumber, ethers} from "ethers";
import { encodeGlpHarvestParams, wasHarvestedRecently } from "../gmx-utils";

export const TRANSACTION_NAME = 'glp-auto-compounder';

export interface HarvestGlpConfig  {
    GMX_ADDRESS: string,
    OGMX_ADDRESS: string,
    OGLP_ADDRESS: string,
    GLP_REWARD_AGGREGATOR_ADDRESS: string,
    ZERO_EX_PROXY_ADDRESS: string,

    // The min frequency that the harvester can actually run
    MIN_HARVEST_INTERVAL_SECS: number,

    // max price impact when swapping $GMX -> $WETH via 0x
    GMX_TO_WETH_PRICE_IMPACT_BPS: number,

    // max slippage (not including price impact) when swapping $GMX -> $WETH via 0x
    GMX_TO_WETH_SLIPPAGE_BPS: number,

    // max slippage when investing in $oGLP with $WETH
    WETH_TO_OGLP_INVESTMENT_SLIPPAGE_BPS: number,

    // What percentage of the total oGLP on hand does the aggregator actually add as reserves into ovGLP
    DAILY_ADD_TO_RESERVE_BPS: number,
}

async function mumbaiGmxToWethQuote(
    connection: AutotaskConnection,
    config: HarvestGlpConfig,
    sellAmount: BigNumber,
) {
    console.log(`MUMBAI: Selling [${sellAmount.toString()}] GMX for wETH`);

    const dummyDex: DummyDex = DummyDex__factory.connect(
        config.ZERO_EX_PROXY_ADDRESS,
        connection.signer
    );

    const buyWethAmount = sellAmount
        .mul(await dummyDex.gmxPrice())
        .div(await dummyDex.wrappedNativePrice());
    console.log(`\tExpected wETH Amount Bought: [${buyWethAmount.toString()}]`);

    const minWethExpected = buyWethAmount.mul(10_000-config.GMX_TO_WETH_SLIPPAGE_BPS).div(10_000);
    console.log(`\tMin wETH Amount Bought: [${minWethExpected.toString()}]`);
    const gmxToWethQuoteData = dummyDex.interface.encodeFunctionData("swapToWrappedNative", [sellAmount]);

    return {quoteData: gmxToWethQuoteData, minAmountExpected: minWethExpected};
}

async function arbitrumGmxToWethQuote(
    commonConfig: CommonConfig, 
    config: HarvestGlpConfig, 
    wethAddress: string, 
    sellAmount: BigNumber,
) {
    console.log(`ARBITRUM: Selling [${sellAmount.toString()}] GMX for wETH`);
    const quoteParams: ZeroExQuoteParams = {
        sellToken: config.GMX_ADDRESS,
        buyToken: wethAddress,
        sellAmount: sellAmount.toString(),
        priceImpactProtectionPercentage: bpsToFraction(config.GMX_TO_WETH_PRICE_IMPACT_BPS), 
        slippagePercentage: bpsToFraction(config.GMX_TO_WETH_SLIPPAGE_BPS),
        enableSlippageProtection: true,
    };

    const quoteResp = await zeroExQuote(commonConfig.NETWORK, quoteParams);

    // eg "buyAmount": "2966807432720365600"
    const buyAmount = BigNumber.from(quoteResp.buyAmount);
    console.log(`Expected wETH Amount Bought: [${buyAmount.toString()}]`);

    // eg "guaranteedPrice": "0.029371393583931619",
    const guaranteedPrice = ethers.utils.parseEther(quoteResp.guaranteedPrice);

    // minAmountExpected = sellAmount * guaranteedPrice
    const minAmountExpected = sellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    console.log(`Min wETH Amount Bought: [${minAmountExpected.toString()}]`);

    return {quoteData: quoteResp.data, minAmountExpected};
}

export async function harvestGlpRewards(
    connection: AutotaskConnection,
    commonConfig: CommonConfig,
    config: HarvestGlpConfig,
): Promise<AutotaskResult> {
    const startUnixMilliSecs = (new Date()).getTime();

    // Wait for any in flight transactions to complete first.
    if (!await waitForLastTransactionToFinish(connection, commonConfig, startUnixMilliSecs)) {
        return timeout('previous transaction still pending');
    }

    const rewardAggregator: OrigamiGmxRewardsAggregator = OrigamiGmxRewardsAggregator__factory.connect(
        config.GLP_REWARD_AGGREGATOR_ADDRESS,
        connection.signer
    );
    const oGmx: IOrigamiInvestment = IOrigamiInvestment__factory.connect(
        config.OGMX_ADDRESS,
        connection.signer
    );
    const oGlp: IOrigamiInvestment = IOrigamiInvestment__factory.connect(
        config.OGLP_ADDRESS,
        connection.signer
    );

    if (await wasHarvestedRecently(connection, config.MIN_HARVEST_INTERVAL_SECS, rewardAggregator)) {
        return noop();
    }

    const wethAddress = await rewardAggregator.wrappedNativeToken();
    const _harvestableRewards = await rewardAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    console.log(`\tGLP Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);

    // Get a quote to swap $oGMX rewards -> $GMX
    // NB: No slippage when exiting the oGMX position as it's redeemed in situ (not sold via a dex)
    const oGmxToGmxExitQuote = await oGmx.exitQuote(harvestableRewards.oGmx, config.GMX_ADDRESS, 0, 0);
    console.log(`oGMX -> GMX Exit Quote: ${oGmxToGmxExitQuote}`);

    // Get a quote to swap $GMX -> $WETH
    const {quoteData: gmxToWethQuoteData, minAmountExpected: minWethExpected} = commonConfig.NETWORK === 'arbitrum'
        ? await arbitrumGmxToWethQuote(
            commonConfig, 
            config, 
            wethAddress,
            oGmxToGmxExitQuote.quoteData.minToTokenAmount
        )
        : await mumbaiGmxToWethQuote(
            connection,
            config, 
            oGmxToGmxExitQuote.quoteData.minToTokenAmount
        );

    // The total $WETH we have to sell = 
    //   1/ The expected amount of $WETH we will receive from selling the $GMX +
    //   2/ The harvested $WETH
    const wethToInvestInOGlp = minWethExpected.add(harvestableRewards.weth);
    console.log(`wethToInvestInOGlp=[${wethToInvestInOGlp.toString()}]`);

    // Get a quote to swap $WETH -> $oGLP
    // There may be slippage on the expected output, as the underlying GLP purchase is executed via GMX.io
    const wethToOglpInvestQuote = await oGlp.investQuote(wethToInvestInOGlp, wethAddress, config.WETH_TO_OGLP_INVESTMENT_SLIPPAGE_BPS, 0);
    console.log(`WETH -> oGLP Invest Quote: ${wethToOglpInvestQuote}`);

    // The total $oGLP expected in the aggregator = 
    //   1/ The min expected amount after the oGMX->GMX->wETH->oGLP swaps
    //   2/ The amount of oGlp already existing in the aggregator - given by the harvestableRewards()
    const totalOGlpAvailable = wethToOglpInvestQuote.quoteData.minInvestmentAmount.add(harvestableRewards.oGlp);
    console.log(`totalOGlpAvailable=[${totalOGlpAvailable.toString()}]`);

    // To smooth the bump up out, we only add a percentage of the total available oGLP as reserves
    // each day.
    const addToReserveAmount = totalOGlpAvailable.mul(config.DAILY_ADD_TO_RESERVE_BPS).div(10_000);
    console.log(`addToReserveAmount=[${addToReserveAmount}]`);

    const harvestParams: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct = {
        oGmxExitQuoteData: oGmxToGmxExitQuote.quoteData,
        gmxToNativeSwapData: gmxToWethQuoteData,
        oGlpInvestQuoteData: wethToOglpInvestQuote.quoteData,
        addToReserveAmount: addToReserveAmount,
    };
    console.log("Harvest Params:", harvestParams);

    const encodedParams = encodeGlpHarvestParams(harvestParams);
    console.log("harvestRewards encoded params:", encodedParams);
    const populatedTx = await rewardAggregator.populateTransaction['harvestRewards'](encodedParams);
    const tx = await sendTransaction(connection, commonConfig, populatedTx);
    console.log(`Waiting on transaction: ${tx.hash}`);
    return createdTransaction(tx.hash);
}
