import { 
    OrigamiGmxEarnAccount,
    OrigamiGmxEarnAccount__factory, 
    OrigamiGmxManager__factory
} from "@/typechain";
import { getBlockTimestamp } from '@/common/utils';
import { TaskContext, Logger } from "@mountainpath9/overlord";
import { tryUntilTimeout } from "@/common/utils";
import { Provider } from "@ethersproject/abstract-provider";
import { DiscordMesage, connectDiscord, urlEmbed } from "@/common/discord";
import * as ethers from "ethers";
import { formatBigNumber, matchAndDecodeEvent, txReceiptMarkdown } from "./utils";
import { Chain } from "@/chains";

export const TRANSACTION_NAME = 'transfer-staked-glp';

export interface TransferStakedGlpConfig {
    CHAIN: Chain,
    GLP_MANAGER: string, // The address of Origami's GLP Manager contract
    MIN_TRANSFER_INTERVAL_SECS: number, // How frequently the transfer is allowed to occur.
}

async function waitUntilAfterCooldown(
    logger: Logger,
    startUnixMilliSecs: number,
    secondaryEarnAccount: OrigamiGmxEarnAccount
): Promise<boolean> {
    return tryUntilTimeout(startUnixMilliSecs, TIMEOUT_CONFIG, async () => {
        const currentBlockTime = await getBlockTimestamp(secondaryEarnAccount.provider);
        const cooldownExpiry = await secondaryEarnAccount.glpInvestmentCooldownExpiry();
        const glpInvestmentsPaused = await secondaryEarnAccount.glpInvestmentsPaused();

        if (!glpInvestmentsPaused) {
            logger.info(`secondaryEarnAccount.glpInvestmentsPaused() = false. Executing transfer`);
            return true;
        } else if (currentBlockTime.gt(cooldownExpiry)) {
            logger.info(`Current Block Time [${currentBlockTime.toNumber()}] > Cooldown expiry [${cooldownExpiry.toNumber()}]. Executing transfer`);
            return true;
        } else {
            logger.info(
                `Cooldown has not yet passed. Current Block Time [${currentBlockTime.toNumber()}] <= ` +
                `Cooldown expiry [${cooldownExpiry.toNumber()}]. Remaining = [${cooldownExpiry.sub(currentBlockTime).toNumber()}] secs. Sleeping...`
            );
            return false;
        }
    });
}

const TIMEOUT_CONFIG = {
    WAIT_SLEEP_SECS:5,
    TOTAL_TIMEOUT_SECS:290,
};


export async function transferStakedGlp(
    ctx: TaskContext,
    config: TransferStakedGlpConfig,
): Promise<void> {
    const startUnixMilliSecs = (new Date()).getTime();

    const signer = await ctx.getSigner(config.CHAIN.id);

    const glpManager = OrigamiGmxManager__factory.connect(
        config.GLP_MANAGER, 
        signer
    );
    const primaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(
        await glpManager.primaryEarnAccount(), 
        signer
    );
    const secondaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(
        await glpManager.secondaryEarnAccount(), 
        signer
    );

    const secondaryPositions = await secondaryEarnAccount.positions();
    const stakedGlpToTransfer = secondaryPositions.glpPositions.stakedGlp;
    ctx.logger.info(
        `Secondary Earn Account [${secondaryEarnAccount.address}] Staked GLP Position = [${stakedGlpToTransfer}]`
    );
    ctx.logger.info(
        `Primary Earn Account [${primaryEarnAccount.address}] ` +
        `Staked GLP Position = [${(await primaryEarnAccount.positions()).glpPositions.stakedGlp}]`
    );

    // No staked GLP position tro transfer
    if (stakedGlpToTransfer.isZero()) {
        ctx.logger.info(`No staked GLP to transfer`);
        return;
    }

    const currentBlockTime = await getBlockTimestamp(secondaryEarnAccount.provider);
    const glpLastTransferredAt = await secondaryEarnAccount.glpLastTransferredAt();
    const timeSinceLastTransfer = currentBlockTime.sub(glpLastTransferredAt);

    // If the position has been transferred recently, then nothing to do.
    if (timeSinceLastTransfer.lte(config.MIN_TRANSFER_INTERVAL_SECS)) {
        ctx.logger.info(
            `Already transferred recently. currentBlockTime = [${currentBlockTime.toNumber()}] ` +
            `glpLastTransferredAt [${glpLastTransferredAt.toNumber()}] ` + 
            `MIN_TRANSFER_INTERVAL_SECS [${config.MIN_TRANSFER_INTERVAL_SECS}]. ` +
            `remaining [${config.MIN_TRANSFER_INTERVAL_SECS - timeSinceLastTransfer.toNumber()}] secs`
        );
        return;
    }

    if (!await waitUntilAfterCooldown(ctx.logger, startUnixMilliSecs, secondaryEarnAccount)) {
        ctx.logger.info(`Cooldown not yet expired`);
        return;
    }
    ctx.logger.info(
        `Transferring [${stakedGlpToTransfer}] Staked GLP from ` +
        `secondaryEarnAccount=[${secondaryEarnAccount.address}] to ` +
        `primaryEarnAccount=[${primaryEarnAccount.address}]`
    );

    // Execute the transactions
    const submittedAt = new Date();
    const tx = await secondaryEarnAccount.transferStakedGlpOrPause(stakedGlpToTransfer, primaryEarnAccount.address, {
        gasLimit: 3_000_000,
    });
    const txReceipt = await tx.wait();
    const txUrl = config.CHAIN.transactionUrl(txReceipt.transactionHash);    

    const filter = secondaryEarnAccount.filters.SetGlpInvestmentsPaused();

    // Grab the events of interest
    const events: string[] = [];
    for(const ev of txReceipt?.events || []) {
        const paused = matchAndDecodeEvent(secondaryEarnAccount, secondaryEarnAccount.filters.SetGlpInvestmentsPaused(), ev);
        if (paused) {
            events.push(`SetGlpInvestmentsPausedEventObject(pause=${paused.pause})`)
        }
        const transferred = matchAndDecodeEvent(secondaryEarnAccount, secondaryEarnAccount.filters.StakedGlpTransferred(), ev);
        if (transferred) {
            events.push(`StakedGlpTransferred(receiver=${transferred.receiver}, amount=${formatBigNumber(transferred.amount, 18, 4)})`)
        }
    }

    // Send notification
    const message = await buildDiscordMessage(signer.provider!, submittedAt, txReceipt, txUrl, events);
    const webhookUrl = await ctx.getSecret('discord_webhook_url');
    const discord = await connectDiscord(webhookUrl, ctx.logger);
    await discord.postMessage(message);
}

async function buildDiscordMessage(provider: Provider, submittedAt: Date, txReceipt: ethers.ContractReceipt, txUrl: string, events: string[]): Promise<DiscordMesage> {

    const content = [
        `**Transfer staked GLP**`,
        ``,
        ...events.map(ev => `_event_: ${ev})`),
        ``,
        ...await txReceiptMarkdown(provider, submittedAt, txReceipt),
    ];

    return {
        content: content.join('\n'),
        embeds: [
            urlEmbed(txUrl),
        ]
    }
}