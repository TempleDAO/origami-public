import { z } from 'zod';

export interface SwapParams {
  tokenIn: string;
  tokenOut: string;
  amount: string;
  to?: string;
  slippage?: number;
  liquiditySources?: string[];
  liquiditySourcesBlacklist?: string[];
}

// Common fields when a route is found
const PriceInfoResponse = z.object({
  status: z.enum(['Success', 'Partial']),
  assumedAmountOut: z.string(),
  routerAddr: z.string(),
  tx: z.optional(
    z.object({
      value: z.string(),
      to: z.string(),
      data: z.string(),
    })
  ),
});

// API Response Types
const BaseResponse = z.object({
  blockNumber: z.number(),
});

const NoRouteResponse = BaseResponse.extend({
  status: z.literal('NoWay'),
});

const SwapResponse = z.discriminatedUnion('status', [
  PriceInfoResponse.passthrough(),
  NoRouteResponse,
]);

export type SwapResponse = z.infer<typeof SwapResponse>;


/**
 * Get swap quote and execution data from Ooga Booga API
 */
export async function getSwap(
  apiKey: string,
  params: SwapParams
): Promise<SwapResponse> {
  return _getSwap(apiKey, params);
}

async function _getSwap(
  apiKey: string,
  params: SwapParams,
): Promise<SwapResponse> {
  const searchParams = new URLSearchParams({
    tokenIn: params.tokenIn,
    tokenOut: params.tokenOut,
    amount: params.amount,
  });

  if (params.to) {
    searchParams.set('to', params.to);
  }
  if (params.slippage !== undefined) {
    searchParams.set('slippage', params.slippage.toString());
  }
  if (params.liquiditySources?.length) {
    params.liquiditySources.forEach((source) =>
      searchParams.append('liquiditySources', source)
    );
  }
  if (params.liquiditySourcesBlacklist?.length) {
    params.liquiditySourcesBlacklist.forEach((source) =>
      searchParams.append('liquiditySourcesBlacklist', source)
    );
  }

  console.debug(`Ooga Booga swap params: ${searchParams}`);
  const url = apiRequestUrl('swap') + '?' + searchParams;

  const resp = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
  });

  if (!resp.ok) {
    throw new Error(
      `oogabooga.getSwap failed with status: ${
        resp.status
      }, body: ${await resp.text()}`
    );
  }

  const data = await resp.json();

  console.debug(`Ooga Booga swap response: ${JSON.stringify(data, null, 2)}`);

  try {
    return SwapResponse.parse(data);
  } catch (error) {
    console.error(`Failed to parse Ooga Booga response:${error}`);
    console.error(`Raw response data: \n${JSON.stringify(data, null, 2)}`);
    throw error;
  }
}

function apiRequestUrl(methodName: string) {
  return `https://mainnet.api.oogabooga.io/v1/${methodName}`;
}
