import { mine, runAsyncMain } from "../../../helpers";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { getDeployContext } from "../../deploy-context";
import { ContractAddresses } from "../../contract-addresses/types";
import { ContractInstances } from "../../contract-addresses";
import { ethers } from "ethers";
import { acceptOwner, createSafeBatch, recoverToken, setSwapper, writeSafeTransactionsBatch } from "../../../safe-tx-builder";
import path from "path";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupCowSwapper() {
    await mine(
        INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2.setOrderConfig(
            ADDRS.EXTERNAL.SKY.SKY_TOKEN,
            {
                maxSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.MAX_SELL_AMOUNT,
                buyToken: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
                minBuyAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.MIN_BUY_AMOUNT, 
                roundDownDivisor: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.ROUND_DOWN_DIVISOR,
                partiallyFillable: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.PARTIALLY_FILLABLE,
                useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
                limitPriceOracle: ADDRS.ORACLES.SKY_USDS,
                limitPriceAdjustmentBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.LIMIT_PRICE_ADJUSTMENT_BPS,
                verifySlippageBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.VERIFY_SLIPPAGE_BPS,
                expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.EXPIRY_PERIOD_SECS,
                recipient: ADDRS.VAULTS.SUSDSpS.MANAGER,
                appData: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.APP_DATA,
            }
        )
    );

    await mine(
        INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2.setCowApproval(
            ADDRS.EXTERNAL.SKY.SKY_TOKEN,
            ethers.constants.MaxUint256
        )
    );

    await mine(
        INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2.createConditionalOrder(ADDRS.EXTERNAL.SKY.SKY_TOKEN)
    );

    await mine(
        INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2.proposeNewOwner(ADDRS.CORE.MULTISIG)
    );
}



async function main() {
    ({ADDRS, INSTANCES} = await getDeployContext(__dirname));

    await setupCowSwapper();

    const cowSwapperBalance = 
        await INSTANCES.EXTERNAL.SKY.SKY_TOKEN.balanceOf(INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER.address);

    const batch = createSafeBatch(
        [
            acceptOwner(INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2),
            setSwapper(INSTANCES.VAULTS.SUSDSpS.MANAGER, INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2.address),
            recoverToken(
                INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER, 
                INSTANCES.EXTERNAL.SKY.SKY_TOKEN.address, 
                INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_2.address,
                cowSwapperBalance
            ),
        ]
    );

  const filename = path.join(__dirname, "../transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);