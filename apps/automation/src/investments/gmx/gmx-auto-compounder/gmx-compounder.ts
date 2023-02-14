
import { AutotaskResult, createdTransaction, noop, timeout } from "@/autotask-result";
import { CommonConfig } from "@/config";
import { AutotaskConnection } from "@/connect";
import { 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,   
    IOrigamiInvestment, IOrigamiInvestment__factory,
    DummyDex, DummyDex__factory, IERC20, IERC20__factory,
} from "@/typechain";
import { zeroExQuote, ZeroExQuoteParams } from '@/common/zero-ex'
import { sendTransaction } from '@/ethers';
import { bpsToFraction, waitForLastTransactionToFinish } from "@/utils";
import { BigNumber, ethers} from "ethers";
import { encodeGmxHarvestParams, wasHarvestedRecently } from "../gmx-utils";

export const TRANSACTION_NAME = 'gmx-auto-compounder';

export interface HarvestGmxConfig  {
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
    connection: AutotaskConnection,
    config: HarvestGmxConfig,
    sellAmount: BigNumber,
) {
    console.log(`MUMBAI: Selling [${sellAmount.toString()}] wETH for GMX`);

    const dummyDex: DummyDex = DummyDex__factory.connect(
        config.ZERO_EX_PROXY_ADDRESS,
        connection.signer
    );

    const buyGmxAmount = sellAmount
        .mul(await dummyDex.wrappedNativePrice())
        .div(await dummyDex.gmxPrice());
    console.log(`\tExpected GMX Amount Bought: [${buyGmxAmount.toString()}]`);

    const minGmxExpected = buyGmxAmount.mul(10_000-config.WETH_TO_GMX_SLIPPAGE_BPS).div(10_000);
    console.log(`\tMin GMX Amount Bought: [${minGmxExpected.toString()}]`);
    const wethToGmxQuoteData = dummyDex.interface.encodeFunctionData("swapToGMX", [sellAmount]);

    return {quoteData: wethToGmxQuoteData, minAmountExpected: minGmxExpected};
}

async function arbitrumWethToGmxQuote(
    commonConfig: CommonConfig, 
    config: HarvestGmxConfig, 
    wethAddress: string, 
    sellAmount: BigNumber
) {
    console.log(`ARBITRUM: Selling [${sellAmount.toString()}] wETH for GMX`);
    const quoteParams: ZeroExQuoteParams = {
        sellToken: wethAddress,
        buyToken: config.GMX_ADDRESS,
        sellAmount: sellAmount.toString(),
        priceImpactProtectionPercentage: bpsToFraction(config.WETH_TO_GMX_PRICE_IMPACT_BPS), 
        slippagePercentage: bpsToFraction(config.WETH_TO_GMX_SLIPPAGE_BPS),
        enableSlippageProtection: true,
    };

    const quoteResp = await zeroExQuote(commonConfig.NETWORK, quoteParams);

    // eg "buyAmount": "336056751580968879966"
    const buyAmount = BigNumber.from(quoteResp.buyAmount);
    console.log(`Expected GMX Amount Bought: [${buyAmount.toString()}]`);

    // eg "guaranteedPrice": "33.269618406515919116",
    const guaranteedPrice = ethers.utils.parseEther(quoteResp.guaranteedPrice);

    // minAmountExpected = sellAmount * guaranteedPrice
    const minAmountExpected = sellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    console.log(`Min GMX Amount Bought: [${minAmountExpected.toString()}]`);

    return {quoteData: quoteResp.data, minAmountExpected};
}

export async function harvestGmxRewards(
    connection: AutotaskConnection,
    commonConfig: CommonConfig,
    config: HarvestGmxConfig,
): Promise<AutotaskResult> {
    const startUnixMilliSecs = (new Date()).getTime();

    // Wait for any in flight transactions to complete first.
    if (!await waitForLastTransactionToFinish(connection, commonConfig, startUnixMilliSecs)) {
        return timeout('previous transaction still pending');
    }

    const rewardAggregator: OrigamiGmxRewardsAggregator = OrigamiGmxRewardsAggregator__factory.connect(
        config.GMX_REWARD_AGGREGATOR_ADDRESS,
        connection.signer
    );
    const oGmx: IOrigamiInvestment = IOrigamiInvestment__factory.connect(
        config.OGMX_ADDRESS,
        connection.signer
    );
    const gmx: IERC20 = IERC20__factory.connect(
        config.GMX_ADDRESS,
        connection.signer
    );

    if (await wasHarvestedRecently(connection, config.MIN_HARVEST_INTERVAL_SECS, rewardAggregator)) {
        return noop();
    }

    const wethAddress = await rewardAggregator.wrappedNativeToken();
    const _harvestableRewards = await rewardAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    console.log(`\tGMX Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);
    const existingGmx = await gmx.balanceOf(rewardAggregator.address);
    console.log(`\tExisting GMX in aggregator: ${existingGmx.toString()}`);

    // Get a quote to swap $WETH -> $GMX
    const {quoteData: wethToGmxQuoteData, minAmountExpected: minGmxExpected} = commonConfig.NETWORK === 'arbitrum'
        ? await arbitrumWethToGmxQuote(
            commonConfig, 
            config, 
            wethAddress,
            harvestableRewards.weth,
        )
        : await mumbaiWethToGmxQuote(
            connection,
            config, 
            harvestableRewards.weth,
        );
        
    // The total $GMX we have to invest = 
    //   1/ The expected amount of $GMX we will receive from selling the $WETH +
    //   2/ Any existing balance from previous swaps left over amounts
    const gmxToInvestInOGmx = minGmxExpected.add(existingGmx);
    console.log(`gmxToInvestInOGmx=[${gmxToInvestInOGmx.toString()}]`);

    // Get a quote to swap $GMX -> $oGMX
    // NB: No slippage when investing in the oGMX position as it's minted in situ (not bought via a dex)
    const gmxToOgmxInvestQuote = await oGmx.investQuote(gmxToInvestInOGmx, config.GMX_ADDRESS, 0, 0);
    console.log(`GMX -> oGMX Invest Quote: ${gmxToOgmxInvestQuote}`);

    // The total $oGMX expected in the aggregator = 
    //   1/ The min expected amount after the wETH->GMX->oGMX swaps
    //   2/ The amount of oGMX already existing + harvested in the aggregator - given by the harvestableRewards()
    const totalOGmxAvailable = gmxToOgmxInvestQuote.quoteData.minInvestmentAmount.add(harvestableRewards.oGmx);
    console.log(`totalOGmxAvailable=[${totalOGmxAvailable.toString()}]`);

    // To smooth the bump up out, we only add a percentage of the total available oGMX as reserves
    // each day.
    const addToReserveAmount = totalOGmxAvailable.mul(config.DAILY_ADD_TO_RESERVE_BPS).div(10_000);
    console.log(`addToReserveAmount=[${addToReserveAmount}]`);

    const harvestParams: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct = {
        nativeToGmxSwapData: wethToGmxQuoteData,
        oGmxInvestQuoteData: gmxToOgmxInvestQuote.quoteData,
        addToReserveAmount: addToReserveAmount,
    };
    console.log("Harvest Params:", harvestParams);

    const encodedParams = encodeGmxHarvestParams(harvestParams);
    console.log("harvestRewards encoded params:", encodedParams);
    const populatedTx = await rewardAggregator.populateTransaction['harvestRewards'](encodedParams);
    const tx = await sendTransaction(connection, commonConfig, populatedTx);
    console.log(`Waiting on transaction: ${tx.hash}`);
    return createdTransaction(tx.hash);
}
