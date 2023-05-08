import { Chain } from "@/chains";
import { DiscordMesage, connectDiscord } from "@/common/discord";
import { matchLog } from "@/common/filters";
import { OrigamiGmxManager, OrigamiGmxManager__factory } from "@/typechain";
import { IOrigamiGmxManager } from "@/typechain/OrigamiGmxManager";
import { TypedEvent, TypedEventFilter } from "@/typechain/common";
import { ChainEventTask, TaskContext, TaskRunner } from "@mountainpath9/overlord";
import { BaseContract, providers } from "ethers";


export interface AlertPausedStatusConfig {
  CHAIN: Chain,
  GLP_MANAGER: string,
  GMX_MANAGER: string,
}

export async function createAlertPausedTask(taskRunner: TaskRunner, id: string, config: AlertPausedStatusConfig): Promise<ChainEventTask> {

  const provider = await taskRunner.getProvider(config.CHAIN.id);
  const glpManager: OrigamiGmxManager = OrigamiGmxManager__factory.connect(
    config.GLP_MANAGER,
    provider
  );
  const gmxManager: OrigamiGmxManager = OrigamiGmxManager__factory.connect(
    config.GMX_MANAGER,
    provider
  );
  const glpFilter = glpManager.filters.PausedSet();
  const gmxFilter = gmxManager.filters.PausedSet();

  async function action(ctx: TaskContext, log: providers.Log): Promise<void> {
    let logArgs = undefined;
    let contractLabel = "";
    if (!logArgs) {
      logArgs = matchLog(log, glpManager, glpFilter);
      contractLabel = "GLP Manager";
    }
    if (!logArgs) {
      logArgs = matchLog(log, gmxManager, gmxFilter);
      contractLabel = "GMX Manager";
    }
    if (!logArgs) {
      ctx.logger.error('unexpected log message found');
      return;
    }
    const txUrl = config.CHAIN.transactionUrl(log.transactionHash);

    // Send notification
    const message = await buildDiscordMessage(log, contractLabel, txUrl, logArgs[0]);
    const webhookUrl = await ctx.getSecret('discord_webhook_url');
    const discord = await connectDiscord(webhookUrl, ctx.logger);
    await discord.postMessage(message);
  }

  return {
    id: id,
    chainId:config.CHAIN.id,
    filters: [glpFilter, gmxFilter],
    action,
  };
}

async function buildDiscordMessage(log: providers.Log, contractLabel: string, txUrl: string, paused: IOrigamiGmxManager.PausedStructOutput): Promise<DiscordMesage> {
  
  const content = [
      `**Origami Paused Status Change on ${contractLabel}**`,
      ``,
      `*glpInvestmentsPaused:* \`${paused.glpInvestmentsPaused}\``,
      `*gmxInvestmentsPaused:* \`${paused.gmxInvestmentsPaused}\``,
      `*glpExitsPaused:* \`${paused.glpExitsPaused}\``,
      `*gmxExitsPaused:* \`${paused.gmxExitsPaused}\``,
      ``,
      txUrl,
  ];

  return {
      content: content.join('\n'),
      embeds: [
      ]
  }
}

export function parseLogArgs<TArgsArray extends any[], TArgsObject>(
  log: providers.Log,
  contract: BaseContract,
  _eventFilter: TypedEventFilter<TypedEvent<TArgsArray, TArgsObject>>
): TArgsArray & TArgsObject {
  const args = contract.interface.parseLog(log).args;
  return args as TArgsArray & TArgsObject;
}