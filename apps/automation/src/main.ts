
import { TaskContext, TaskException, createTaskRunner } from "@mountainpath9/overlord";
import { harvestGmxRewards } from "./investments/gmx/gmx-auto-compounder";
import { harvestGlpRewards } from "./investments/gmx/glp-auto-compounder";
import { transferStakedGlp } from "./investments/gmx/transfer-staked-glp";
import { createAlertPausedTask } from "./investments/gmx/alert-paused-status";

import { DISCORD_WEBHOOK_URL_KEY, getConfig } from "./config";
import { connectDiscord } from "./common/discord";


async function main() {
  const runner = createTaskRunner("origami");
  const config = getConfig();

  runner.setTaskExceptionHandler(discordNotifyTaskException)

  runner.addPeriodicTask({
    id: 'gmx-auto-compounder',
    cronSchedule: '30 22 * * *',
    action: async (ctx) => harvestGmxRewards(ctx, config.harvestGmx),
  });

  runner.addWebhookTask({
    id: 'gmx-auto-compounder-wh',
    action: async (ctx) => harvestGmxRewards(ctx, config.harvestGmx),
  });

  runner.addPeriodicTask({
    id: 'glp-auto-compounder',
    cronSchedule: '30 22 * * *',
    action: async (ctx) => harvestGlpRewards(ctx, config.harvestGlp),
  });

  runner.addWebhookTask({
    id: 'glp-auto-compounder-wh',
    action: async (ctx) => harvestGlpRewards(ctx, config.harvestGlp),
  });

  runner.addPeriodicTask({ 
    id: 'transfer-staked-glp',
    cronSchedule: '0 22 * * *',
    action: async (ctx) => transferStakedGlp(ctx, config.transferStakedGlp),
  });

  runner.addWebhookTask({ 
    id: 'transfer-staked-glp-wh',
    action: async (ctx) => transferStakedGlp(ctx, config.transferStakedGlp),
  });
  
  const alertPausedTask = await createAlertPausedTask(runner, 'alert-paused-status', config.alertPausedStatus);
  runner.addChainEventTask(
    alertPausedTask
  );

  runner.main();
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
