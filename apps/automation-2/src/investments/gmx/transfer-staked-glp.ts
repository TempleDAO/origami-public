import { 
    OrigamiGmxEarnAccount,
    OrigamiGmxEarnAccount__factory, 
    OrigamiGmxManager__factory
} from "@/typechain";
import { getBlockTimestamp } from '@/common/utils';
import { TaskContext, Logger } from "@mountainpath9/overlord";
import { tryUntilTimeout } from "@/common/utils";
import { TransactionReceipt } from "@ethersproject/abstract-provider";
import { DiscordMesage, connectDiscord, urlEmbed } from "@/common/discord";
import { EmbedBuilder } from "discord.js";

export const TRANSACTION_NAME = 'transfer-staked-glp';

export interface TransferStakedGlpConfig {
    CHAIN_ID: number,
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

    const signer = await ctx.getSigner(config.CHAIN_ID);

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
    const populatedTx = await secondaryEarnAccount.populateTransaction.transferStakedGlpOrPause(stakedGlpToTransfer, primaryEarnAccount.address);
    const tx = await signer.sendTransaction(populatedTx);
    const txReceipt = await tx.wait();

    // Send notification
    const message = buildDiscordMessage(txReceipt);
    const webhookUrl = await ctx.getSecret('discord_webhook_url');
    const discord = await connectDiscord(webhookUrl, ctx.logger);
    await discord.postMessage(message);
}

function buildDiscordMessage(txReceipt: TransactionReceipt): DiscordMesage {
    // What:                                StakedGlpTransferred(receiver=0xA8E4c1Ce9B980734e814FBE979632e7fB6913096, amount=24,688.8733)
    // From:                                0x9dc9d0a95100c72bf6fcd66ef0a6a878bb83c858
    // To:                                      0xA8E4c1Ce9B980734e814FBE979632e7fB6913096
    // Amount:                           24,688.8733
    
    // Gas Price (GWEI):          30.0000
    // Gas Used:                        426,814
    // Total Fee (MATIC):         0.01280442
    // Mined At (Local):           4 April 2023 08:00
    // Mined At Unix:               1680559237
    // Submitted At Unix:       1680559232.092
    // Seconds To Mine:          4.908
    
    // TODO - extra code that extracts useful info, as per the above

    return {
        content: "Transfer staked GLP",
        embeds: [
            urlEmbed(`https://mumbai.polygonscan.com/tx/${txReceipt.transactionHash}`),
        ]
    }
}
