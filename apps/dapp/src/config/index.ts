import { ApiConfig } from '@/api/ethers';
import { getApiConfig as getTestnetApiConfig } from './testnet';
import { getApiConfig as getMainnetApiConfig } from './mainnet';

// 'MODE=development' when Vite runs locally (`yarn dev`) or if the CLI `--mode=development` flag is explicitly set.
// When deployed via vercel (in preview or production), `MODE=production` always.
//
// In that instance, the `$VITE_ENV` environment variable can be set to either `development` or `production` to control
// whether to use testnet or mainnet.
const MODE = import.meta.env.MODE;
const ENV = import.meta.env.VITE_ENV;

export function getApiConfig(): ApiConfig {
  if (MODE == 'development' || ENV == 'development') {
    return getTestnetApiConfig();
  } else {
    return getMainnetApiConfig();
  }
}

export const IS_DEVELOPMENT = MODE == 'development';
export const ENABLE_API_LOGS = IS_DEVELOPMENT;
export const ENABLE_SUBGRAPH_LOGS = false;
export { tokenLabelMap } from './tokenLabelMap';
