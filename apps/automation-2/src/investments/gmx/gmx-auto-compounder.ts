
import { connectDiscord, DiscordMesage, urlEmbed } from "@/common/discord";
import { TaskContext } from "@mountainpath9/overlord";
import { bpsToFraction } from "@/common/utils";
import { zeroExQuote, ZeroExQuoteParams } from "./zero-ex";
import { 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,   
    IOrigamiInvestment, IOrigamiInvestment__factory,
    DummyDex, DummyDex__factory, IERC20, IERC20__factory, RepricingToken, RepricingToken__factory,
} from "@/typechain";
import { Provider } from "@ethersproject/providers";
import { BigNumber, ethers } from "ethers";
import { encodeGmxHarvestParams, formatBigNumber, matchAndDecodeEvent, txReceiptMarkdown, wasHarvestedRecently } from "./utils";


export const TRANSACTION_NAME = 'gmx-auto-compounder';

export interface HarvestGmxConfig  {
    CHAIN_ID: number,
    GMX_ADDRESS: string,
    OGMX_ADDRESS: string,
    GMX_REWARD_AGGREGATOR_ADDRESS: string,
    ZERO_EX_PROXY_ADDRESS: string,

    // The min frequency that the harvester can actually run
    MIN_HARVEST_INTERVAL_SECS: number,

    // max price impact when swapping $WETH -> $GMX via 0x
    WETH_TO_GMX_PRICE_IMPACT_BPS: number,

    // max slippage (not including price impact) when swapping $WETH -> $GMX via 0x
    WETH_TO_GMX_SLIPPAGE_BPS: number,

    // What percentage of the total oGMX on hand does the aggregator actually add as reserves into ovGMX
    DAILY_ADD_TO_RESERVE_BPS: number,
}


async function mumbaiWethToGmxQuote(
    ctx: TaskContext,
    config: HarvestGmxConfig,
    sellAmount: BigNumber,
) {
    ctx.logger.info(`MUMBAI: Selling [${sellAmount.toString()}] wETH for GMX`);

    const signer = await ctx.getSigner(config.CHAIN_ID);
    const dummyDex: DummyDex = DummyDex__factory.connect(
        config.ZERO_EX_PROXY_ADDRESS,
        signer,
    );

    const buyGmxAmount = sellAmount
        .mul(await dummyDex.wrappedNativePrice())
        .div(await dummyDex.gmxPrice());
    ctx.logger.info(`\tExpected GMX Amount Bought: [${buyGmxAmount.toString()}]`);

    const minGmxExpected = buyGmxAmount.mul(10_000-config.WETH_TO_GMX_SLIPPAGE_BPS).div(10_000);
    ctx.logger.info(`\tMin GMX Amount Bought: [${minGmxExpected.toString()}]`);
    const wethToGmxQuoteData = dummyDex.interface.encodeFunctionData("swapToGMX", [sellAmount]);

    return {quoteData: wethToGmxQuoteData, minAmountExpected: minGmxExpected};
}

async function arbitrumWethToGmxQuote(
    ctx: TaskContext,
    config: HarvestGmxConfig, 
    wethAddress: string, 
    sellAmount: BigNumber
) {
    ctx.logger.info(`ARBITRUM: Selling [${sellAmount.toString()}] wETH for GMX`);
    const quoteParams: ZeroExQuoteParams = {
        sellToken: wethAddress,
        buyToken: config.GMX_ADDRESS,
        sellAmount: sellAmount.toString(),
        priceImpactProtectionPercentage: bpsToFraction(config.WETH_TO_GMX_PRICE_IMPACT_BPS), 
        slippagePercentage: bpsToFraction(config.WETH_TO_GMX_SLIPPAGE_BPS),
        enableSlippageProtection: true,
    };

    const quoteResp = await zeroExQuote(ctx.logger, config.CHAIN_ID, quoteParams);

    // eg "buyAmount": "336056751580968879966"
    const buyAmount = BigNumber.from(quoteResp.buyAmount);
    ctx.logger.info(`Expected GMX Amount Bought: [${buyAmount.toString()}]`);

    // eg "guaranteedPrice": "33.269618406515919116",
    const guaranteedPrice = ethers.utils.parseEther(quoteResp.guaranteedPrice);

    // minAmountExpected = sellAmount * guaranteedPrice
    const minAmountExpected = sellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    ctx.logger.info(`Min GMX Amount Bought: [${minAmountExpected.toString()}]`);

    return {quoteData: quoteResp.data, minAmountExpected};
}

export async function harvestGmxRewards(
    ctx: TaskContext,
    config: HarvestGmxConfig,
): Promise<void> {
    const startUnixMilliSecs = (new Date()).getTime();

    const signer = await ctx.getSigner(config.CHAIN_ID);

    const rewardAggregator: OrigamiGmxRewardsAggregator = OrigamiGmxRewardsAggregator__factory.connect(
        config.GMX_REWARD_AGGREGATOR_ADDRESS,
        signer
    );
    const oGmx: IOrigamiInvestment = IOrigamiInvestment__factory.connect(
        config.OGMX_ADDRESS,
        signer
    );
    const oGmxRp: RepricingToken = RepricingToken__factory.connect(
        config.OGMX_ADDRESS, 
        signer
    );
    const gmx: IERC20 = IERC20__factory.connect(
        config.GMX_ADDRESS,
        signer
    );

    if (await wasHarvestedRecently(ctx.logger, config.MIN_HARVEST_INTERVAL_SECS, rewardAggregator)) {
        return;
    }

    const wethAddress = await rewardAggregator.wrappedNativeToken();
    const _harvestableRewards = await rewardAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    ctx.logger.info(`\tGMX Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);
    const existingGmx = await gmx.balanceOf(rewardAggregator.address);
    ctx.logger.info(`\tExisting GMX in aggregator: ${existingGmx.toString()}`);

    // Get a quote to swap $WETH -> $GMX
    const {quoteData: wethToGmxQuoteData, minAmountExpected: minGmxExpected} = config.CHAIN_ID === 42161
        ? await arbitrumWethToGmxQuote(
            ctx,
            config, 
            wethAddress,
            harvestableRewards.weth,
        )
        : await mumbaiWethToGmxQuote(
            ctx,
            config, 
            harvestableRewards.weth,
        );
        
    // The total $GMX we have to invest = 
    //   1/ The expected amount of $GMX we will receive from selling the $WETH +
    //   2/ Any existing balance from previous swaps left over amounts
    const gmxToInvestInOGmx = minGmxExpected.add(existingGmx);
    ctx.logger.info(`gmxToInvestInOGmx=[${gmxToInvestInOGmx.toString()}]`);

    // Get a quote to swap $GMX -> $oGMX
    // NB: No slippage when investing in the oGMX position as it's minted in situ (not bought via a dex)
    const gmxToOgmxInvestQuote = await oGmx.investQuote(gmxToInvestInOGmx, config.GMX_ADDRESS, 0, 0);
    ctx.logger.info(`GMX -> oGMX Invest Quote: ${gmxToOgmxInvestQuote}`);

    // The total $oGMX expected in the aggregator = 
    //   1/ The min expected amount after the wETH->GMX->oGMX swaps
    //   2/ The amount of oGMX already existing + harvested in the aggregator - given by the harvestableRewards()
    const totalOGmxAvailable = gmxToOgmxInvestQuote.quoteData.minInvestmentAmount.add(harvestableRewards.oGmx);
    ctx.logger.info(`totalOGmxAvailable=[${totalOGmxAvailable.toString()}]`);

    const harvestParams: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct = {
        nativeToGmxSwapData: wethToGmxQuoteData,
        oGmxInvestQuoteData: gmxToOgmxInvestQuote.quoteData,
        addToReserveAmountPct: config.DAILY_ADD_TO_RESERVE_BPS,
    };
    ctx.logger.info(`Harvest Params: ${JSON.stringify(harvestParams)}`);

    const submittedAt = new Date();
    const encodedParams = encodeGmxHarvestParams(rewardAggregator, harvestParams);
    ctx.logger.info(`harvestRewards encoded params: ${encodedParams}`);
    const tx = await rewardAggregator.harvestRewards(encodedParams);
    const txReceipt = await tx.wait();

    // Grab the events
    const events: string[] = [];
    for(const ev of txReceipt?.events || []) {
        const addedEv = matchAndDecodeEvent(oGmxRp, oGmxRp.filters.PendingReservesAdded(), ev);
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
        `**Harvest GMX Rewards**`,
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
