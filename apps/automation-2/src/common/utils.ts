
import { BigNumber } from "ethers";
import { Provider } from "@ethersproject/abstract-provider";

export async function getBlockTimestamp(provider: Provider): Promise<BigNumber> {
  const latestBlock = await provider.getBlock("latest");
  return BigNumber.from(latestBlock.timestamp);
}

export function bpsToFraction(bps: number): number {
  // eg 100 -> 0.01 (1%)
  return bps / 10_000;
}

// Keep trying to run `fn` until it returns true, sleeping in between, and timeout after 
// TOTAL_TIMEOUT_SECS
export const tryUntilTimeout = async (
  startUnixMilliSecs: number,
  config: TimeoutConfig,
  fn: () => Promise<boolean>,
): Promise<boolean> => {
  const cooldownSleepMilliSecs = 1000 * config.WAIT_SLEEP_SECS;

  while (true) {
      const canRun = await fn();

      if (canRun) {
          return true;
      }

      // Bail if the next sleep would take us over the timeout
      const secsElapsed = (new Date().getTime() - startUnixMilliSecs) / 1000;
      if (secsElapsed + config.WAIT_SLEEP_SECS >= config.TOTAL_TIMEOUT_SECS) {
          return false;
      }

      // Sleep for WAIT_SLEEP_SECS then try again.
      await sleep(cooldownSleepMilliSecs);
  }
}


export interface TimeoutConfig {
  WAIT_SLEEP_SECS: number, // Number of seconds to sleep between retries to check when waiting for conditions to be met.
  TOTAL_TIMEOUT_SECS: number, // The total number of seconds the bot will wait for conditions to be met. Note the OZ autotask will fail noisily after 300 secs, so suggest failing slightly before that.
};

export const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

export function min(v1: number, v2: number): number {
  return v1 < v2 ? v1 : v2;
}

export function assertNever(x: never): never {
  throw new Error("Unexpected object: " + x);
}