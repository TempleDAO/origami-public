
import { TaskContext, TaskException, createTaskRunner } from "@mountainpath9/overlord";
import { harvestGmxRewards } from "./investments/gmx/gmx-auto-compounder";
import { harvestGlpRewards } from "./investments/gmx/glp-auto-compounder";
import { transferStakedGlp } from "./investments/gmx/transfer-staked-glp";
import { createAlertPausedTask } from "./investments/gmx/alert-paused-status";
import { isLowEthBalance, reportLowEthBalance } from "./investments/gmx/eth-auto-checker";

import { CONFIG as CONFIG_TESTNETS } from "./config/testnets";
import { CONFIG as CONFIG_PRODNETS } from "./config/prodnets";

import { DISCORD_WEBHOOK_URL_KEY, connectDiscord } from "./common/discord";


async function main() {
  const runner = createTaskRunner();
  const label = await runner.getLabel();
  const config = getConfig(label);

  runner.setTaskExceptionHandler(discordNotifyTaskException)

  runner.addPeriodicTask({
    id: 'gmx-auto-compounder',
    cronSchedule: '30 10,22 * * *',
    action: async (ctx) => {
      await harvestGmxRewards(ctx, config.harvestGmx);
      await reportLowEthBalance(ctx, config.checkEthBalance);
    }
  });

  runner.addWebhookTask({
    id: 'gmx-auto-compounder-wh',
    action: async (ctx) => {
      await harvestGmxRewards(ctx, config.harvestGmx);
      await reportLowEthBalance(ctx, config.checkEthBalance);
    }
  });

  runner.addPeriodicTask({
    id: 'glp-auto-compounder',
    cronSchedule: '45 10,22 * * *',
    action: async (ctx) => {
      await harvestGlpRewards(ctx, config.harvestGlp);
      await reportLowEthBalance(ctx, config.checkEthBalance);
    }
  });

  runner.addWebhookTask({
    id: 'glp-auto-compounder-wh',
    action: async (ctx) => {
      await harvestGlpRewards(ctx, config.harvestGlp);
      await reportLowEthBalance(ctx, config.checkEthBalance);
    }
  });

  runner.addPeriodicTask({ 
    id: 'transfer-staked-glp',
    cronSchedule: '0 10,22 * * *',
    action: async (ctx) => {
      await transferStakedGlp(ctx, config.transferStakedGlp);
      await reportLowEthBalance(ctx, config.checkEthBalance);
    }
  });

  runner.addWebhookTask({ 
    id: 'transfer-staked-glp-wh',
    action: async (ctx) => {
      await transferStakedGlp(ctx, config.transferStakedGlp);
      await reportLowEthBalance(ctx, config.checkEthBalance);
    }
  });

  runner.addPeriodicTask({ 
    id: 'check-eth-balance',
    cronSchedule: '30 * * * *',
    predicate: async (ctx) => isLowEthBalance(ctx, config.checkEthBalance),
    action: async (ctx) => reportLowEthBalance(ctx, config.checkEthBalance),
  });
  
  const alertPausedTask = await createAlertPausedTask(runner, 'alert-paused-status', config.alertPausedStatus);
  runner.addChainEventTask(
    alertPausedTask
  );

  runner.main();
}

function getConfig(label: string) {
  if (label.endsWith('_testnets')) {
    return CONFIG_TESTNETS;
  } else {
    return CONFIG_PRODNETS;
  }
}

async function discordNotifyTaskException(ctx: TaskContext, te: TaskException) {
  const content = [
    `**ORIGAMI Task Failed**`,
    `task label: ${te.label}`,
    `task id: ${te.taskId}`,
    `task phase: ${te.phase}`,
  ];

  if (te.exception instanceof Error) {
    content.push(`exception type: Error`);
    // We truncate the message here as discord doesn't like large contents
    const message 
      = te.exception.message.length > 997 
      ? te.exception.message.substring(0, 997) + "..." 
      : te.exception.message;
    content.push(`exception message: ${message}`);
  } else {
    content.push(`exception type: unknown`);
  }

  const webhookUrl = await ctx.getSecret(DISCORD_WEBHOOK_URL_KEY);
  const discord = await connectDiscord(webhookUrl, ctx.logger);
  await discord.postMessage({content: content.join('\n')});
}

main();
