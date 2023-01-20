import { AutotaskResult, createdTransaction, noop, timeout } from "@/autotask-result";
import { CommonConfig } from "@/config";
import { AutotaskConnection } from "@/connect";
import { 
    OrigamiGmxEarnAccount,
    OrigamiGmxEarnAccount__factory, 
    OrigamiGmxManager__factory
} from "@/typechain";
import { getBlockTimestamp, sendTransaction } from '@/ethers';
import { tryUntilTimeout, waitForLastTransactionToFinish } from "@/utils";

export const TRANSACTION_NAME = 'transfer-staked-glp';

export interface TransferStakedGlpConfig {
    GLP_MANAGER: string, // The address of Origami's GLP Manager contract
    MIN_TRANSFER_INTERVAL_SECS: number, // How frequently the transfer is allowed to occur.
}

async function waitUntilAfterCooldown(
    connection: AutotaskConnection,
    commonConfig: CommonConfig,
    startUnixMilliSecs: number,
    secondaryEarnAccount: OrigamiGmxEarnAccount
): Promise<boolean> {
    return tryUntilTimeout(startUnixMilliSecs, commonConfig, async () => {
        const currentBlockTime = await getBlockTimestamp(connection);
        const cooldownExpiry = await secondaryEarnAccount.glpInvestmentCooldownExpiry();
        const glpInvestmentsPaused = await secondaryEarnAccount.glpInvestmentsPaused();

        if (!glpInvestmentsPaused) {
            console.log(`secondaryEarnAccount.glpInvestmentsPaused() = false. Executing transfer`);
            return true;
        } else if (currentBlockTime.gt(cooldownExpiry)) {
            console.log(`Current Block Time [${currentBlockTime.toNumber()}] > Cooldown expiry [${cooldownExpiry.toNumber()}]. Executing transfer`);
            return true;
        } else {
            console.log(
                `Cooldown has not yet passed. Current Block Time [${currentBlockTime.toNumber()}] <= ` +
                `Cooldown expiry [${cooldownExpiry.toNumber()}]. Remaining = [${cooldownExpiry.sub(currentBlockTime).toNumber()}] secs. Sleeping...`
            );
            return false;
        }
    });
}

export async function transferStakedGlp(
    connection: AutotaskConnection,
    commonConfig: CommonConfig,
    config: TransferStakedGlpConfig,
): Promise<AutotaskResult> {
    const startUnixMilliSecs = (new Date()).getTime();

    // Wait for any in flight transactions to complete first.
    if (!await waitForLastTransactionToFinish(connection, commonConfig, startUnixMilliSecs)) {
        return timeout('previous transaction still pending');
    }

    const glpManager = OrigamiGmxManager__factory.connect(
        config.GLP_MANAGER, 
        connection.signer
    );
    const primaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(
        await glpManager.primaryEarnAccount(), 
        connection.signer
    );
    const secondaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(
        await glpManager.secondaryEarnAccount(), 
        connection.signer
    );

    const secondaryPositions = await secondaryEarnAccount.positions();
    const stakedGlpToTransfer = secondaryPositions.glpPositions.stakedGlp;
    console.log(
        `Secondary Earn Account [${secondaryEarnAccount.address}] Staked GLP Position = [${stakedGlpToTransfer}]`
    );
    console.log(
        `Primary Earn Account [${primaryEarnAccount.address}] ` +
        `Staked GLP Position = [${(await primaryEarnAccount.positions()).glpPositions.stakedGlp}]`
    );

    // No staked GLP position tro transfer
    if (stakedGlpToTransfer.isZero()) {
        console.log(`No staked GLP to transfer`);
        return noop();
    }

    const currentBlockTime = await getBlockTimestamp(connection);
    const glpLastTransferredAt = await secondaryEarnAccount.glpLastTransferredAt();
    const timeSinceLastTransfer = currentBlockTime.sub(glpLastTransferredAt);

    // If the position has been transferred recently, then nothing to do.
    if (timeSinceLastTransfer.lte(config.MIN_TRANSFER_INTERVAL_SECS)) {
        console.log(
            `Already transferred recently. currentBlockTime = [${currentBlockTime.toNumber()}] ` +
            `glpLastTransferredAt [${glpLastTransferredAt.toNumber()}] ` + 
            `MIN_TRANSFER_INTERVAL_SECS [${config.MIN_TRANSFER_INTERVAL_SECS}]. ` +
            `remaining [${config.MIN_TRANSFER_INTERVAL_SECS - timeSinceLastTransfer.toNumber()}] secs`
        );
        return noop();
    }

    if (!await waitUntilAfterCooldown(connection, commonConfig, startUnixMilliSecs, secondaryEarnAccount)) {
        return timeout('Cooldown not yet expired');
    }

    console.log(
        `Transferring [${stakedGlpToTransfer}] Staked GLP from ` +
        `secondaryEarnAccount=[${secondaryEarnAccount.address}] to ` +
        `primaryEarnAccount=[${primaryEarnAccount.address}]`
    );
    const populatedTx = await secondaryEarnAccount.populateTransaction.transferStakedGlpOrPause(stakedGlpToTransfer, primaryEarnAccount.address);
    const tx = await sendTransaction(connection, commonConfig, populatedTx);
    console.log(`Waiting on transaction: ${tx.hash}`);
    return createdTransaction(tx.hash);
}
