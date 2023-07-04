
import {
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,
    IOrigamiInvestment, IOrigamiInvestment__factory,
    DummyDex, DummyDex__factory, RepricingToken, RepricingToken__factory, OrigamiGmxManager, OrigamiGmxManager__factory,
} from "@/typechain";
import { zeroExQuote, ZeroExQuoteParams } from './zero-ex'
import { bpsToFraction } from "@/common/utils";
import { BigNumber, ethers } from "ethers";
import {
    buildOrigamiTasksDiscordMessage,
    encodeGlpHarvestParams,
    formatBigNumber,
    matchAndDecodeEvent,
    OrigamiTaskDiscordEvent,
    OrigamiTaskDiscordMetadata,
    wasHarvestedRecently
} from "./utils";
import { TaskContext } from "@mountainpath9/overlord";
import { connectDiscord } from "@/common/discord";
import { Chain } from "@/chains";
import { DISCORD_WEBHOOK_URL_KEY } from "@/common/discord";

export const TRANSACTION_NAME = 'glp-auto-compounder';
const GLP_VAULT_TYPE = 0;

export interface HarvestGlpConfig {
    CHAIN: Chain,
    WALLET_NAME: string,
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

    // What threshold of secondary WETH rewards (from initial user deposits) 
    // should be available to harvest for it to be worth spending the gas.
    // In decimal format, eg specific `0.01` to mean 0.01 WETH
    SECONDARY_REWARDS_THRESHOLD: number,
}

async function mumbaiGmxToWethQuote(
    ctx: TaskContext,
    config: HarvestGlpConfig,
    sellAmount: BigNumber,
) {
    ctx.logger.info(`MUMBAI: Selling [${sellAmount.toString()}] GMX for wETH`);

    const provider = await ctx.getProvider(config.CHAIN.id);
    const signer = await ctx.getSigner(provider, config.WALLET_NAME);

    const dummyDex: DummyDex = DummyDex__factory.connect(config.ZERO_EX_PROXY_ADDRESS, signer);

    const buyWethAmount = sellAmount
        .mul(await dummyDex.gmxPrice())
        .div(await dummyDex.wrappedNativePrice());
    ctx.logger.info(`\tExpected wETH Amount Bought: [${buyWethAmount.toString()}]`);

    const minWethExpected = buyWethAmount.mul(10_000 - config.GMX_TO_WETH_SLIPPAGE_BPS).div(10_000);
    ctx.logger.info(`\tMin wETH Amount Bought: [${minWethExpected.toString()}]`);
    const gmxToWethQuoteData = dummyDex.interface.encodeFunctionData("swapToWrappedNative", [sellAmount]);

    return { quoteData: gmxToWethQuoteData, minAmountExpected: minWethExpected };
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

    const quoteResp = await zeroExQuote(ctx.logger, config.CHAIN.id, quoteParams);

    // eg "buyAmount": "2966807432720365600"
    const buyAmount = BigNumber.from(quoteResp.buyAmount);
    ctx.logger.info(`Expected wETH Amount Bought: [${buyAmount.toString()}]`);

    // eg "guaranteedPrice": "0.029371393583931619",
    const guaranteedPrice = ethers.utils.parseEther(quoteResp.guaranteedPrice);

    // minAmountExpected = sellAmount * guaranteedPrice
    const minAmountExpected = sellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    ctx.logger.info(`Min wETH Amount Bought: [${minAmountExpected.toString()}]`);

    return { quoteData: quoteResp.data, minAmountExpected };
}

/**
 * A workaround for oGmx reward compounding.
 * There are no more esGMX rewards now from GMX.io, so that means no more oGmx rewards from the GLP vault.
 * Unfortunately the aggregator contract doesn't handle the case where oGmx=0, it will revert.
 * So this assumes there is a small amount of oGMX in the contract (protocol funded), and will
 * exit a very small amount only.
 */
function calcOGmxToHarvest(harvestableOGmx: BigNumber) {
    const minOGmxRemaining = ethers.utils.parseEther("0.1");
    const oGmxDustToHarvest = ethers.utils.parseEther("0.00001"); // 10k harvests for this.
    if (harvestableOGmx.gt(minOGmxRemaining)) {
        // Leave the minimum amount in the aggregator for next time
        return harvestableOGmx.sub(minOGmxRemaining);
    } else {
        // Use the dust amount. The GLP_REWARD_AGGREGATOR_ADDRESS must have at least this balance.
        return oGmxDustToHarvest;
    }
}

/**
 * User deposits into oGLP first get added to the secondaryGmxEarnAccount, and then that position is migrated
 * daily into the primaryGmxEarnAccount.
 * In that (up to) 24hr period, rewards may have been earned which should be harvested ready for the compounding.
 */
async function harvestSecondaryWeth(
    ctx: TaskContext,
    config: HarvestGlpConfig,
    signer: ethers.Signer, 
    rewardAggregator: OrigamiGmxRewardsAggregator
) {
    const glpManager: OrigamiGmxManager = OrigamiGmxManager__factory.connect(
        await rewardAggregator.glpManager(),
        signer
    );
    
    const harvestableWeth = (await glpManager.harvestableSecondaryRewards(GLP_VAULT_TYPE))[0];
    ctx.logger.info(`harvestableSecondaryRewards (from transient GLP)=[${harvestableWeth.toString()}]`);
    
    if (harvestableWeth.gt(ethers.utils.parseEther(config.SECONDARY_REWARDS_THRESHOLD.toString()))) {
        ctx.logger.info(`harvestableSecondaryRewards greather than threshold of [${config.SECONDARY_REWARDS_THRESHOLD}]. Harvesting...`);
        const tx = await glpManager.harvestSecondaryRewards({
            gasLimit: 1_000_000,
        });
        const txReceipt = await tx.wait();
        const txUrl = config.CHAIN.transactionUrl(txReceipt.transactionHash);
        ctx.logger.info(`harvestSecondaryRewards txUrl: ${txUrl}`);
    }
}

export async function harvestGlpRewards(
    ctx: TaskContext,
    config: HarvestGlpConfig,
): Promise<void> {

    const provider = await ctx.getProvider(config.CHAIN.id);
    const signer = await ctx.getSigner(provider, config.WALLET_NAME);

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

    await harvestSecondaryWeth(ctx, config, signer, rewardAggregator);

    const wethAddress = await rewardAggregator.wrappedNativeToken();
    const _harvestableRewards = await rewardAggregator.harvestableRewards();
    const harvestableRewards = { weth: _harvestableRewards[0], oGmx: calcOGmxToHarvest(_harvestableRewards[1]), oGlp: _harvestableRewards[2] };
    ctx.logger.info(`\tGLP Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);

    // Get a quote to swap $oGMX rewards -> $GMX
    // NB: No slippage when exiting the oGMX position as it's redeemed in situ (not sold via a dex)
    const oGmxToGmxExitQuote = await oGmx.exitQuote(harvestableRewards.oGmx, config.GMX_ADDRESS, 0, 0);
    ctx.logger.info(`oGMX -> GMX Exit Quote: ${oGmxToGmxExitQuote}`);

    // Get a quote to swap $GMX -> $WETH
    const { quoteData: gmxToWethQuoteData, minAmountExpected: minWethExpected } = config.CHAIN.id === 42161
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
    const tx = await rewardAggregator.harvestRewards(encodedParams, {
        gasLimit: 4_000_000,
    });
    const txReceipt = await tx.wait();
    const txUrl = config.CHAIN.transactionUrl(txReceipt.transactionHash);

    // Grab the events
    const events: OrigamiTaskDiscordEvent[] = [];
    for (const ev of txReceipt?.events || []) {
        const addedEv = matchAndDecodeEvent(oGlpRp, oGlpRp.filters.PendingReservesAdded(), ev);
        if (addedEv) {
            events.push({
                what: "PendingReservesAdded",
                details: [`amount = \`${formatBigNumber(addedEv.amount, 18, 4)}\``]
            })
        }
    }
    const metadata: OrigamiTaskDiscordMetadata = {
        title: 'Harvest GLP Rewards',
        events,
        submittedAt,
        txReceipt,
        txUrl
    };

    // Send notification
    const message = await buildOrigamiTasksDiscordMessage(signer.provider!, config.CHAIN, metadata);
    const webhookUrl = await ctx.getSecret(DISCORD_WEBHOOK_URL_KEY);
    const discord = await connectDiscord(webhookUrl, ctx.logger);
    await discord.postMessage(message);
}
