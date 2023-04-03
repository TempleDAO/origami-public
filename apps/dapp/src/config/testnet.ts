import { ApiConfig, ExtendedTokenConfig } from '@/api/ethers';
import { Chain, InvestmentConfig, PriceContractConfig } from '@/api/types';

export function getApiConfig(): ApiConfig {
  return {
    chains: [MUMBAI],
    tokens: [
      GMX_TOKEN,
      SGLP_TOKEN,
      OVGMX_TOKEN,
      OVGLP_TOKEN,
      OGMX_TOKEN,
      OGLP_TOKEN,
      BTC_TOKEN,
      BNB_TOKEN,
      DAI_TOKEN,
      WETH_TOKEN,
    ],
    investments: [GMX_ON_MUMBAI, GLP_ON_MUMBAI],
    priceContracts: [MUMBAI_PRICE_CONTRACT],
  };
}

const MUMBAI: Chain = {
  name: 'Polygon Mumbai',
  id: 80001,
  rpcUrl: 'https://rpc.ankr.com/polygon_mumbai',
  walletRpcUrl: 'https://rpc.ankr.com/polygon_mumbai',
  nativeCurrency: {
    name: 'MATIC',
    symbol: 'MATIC',
    decimals: 18,
  },
  subgraphUrl:
    'https://api.thegraph.com/subgraphs/name/medariox/origami-mumbai',
  explorer: {
    transactionUrl: (hash) => `https://mumbai.polygonscan.com/tx/${hash}`,
    tokenUrl: (hash) => `https://mumbai.polygonscan.com/token/${hash}`,
  },
  iconName: 'arbitrum',
};

const MUMBAI_PRICE_CONTRACT: PriceContractConfig = {
  address: '0x97EDBdCB4D4bD0bC3b784117db2970Aa27D2C6a8',
  chainId: MUMBAI.id,
};

const GMX_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x500244EDee4AfCa6a1be7E28010719D9bcB3CB3e',
    chainId: MUMBAI.id,
  },
  icon: 'gmx',
  name: 'ovGMX',
  description: "GMX's utility and governance token ($GMX)",
  supportedAssetsDescription: 'GMX',
  info: `
  Users deposit GMX and receive proportional ovGMX vault shares in the GMX vault.
  \n
  The ovGMX price in terms of GMX will rise as GMX staking rewards are harvested and auto-compounded into vault reserves.
  \n
  The GMX vault yield is further boosted from staking esGMX and multiplier point rewards.
  \n
  [More info](https://mumbai.polygonscan.com/address/0x500244EDee4AfCa6a1be7E28010719D9bcB3CB3e)
  `,
};

const GLP_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x7a8108A11949aa9F6395476F160304269A5EE48b',
    chainId: MUMBAI.id,
  },
  icon: 'glp',
  name: 'ovGLP',
  description: "GMX's liquidity provider token ($GLP)",
  supportedAssetsDescription: 'staked GLP or one of the underlying GLP assets',
  info: `
  Users deposit existing GLP and receive proportional ovGLP vault shares in the GLP vault. Alternatively users may deposit one of [underlying GLP assets](https://app.gmx.io/#/buy_glp) and receive the corresponding ovGLP.
  \n
  The price of ovGLP in terms of GLP will rise as GLP staking rewards are harvested and auto-compounded into vault reserves. 
  \n
  [More info](https://mumbai.polygonscan.com/address/0x7a8108A11949aa9F6395476F160304269A5EE48b)
  `,
};

const OVGLP_TOKEN: ExtendedTokenConfig = {
  address: GLP_ON_MUMBAI.contractAddress.address,
  chainId: GLP_ON_MUMBAI.contractAddress.chainId,
  iconName: GLP_ON_MUMBAI.icon,
  symbol: GLP_ON_MUMBAI.name,
  decimals: 18,
};

const OVGMX_TOKEN: ExtendedTokenConfig = {
  address: GMX_ON_MUMBAI.contractAddress.address,
  chainId: GMX_ON_MUMBAI.contractAddress.chainId,
  iconName: GMX_ON_MUMBAI.icon,
  symbol: GMX_ON_MUMBAI.name,
  decimals: 18,
};

const GMX_TOKEN: ExtendedTokenConfig = {
  address: '0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'GMX',
  decimals: 18,
};

const OGMX_TOKEN: ExtendedTokenConfig = {
  address: '0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'oGMX',
  decimals: 18,
};

const SGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x9f9d9e1f64618695142664280b6241442432e45b',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'sGLP',
  decimals: 18,
};

const OGLP_TOKEN: ExtendedTokenConfig = {
  address: '0xacfee3A66337067F75151637D0DefEd09E880914',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'oGLP',
  decimals: 18,
};

const BTC_TOKEN: ExtendedTokenConfig = {
  address: '0x436F79C41b477C28A292808523b3eb0E22202B7F',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BTC',
  decimals: 8,
};

const BNB_TOKEN: ExtendedTokenConfig = {
  address: '0xD80A1171E8E3400868051e7ced31550638660575',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BNB',
  decimals: 18,
};

const DAI_TOKEN: ExtendedTokenConfig = {
  address: '0x5da15e1fC595ff5991dD92447DB94Cfde78A08B8',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'DAI',
  decimals: 18,
};

const WETH_TOKEN: ExtendedTokenConfig = {
  address: '0xee8405FBBa52312cE8783a09A646992D2E209C8a',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WETH',
  decimals: 18,
};
