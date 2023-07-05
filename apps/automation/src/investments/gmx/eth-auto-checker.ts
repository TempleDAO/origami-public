import { TaskContext } from '@mountainpath9/overlord';
import { formatBigNumber } from './utils';
import { BigNumber } from 'ethers';
import { DISCORD_WEBHOOK_URL_KEY, DiscordMesage, connectDiscord } from '../../common/discord';
import { Chain } from '@/chains';

export interface CheckEthBalanceConfig {
    CHAIN: Chain,
    WALLET_NAME: string;
    MIN_ETH_BALANCE: BigNumber;
}

export async function checkEthBalance(
  ctx: TaskContext,
  config: CheckEthBalanceConfig
) {
  const provider = await ctx.getProvider(config.CHAIN.id);
  const signer = await ctx.getSigner(provider, config.WALLET_NAME);
  const balance = await signer.getBalance();
  const walletAddress = await signer.getAddress();
  const ethBalanceStr = formatBigNumber(balance, 18, 6);
  ctx.logger.info(`ETH Balance for [${walletAddress}] = [${ethBalanceStr}]`);

  if (balance.lt(config.MIN_ETH_BALANCE)) {
    // Report low balance
    const values = {
      "ethBalance": ethBalanceStr,
      "requiredBalance": formatBigNumber(config.MIN_ETH_BALANCE, 18, 6),
    };
    ctx.logger.error(`Eth balance below the required amount: ${JSON.stringify(values)}`);

    // Send alert notification
    const submittedAt = new Date();
    const message = await buildDiscordMessageCheckEth(config.CHAIN, submittedAt, walletAddress, balance, config.MIN_ETH_BALANCE);
    const webhookUrl = await ctx.getSecret(DISCORD_WEBHOOK_URL_KEY);
    const discord = await connectDiscord(webhookUrl, ctx.logger);
    await discord.postMessage(message);
  }
}

async function buildDiscordMessageCheckEth(
    chain: Chain,
    submittedAt: Date,
    watchAddress: string,
    ethBalance: BigNumber,
    minBalance: BigNumber
): Promise<DiscordMesage> {

    const content = [
        `**ORIGAMI LOW ETH ALERT [${chain.name}]**`,
        ``,
        `_address:_ ${watchAddress}`,
        `_required eth:_ ${formatBigNumber(minBalance, 18, 6)}`,
        `_eth balance:_  ${formatBigNumber(ethBalance, 18, 6)}`,
        `_submitted at:_ ${submittedAt.toISOString()}`,
        ``,
        `${chain.addressUrl(watchAddress)}`
    ];

    return {
        content: content.join('\n')
    }
}


