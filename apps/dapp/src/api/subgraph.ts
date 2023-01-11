import { z } from 'zod';
import { ContractAddress, Token } from './types';

const ENABLE_SUBGRAPH_LOGS = false;

/** A typed query to subgraph  */
interface SubGraphQuery<T> {
  label: string;
  request: string;
  parse(response: unknown): T;
}

//----------------------------------------------------------------------------------------------------

export function queryInvestmentVaultMetrics(
  investmentAddress: ContractAddress
): SubGraphQuery<InvestmentVaultMetricsResp> {
  const label = 'queryInvestmentVaultMetrics';
  const investmentId = investmentAddress.address.toLowerCase();
  const request = `
  {
    investmentVault(id:"${investmentId}") {
      timestamp
      apr
      tvl
    }
  }
  `;
  return {
    label,
    request,
    parse: InvestmentVaultMetricsResp.parse,
  };
}

const InvestmentVaultMetricsResp = z.object({
  investmentVault: z.optional(
    z.object({
      apr: z.string(),
      tvl: z.string(),
    })
  ),
});
type InvestmentVaultMetricsResp = z.infer<typeof InvestmentVaultMetricsResp>;

//----------------------------------------------------------------------------------------------------

export function queryInvestmentVaultHourlySnapshots(
  investmentAddress: ContractAddress,
  first: number
): SubGraphQuery<InvestmentVaultHourlySnapshotsResp> {
  const label = 'queryInvestmentVaultHourlySnapshots';
  const investmentId = investmentAddress.address.toLowerCase();
  const request = `
  {
    investmentVaultHourlySnapshots(
      where: {investmentVault: "${investmentId}"}
      orderBy: timestamp
      first: ${first}
      orderDirection: desc
    ) {
      timeframe
      timestamp
      apr
      tvl
    }
  }
  `;

  return {
    label,
    request,
    parse: InvestmentVaultHourlySnapshotsResp.parse,
  };
}

const InvestmentVaultHourlySnapshotsResp = z.object({
  investmentVaultHourlySnapshots: z.array(
    z.object({
      timeframe: z.string(),
      timestamp: z.string(),
      apr: z.string(),
      tvl: z.string(),
    })
  ),
});
type InvestmentVaultHourlySnapshotsResp = z.infer<
  typeof InvestmentVaultHourlySnapshotsResp
>;

//----------------------------------------------------------------------------------------------------

export function queryInvestmentVaultDailySnapshots(
  investmentAddress: ContractAddress,
  first: number
): SubGraphQuery<InvestmentVaultDailySnapshotsResp> {
  const label = 'queryInvestmentVaultDailySnapshots';
  const investmentId = investmentAddress.address.toLowerCase();
  const request = `
  {
    investmentVaultDailySnapshots(
      where: {investmentVault: "${investmentId}"}
      orderBy: timestamp
      first: ${first}
      orderDirection: desc
    ) {
      timeframe
      timestamp
      apr
      tvl
    }
  }
  `;

  return {
    label,
    request,
    parse: InvestmentVaultDailySnapshotsResp.parse,
  };
}

const InvestmentVaultDailySnapshotsResp = z.object({
  investmentVaultDailySnapshots: z.array(
    z.object({
      timeframe: z.string(),
      timestamp: z.string(),
      apr: z.string(),
      tvl: z.string(),
    })
  ),
});
type InvestmentVaultDailySnapshotsResp = z.infer<
  typeof InvestmentVaultDailySnapshotsResp
>;

//----------------------------------------------------------------------------------------------------

export function queryRewardTokenHourlySnapshots(
  token: Token,
  first: number
): SubGraphQuery<RewardTokenHourlySnapshotsResp> {
  const label = 'queryRewardTokenHourlySnapshots';
  const tokenAddress = token.config.address.toLowerCase();
  const request = `
  {
    rewardTokenHourlySnapshots(
      where: {rewardToken: "${tokenAddress}"}
      orderBy: timestamp
      first: ${first}
      orderDirection: desc
    ) {
      timeframe
      timestamp
      price
    }
  }
  `;

  return {
    label,
    request,
    parse: RewardTokenHourlySnapshotsResp.parse,
  };
}

const RewardTokenHourlySnapshotsResp = z.object({
  rewardTokenHourlySnapshots: z.array(
    z.object({
      timeframe: z.string(),
      timestamp: z.string(),
      price: z.string(),
    })
  ),
});
type RewardTokenHourlySnapshotsResp = z.infer<
  typeof RewardTokenHourlySnapshotsResp
>;

//----------------------------------------------------------------------------------------------------

export function queryRewardTokenDailySnapshots(
  token: Token,
  first: number
): SubGraphQuery<RewardTokenDailySnapshotsResp> {
  const label = 'queryTokenPriceDailySnapshots';
  const tokenAddress = token.config.address.toLowerCase();
  const request = `
  {
    rewardTokenDailySnapshots(
      where: {rewardToken: "${tokenAddress}"}
      orderBy: timestamp
      first: ${first}
      orderDirection: desc
    ) {
      timeframe
      timestamp
      price
    }
  }
  `;

  return {
    label,
    request,
    parse: RewardTokenDailySnapshotsResp.parse,
  };
}

const RewardTokenDailySnapshotsResp = z.object({
  rewardTokenDailySnapshots: z.array(
    z.object({
      timeframe: z.string(),
      timestamp: z.string(),
      price: z.string(),
    })
  ),
});
type RewardTokenDailySnapshotsResp = z.infer<
  typeof RewardTokenDailySnapshotsResp
>;

//----------------------------------------------------------------------------------------------------

export async function subgraphQuery<T>(
  url: string,
  query: SubGraphQuery<T>
): Promise<T> {
  const response = await rawSubgraphQuery(url, query.label, query.request);
  return query.parse(response);
}

export async function rawSubgraphQuery(
  url: string,
  label: string,
  query: string
): Promise<unknown> {
  if (ENABLE_SUBGRAPH_LOGS) {
    console.log('subgraph-request', label, query);
  }
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query }),
  });

  const rawResults = await response.json();

  if (ENABLE_SUBGRAPH_LOGS) {
    console.log('subgraph-response', label, rawResults);
  }
  if (rawResults.errors !== undefined) {
    throw new Error(
      `Unable to fetch ${label} from subgraph: ${rawResults.errors}`
    );
  }

  return rawResults.data as unknown;
}

export function dateFromTimestamp(timestamp: string): Date {
  return new Date(parseFloat(timestamp) * 1000);
}

export function percentFromBps(v: string): number {
  return parseFloat(v) / 10000;
}
