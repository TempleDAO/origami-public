import * as z from 'zod';

export interface SwapExactTokenForPtReq {
  chainId: number;
  receiverAddr: string;
  marketAddr: string;
  tokenInAddr: String;
  amountTokenIn: string;
  slippage: number;
}
const SWAP_EXACT_TOKEN_FOR_PT_RESP = z.object({
  transaction: z.object({
    data: z.string()
  }),
  data: z.object({
    amountPtOut: z.string(),
  }),
});

type SwapExactTokenForPtResp = z.infer<typeof SWAP_EXACT_TOKEN_FOR_PT_RESP>;

export async function swapExactTokenForPt(req: SwapExactTokenForPtReq): Promise<SwapExactTokenForPtResp> {
  const url = pendleUrl('swapExactTokenForPt', [
    `chainId=${req.chainId}`,
    `receiverAddr=${req.receiverAddr}`,
    `marketAddr=${req.marketAddr}`,
    `tokenInAddr=${req.tokenInAddr}`,
    `amountTokenIn=${req.amountTokenIn}`,
    `slippage=${req.slippage}`,
  ]);
  console.log(url);
  const resp = await fetch(url, {
    headers: {
      accept: 'application/json',
    }
  });
  const jv = await resp.json();
  return SWAP_EXACT_TOKEN_FOR_PT_RESP.parse(jv);
}

export interface SwapExactPtForTokenReq {
  chainId: number;
  receiverAddr: string;
  marketAddr: string;
  amountPtIn: string;
  tokenOutAddr: string;
  slippage: number;
}
const SWAP_EXACT_PT_FOR_TOKEN_RESP = z.object({
  transaction: z.object({
    data: z.string()
  }),
  data: z.object({
    amountTokenOut: z.string(),
  }),
});

type SwapExactPtForTokenResp = z.infer<typeof SWAP_EXACT_PT_FOR_TOKEN_RESP>;

export async function swapExactPtForToken(req: SwapExactPtForTokenReq): Promise<SwapExactPtForTokenResp> {
  const url = pendleUrl('swapExactPtForToken', [
    `chainId=${req.chainId}`,
    `receiverAddr=${req.receiverAddr}`,
    `marketAddr=${req.marketAddr}`,
    `amountPtIn=${req.amountPtIn}`,
    `tokenOutAddr=${req.tokenOutAddr}`,
    `slippage=${req.slippage}`,
  ]);
  console.log(url);
  const resp = await fetch(url, {
    headers: {
      accept: 'application/json',
    }
  });
  const jv = await resp.json();
  return SWAP_EXACT_PT_FOR_TOKEN_RESP.parse(jv);
}


function pendleUrl(method: string, args: string[]): string {
  return `${API}/${method}?${args.join('&')}`;
}

const API = "https://api-v2.pendle.finance/sdk/api/v1";
