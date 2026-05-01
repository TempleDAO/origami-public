import * as z from 'zod';
import { AddressSchema, BigIntSchema, FetchError, HexSchema } from './types';

const ENABLE_PENDLE_API_LOGS = false;

export interface ConvertReq {
  chainId: number;
  assetInAddr: string; // use zeroAddress for ETH
  assetInAmount: bigint;
  assetOutAddr: string; // use zeroAddress for ETH
  onlyScalableSources: boolean;
  recipient: string;
  slippageBps: number;
}

export interface PendleSwapQuoteParams {
  receiver: string;
  slippage: number; // between 0-1, 0.01 == 1%
  enableAggregator: boolean;
  aggregators: string; // eg kyberswap,okx. Recommend keeping to just kyberswap to reduce CU requirements
  tokensIn: string; // comma separated. Recommend just doing one at a time
  amountsIn: string;
  tokensOut: string;
  needScale: boolean; // set to true when amounts are updated onchain, eg in the middle of a bundle
}

const TxResponseSchema = z.object({
  data: HexSchema,
  to: AddressSchema,
  from: AddressSchema,
  value: BigIntSchema.optional(),
});
type TxResponse = z.infer<typeof TxResponseSchema>;

const ConvertResponseSchema = z.object({
  routes: z.array(
    z.object({
      tx: TxResponseSchema,
      outputs: z.array(
        z.object({
          token: AddressSchema,
          amount: BigIntSchema,
        })
      ),
      data: z.object({
        aggregatorType: z.string(),
        priceImpact: z.number(),
      }),
    })
  ),
});
type ConvertResponse = z.infer<typeof ConvertResponseSchema>;

export async function convert(req: ConvertReq) {
  const params: PendleSwapQuoteParams = {
    receiver: req.recipient,
    slippage: req.slippageBps / 10_000,
    enableAggregator: true,
    aggregators: 'kyberswap',
    tokensIn: req.assetInAddr,
    amountsIn: req.assetInAmount.toString(),
    tokensOut: req.assetOutAddr,
    needScale: req.onlyScalableSources,
  };

  const convertArgs = new URLSearchParams(
    Object.entries(params).map(([k, v]) => [k, v.toString()])
  );

  if (ENABLE_PENDLE_API_LOGS) {
    console.debug(`Pendle /convert params: ${convertArgs}`);
  }

  const url = `https://api-v2.pendle.finance/core/v2/sdk/${req.chainId}/convert` + '?' + convertArgs;
  if (ENABLE_PENDLE_API_LOGS) {
    console.debug("Full Query:", url);
  }

  const getConvertData = async (): Promise<ConvertResponse> =>  {
    const resp = await fetch(url, {
      headers: {
        'Content-Type': 'application/json',
      },
    });

    if (!resp.ok) {
      throw new FetchError(
        resp.status,
        `pendle /convert failed with status: ${resp.status}, body: ${await resp.text()}, params: ${JSON.stringify(params)}`
      );
    }
    const respData = await resp.json();
    if (ENABLE_PENDLE_API_LOGS) {
      console.debug(
        `Pendle /convert response: ${JSON.stringify(respData, undefined, 2)}`
      );
    }
    return ConvertResponseSchema.parse(respData);
  }

  const convertResp = await getConvertData();

  if (convertResp.routes.length < 1) {
    throw new Error(`Expected at least one route from Pendle API`);
  }

  // Pendle returns the routes 'best' to 'worst'. So take the first one
  const bestRoute = convertResp.routes[0];
  if (bestRoute.outputs.length != 1) {
    throw new Error(`Expected exactly one output token from Pendle API`);
  }

  return bestRoute;  
}
