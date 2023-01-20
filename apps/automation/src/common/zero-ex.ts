import qs from 'qs';
import axios from 'axios'
import { CHAIN_NAME } from '@/connect';

export interface ZeroExQuoteParams {
    sellToken: string,
    buyToken:  string,
    sellAmount: string ,
    priceImpactProtectionPercentage: number,
    enableSlippageProtection: boolean,
    slippagePercentage: number,
};

export interface ZeroExQuoteResponse {
    price: string,
    guaranteedPrice: string,
    estimatedPriceImpact: string,
    to: string,
    data: string,
    value: string,
    buyAmount: string,
    sellAmount: string ,
    expectedSlippage: string,
};

export const zeroExQuote = async (
    chainName: CHAIN_NAME,
    quoteParams: ZeroExQuoteParams,
): Promise<ZeroExQuoteResponse> => {
    try {
        const url = `https://${chainName}.api.0x.org/swap/v1/quote?${qs.stringify(quoteParams)}`;
        console.log(`Zero Ex Quote Request: [${url}]`);
        const { data } = await axios.get<ZeroExQuoteResponse>(url);
        console.log(`Zero Ex Quote Response: [${JSON.stringify(data)}]`);
        return data;
      } catch (error) {
        if (axios.isAxiosError(error)) {
            console.log(error.toJSON());
            throw error;
        } else {
          throw error;
        }
    }
}
