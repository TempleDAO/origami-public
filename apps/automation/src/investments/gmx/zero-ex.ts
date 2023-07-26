import qs from 'qs';
import axios from 'axios'
import { Logger } from '@mountainpath9/overlord';

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

export const CHAIN_IDS = {
    arbitrum: 42161,
    mumbai: 80001,
};

export const zeroExQuote = async (
    logger: Logger,
    chainId: number,
    quoteParams: ZeroExQuoteParams,
    apiKey: string,
): Promise<ZeroExQuoteResponse> => {
    try {
        const chainName = zeroExChainName(chainId);
        const url = `https://${chainName}.api.0x.org/swap/v1/quote?${qs.stringify(quoteParams)}`;
        logger.info(`Zero Ex Quote Request: [${url}]`);
        const { data } = await axios.get<ZeroExQuoteResponse>(url, {
            headers: { '0x-api-key' : apiKey }
        });
        logger.info(`Zero Ex Quote Response: [${JSON.stringify(data)}]`);
        return data;
      } catch (error) {
        if (axios.isAxiosError(error)) {
            logger.info(error.toJSON());
            throw error;
        } else {
          throw error;
        }
    }
}

function zeroExChainName(chainId: number): string {
    switch (chainId) {
        case 80001: return 'mumbai';
        case 42161: return 'arbitrum';
        default: throw new Error('unknown chain for 0x');
    }
}