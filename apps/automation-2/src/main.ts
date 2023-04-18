
import { createTaskRunner } from "@mountainpath9/overlord";
import { harvestGmxRewards } from "./investments/gmx/gmx-auto-compounder";
import { harvestGlpRewards } from "./investments/gmx/glp-auto-compounder";
import { transferStakedGlp } from "./investments/gmx/transfer-staked-glp";
import { getConfig } from "./config";


function main() {
  const runner = createTaskRunner("origami");
  const config = getConfig();

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
  
  runner.main();
}


main();
