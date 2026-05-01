import {
  encodedOraclePrice,
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../helpers';
import { ContractInstances } from '../contract-addresses';
import { ContractAddresses } from '../contract-addresses/types';
import { DEFAULT_SETTINGS } from '../default-settings';
import { TokenPrices } from '../../../../typechain';
import { getDeployContext } from '../deploy-context';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

function getEncodedMappings() {
  return [
    {
      token: ZERO_ADDRESS, // native XPL
      fnCalldata: encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.XPL_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.XPL_USD_ORACLE.STALENESS_THRESHOLD
      )
    },
    {
      token: ADDRS.EXTERNAL.WXPL_TOKEN,
      fnCalldata: encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.XPL_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.XPL_USD_ORACLE.STALENESS_THRESHOLD
      )
    },
    {
      token: ADDRS.EXTERNAL.TETHER.USDT0_TOKEN,
      fnCalldata: encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.USDT0_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDT0_USD_ORACLE.STALENESS_THRESHOLD
      )
    },
    {
      token: ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
      fnCalldata: encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.USDE_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDE_USD_ORACLE.STALENESS_THRESHOLD
      )
    },
    {
      token: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
      fnCalldata: encodedOraclePrice(
        ADDRS.EXTERNAL.CHAINLINK.SUSDE_USD_ORACLE, 
        DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.SUSDE_USD_ORACLE.STALENESS_THRESHOLD
      )
    },
  ];
}

async function mapTokenPrices(tokenPrices: TokenPrices) {
  await mine(tokenPrices.setTokenPriceFunctions(getEncodedMappings()));
}

async function main() {
  ({ ADDRS, INSTANCES } = await getDeployContext(__dirname));
  
  const tokenPrices = INSTANCES.CORE.TOKEN_PRICES.V1;
  await mapTokenPrices(tokenPrices);
}

runAsyncMain(main);
