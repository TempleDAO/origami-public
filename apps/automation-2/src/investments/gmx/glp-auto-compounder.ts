
import { 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,   
    IOrigamiInvestment, IOrigamiInvestment__factory,
    DummyDex, DummyDex__factory, RepricingToken, RepricingToken__factory,
} from "@/typechain";
import { zeroExQuote, ZeroExQuoteParams } from './zero-ex'
import { bpsToFraction } from "@/common/utils";
import { BigNumber, ethers} from "ethers";
import { encodeGlpHarvestParams, formatBigNumber, matchAndDecodeEvent, txReceiptMarkdown, wasHarvestedRecently } from "./utils";
import { TaskContext } from "@mountainpath9/overlord";
import { Provider } from "@ethersproject/providers";
import { DiscordMesage, connectDiscord, urlEmbed } from "@/common/discord";

export const TRANSACTION_NAME = 'glp-auto-compounder';

export interface HarvestGlpConfig  {
    CHAIN_ID: number,
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
    ctx: TaskContext,
    config: HarvestGlpConfig,
    sellAmount: BigNumber,
) {
    ctx.logger.info(`MUMBAI: Selling [${sellAmount.toString()}] GMX for wETH`);

    const signer = await ctx.getSigner(config.CHAIN_ID);

    const dummyDex: DummyDex = DummyDex__factory.connect(config.ZERO_EX_PROXY_ADDRESS, signer);

    const buyWethAmount = sellAmount
        .mul(await dummyDex.gmxPrice())
        .div(await dummyDex.wrappedNativePrice());
    ctx.logger.info(`\tExpected wETH Amount Bought: [${buyWethAmount.toString()}]`);

    const minWethExpected = buyWethAmount.mul(10_000-config.GMX_TO_WETH_SLIPPAGE_BPS).div(10_000);
    ctx.logger.info(`\tMin wETH Amount Bought: [${minWethExpected.toString()}]`);
    const gmxToWethQuoteData = dummyDex.interface.encodeFunctionData("swapToWrappedNative", [sellAmount]);

    return {quoteData: gmxToWethQuoteData, minAmountExpected: minWethExpected};
}

async function arbitrumGmxToWethQuote(
    ctx: TaskContext,
    config: HarvestGlpConfig, 
    wethAddress: string, 
    sellAmount: BigNumber,
) {
    ctx.logger.info(`ARBITRUM: Selling [${sellAmount.toString()}] GMX for wETH`);
    const quoteParams: ZeroExQuoteParams = {
        sellToken: config.GMX_ADDRESS,
        buyToken: wethAddress,
        sellAmount: sellAmount.toString(),
        priceImpactProtectionPercentage: bpsToFraction(config.GMX_TO_WETH_PRICE_IMPACT_BPS), 
        slippagePercentage: bpsToFraction(config.GMX_TO_WETH_SLIPPAGE_BPS),
        enableSlippageProtection: true,
    };

    const quoteResp = await zeroExQuote(ctx.logger, config.CHAIN_ID, quoteParams);

    // eg "buyAmount": "2966807432720365600"
    const buyAmount = BigNumber.from(quoteResp.buyAmount);
    ctx.logger.info(`Expected wETH Amount Bought: [${buyAmount.toString()}]`);

    // eg "guaranteedPrice": "0.029371393583931619",
    const guaranteedPrice = ethers.utils.parseEther(quoteResp.guaranteedPrice);

    // minAmountExpected = sellAmount * guaranteedPrice
    const minAmountExpected = sellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    ctx.logger.info(`Min wETH Amount Bought: [${minAmountExpected.toString()}]`);

    return {quoteData: quoteResp.data, minAmountExpected};
}

export async function harvestGlpRewards(
    ctx: TaskContext,
    config: HarvestGlpConfig,
): Promise<void> {
    const startUnixMilliSecs = (new Date()).getTime();

    const signer = await ctx.getSigner(config.CHAIN_ID);

    const rewardAggregator: OrigamiGmxRewardsAggregator = OrigamiGmxRewardsAggregator__factory.connect(
        config.GLP_REWARD_AGGREGATOR_ADDRESS,
        signer
    );
    const oGmx: IOrigamiInvestment = IOrigamiInvestment__factory.connect(
        config.OGMX_ADDRESS,
        signer
    );
    const oGlp: IOrigamiInvestment = IOrigamiInvestment__factory.connect(
        config.OGLP_ADDRESS,
        signer
    );
    const oGlpRp: RepricingToken = RepricingToken__factory.connect(
        config.OGLP_ADDRESS, 
        signer
    );

    if (await wasHarvestedRecently(ctx.logger, config.MIN_HARVEST_INTERVAL_SECS, rewardAggregator)) {
        return;
    }

    const wethAddress = await rewardAggregator.wrappedNativeToken();
    const _harvestableRewards = await rewardAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    ctx.logger.info(`\tGLP Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);

    // Get a quote to swap $oGMX rewards -> $GMX
    // NB: No slippage when exiting the oGMX position as it's redeemed in situ (not sold via a dex)
    const oGmxToGmxExitQuote = await oGmx.exitQuote(harvestableRewards.oGmx, config.GMX_ADDRESS, 0, 0);
    ctx.logger.info(`oGMX -> GMX Exit Quote: ${oGmxToGmxExitQuote}`);

    // Get a quote to swap $GMX -> $WETH
    const {quoteData: gmxToWethQuoteData, minAmountExpected: minWethExpected} = config.CHAIN_ID === 42161
        ? await arbitrumGmxToWethQuote(
            ctx,
            config, 
            wethAddress,
            oGmxToGmxExitQuote.quoteData.minToTokenAmount
        )
        : await mumbaiGmxToWethQuote(
            ctx,
            config, 
            oGmxToGmxExitQuote.quoteData.minToTokenAmount
        );

    // The total $WETH we have to sell = 
    //   1/ The expected amount of $WETH we will receive from selling the $GMX +
    //   2/ The harvested $WETH
    const wethToInvestInOGlp = minWethExpected.add(harvestableRewards.weth);
    ctx.logger.info(`wethToInvestInOGlp=[${wethToInvestInOGlp.toString()}]`);

    // Get a quote to swap $WETH -> $oGLP
    // There may be slippage on the expected output, as the underlying GLP purchase is executed via GMX.io
    const wethToOglpInvestQuote = await oGlp.investQuote(wethToInvestInOGlp, wethAddress, config.WETH_TO_OGLP_INVESTMENT_SLIPPAGE_BPS, 0);
    ctx.logger.info(`WETH -> oGLP Invest Quote: ${wethToOglpInvestQuote}`);

    // The total $oGLP expected in the aggregator = 
    //   1/ The min expected amount after the oGMX->GMX->wETH->oGLP swaps
    //   2/ The amount of oGlp already existing in the aggregator - given by the harvestableRewards()
    const totalOGlpAvailable = wethToOglpInvestQuote.quoteData.minInvestmentAmount.add(harvestableRewards.oGlp);
    ctx.logger.info(`totalOGlpAvailable=[${totalOGlpAvailable.toString()}]`);

    // To smooth the bump up out, we only add a percentage of the total available oGLP as reserves
    // each day.
    const addToReserveAmount = totalOGlpAvailable.mul(config.DAILY_ADD_TO_RESERVE_BPS).div(10_000);
    ctx.logger.info(`addToReserveAmount=[${addToReserveAmount}]`);

    const harvestParams: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct = {
        oGmxExitQuoteData: oGmxToGmxExitQuote.quoteData,
        gmxToNativeSwapData: gmxToWethQuoteData,
        oGlpInvestQuoteData: wethToOglpInvestQuote.quoteData,
        addToReserveAmountPct: config.DAILY_ADD_TO_RESERVE_BPS,
    };
    ctx.logger.info(`Harvest Params: ${JSON.stringify(harvestParams)}`);

    const submittedAt = new Date();
    const encodedParams = encodeGlpHarvestParams(rewardAggregator, harvestParams);
    ctx.logger.info(`harvestRewards encoded params: ${encodedParams}`);
    const tx = await rewardAggregator.harvestRewards(encodedParams);
    const txReceipt = await tx.wait();    

    // Grab the events
    const events: string[] = [];
    for(const ev of txReceipt?.events || []) {
        const addedEv = matchAndDecodeEvent(oGlpRp, oGlpRp.filters.PendingReservesAdded(), ev);
        if (addedEv) {
            events.push(`PendingReservesAdded(amount=${formatBigNumber(addedEv.amount, 18, 4)})`)
        }
    }

    // Send notification
    const message = await buildDiscordMessage(signer.provider!, submittedAt, txReceipt, events);
    const webhookUrl = await ctx.getSecret('discord_webhook_url');
    const discord = await connectDiscord(webhookUrl, ctx.logger);
    await discord.postMessage(message);
}

async function buildDiscordMessage(provider: Provider, submittedAt: Date, txReceipt: ethers.ContractReceipt, events: string[]): Promise<DiscordMesage> {

    const content = [
        `**Harvest GLP Rewards**`,
        ``,
        ...events.map(ev => `_event_: ${ev}`),
        ``,
        ...await txReceiptMarkdown(provider, submittedAt, txReceipt),
    ];

    return {
        content: content.join('\n'),
        embeds: [
            urlEmbed(`https://mumbai.polygonscan.com/tx/${txReceipt.transactionHash}`),
        ]
    }
}