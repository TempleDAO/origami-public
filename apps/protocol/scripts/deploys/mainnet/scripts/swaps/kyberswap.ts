import { z } from 'zod';

export interface SwapParams {
  tokenIn: string,
  tokenOut: string,
  amountIn: string,
  gasInclude: boolean, // Best execution price taking into account current gas price
  source: string, // client id
  slippageTolerance: number, // in bps
  sender: string,
  recipient: string,
}

const SwapResponse = z.object({
  code: z.number(),
  message: z.string(),
  data: z.object({
    amountIn: z.string(),
    amountInUsd: z.string(),
    amountOut: z.string(),
    amountOutUsd: z.string(),
    gas: z.string(),
    gasUsd: z.string(),
    outputChange: z.object({
      amount: z.string(),
      percent: z.number(),
      level: z.number(),
    }),
    data: z.string(),
    routerAddress: z.string(),
  }),
  requestId: z.string(),
});

export type SwapResponse = z.infer<typeof SwapResponse>;

export async function getSwap(chainId: number, params: SwapParams): Promise<SwapResponse> {
  return _getSwap(chainId, params);
}

async function _getSwap(chainId: number, params: SwapParams): Promise<SwapResponse> {
  const routeSummary = await _getSwapRouteData(chainId, params);
  return _buildSwap(chainId, routeSummary, params);
}

async function _getSwapRouteData(chainId: number, params: SwapParams): Promise<string> {
  const args = [
    `tokenIn=${params.tokenIn}`,
    `tokenOut=${params.tokenOut}`,
    `amountIn=${params.amountIn}`,
    `gasInclude=${params.gasInclude.toString()}`,
    `source=${params.source}`,
  ];
  const swapArgs = args.join("&");
  console.log(`KyberSwap route params: ${swapArgs}`);
  const url = apiRequestUrl(chainId, "/routes") + "?" + swapArgs;
  console.log(url);
  const resp = await fetch(url, {
    headers: {
      "x-client-id": params.source,
      "accept": "application/json"
    }
  });

  if (!resp.ok) {
    throw new Error(`kyberswap.getSwapRoutes failed with status: ${resp.status}, body: ${await resp.text()}`);
  }
  const respData = await resp.json();
  return respData.data.routeSummary;
}

async function _buildSwap(chainId: number, routeSummary: string, params: SwapParams): Promise<SwapResponse> {
  const args = JSON.stringify({
    routeSummary: routeSummary,
    slippageTolerance: params.slippageTolerance,
    sender: params.sender,
    recipient: params.recipient,
    source: params.source,
  });
  console.log(`KyberSwap build params: ${args}`);
  const url = apiRequestUrl(chainId, "/route/build");
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "x-client-id": params.source,
      "accept": "application/json"
    },
    body: args
  });

  if (!resp.ok) {
    throw new Error(`kyberswap.getSwapRoutes failed with status: ${resp.status}, body: ${await resp.text()}`);
  }
  const jv = await resp.json();
  return SwapResponse.parse(jv);
}

function apiRequestUrl(chainId: number, methodName: string) {
  return `https://aggregator-api.kyberswap.com/${mapToNetworkName(chainId)}/api/v1${methodName}`;
}

// Kyberswap maps to their own names based on the chainId
// https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator/aggregator-api-specification/evm-swaps
function mapToNetworkName(chainId: number) {
  const names: { [key: number]: string } = {
    1: 'ethereum',
    56: 'bsc',
    42161: 'arbitrum',
    137: 'polygon',
    10: 'optimism',
    43114: 'avalanche',
    8453: 'base',
    25: 'cronos',
    324: 'zksync',
    250: 'fantom',
    59144: 'linea',
    1101: 'polygon-zkevm',
    1313161554: 'aurora',
    199: 'bittorrent',
    534352: 'scroll',
  };

  return names[chainId];
}
