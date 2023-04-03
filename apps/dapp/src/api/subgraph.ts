import { ENABLE_SUBGRAPH_LOGS } from '@/config';
import { z } from 'zod';
import { ContractAddress, Token } from './types';

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
      apy
      tvlUSD
      reservesPerShare
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
      apy: z.string(),
      tvlUSD: z.string(),
    })
  ),
});
export type InvestmentVaultMetricsResp = z.infer<
  typeof InvestmentVaultMetricsResp
>;

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
      apy
      tvlUSD
      reservesPerShare
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
      apy: z.string(),
      tvlUSD: z.string(),
      reservesPerShare: z.string(),
    })
  ),
});
export type InvestmentVaultHourlySnapshotsResp = z.infer<
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
      apy
      tvlUSD
      reservesPerShare
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
      apy: z.string(),
      tvlUSD: z.string(),
      reservesPerShare: z.string(),
    })
  ),
});
export type InvestmentVaultDailySnapshotsResp = z.infer<
  typeof InvestmentVaultDailySnapshotsResp
>;

//----------------------------------------------------------------------------------------------------

export function queryPricedTokenHourlySnapshots(
  token: Token,
  first: number
): SubGraphQuery<PricedTokenHourlySnapshotsResp> {
  const label = 'queryPricedTokenHourlySnapshots';
  const tokenAddress = token.config.address.toLowerCase();
  const request = `
  {
    pricedTokenHourlySnapshots(
      where: {pricedToken: "${tokenAddress}"}
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
    parse: PricedTokenHourlySnapshotsResp.parse,
  };
}

const PricedTokenHourlySnapshotsResp = z.object({
  pricedTokenHourlySnapshots: z.array(
    z.object({
      timeframe: z.string(),
      timestamp: z.string(),
      price: z.string(),
    })
  ),
});
export type PricedTokenHourlySnapshotsResp = z.infer<
  typeof PricedTokenHourlySnapshotsResp
>;

//----------------------------------------------------------------------------------------------------

export function queryPricedTokenDailySnapshots(
  token: Token,
  first: number
): SubGraphQuery<PricedTokenDailySnapshotsResp> {
  const label = 'queryTokenPriceDailySnapshots';
  const tokenAddress = token.config.address.toLowerCase();
  const request = `
  {
    pricedTokenDailySnapshots(
      where: {pricedToken: "${tokenAddress}"}
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
    parse: PricedTokenDailySnapshotsResp.parse,
  };
}

const PricedTokenDailySnapshotsResp = z.object({
  pricedTokenDailySnapshots: z.array(
    z.object({
      timeframe: z.string(),
      timestamp: z.string(),
      price: z.string(),
    })
  ),
});
export type PricedTokenDailySnapshotsResp = z.infer<
  typeof PricedTokenDailySnapshotsResp
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

export function percentFromSubgraph(v: string): number {
  return parseFloat(v) / 100;
}
