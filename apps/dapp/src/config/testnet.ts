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
  rpcUrl: 'https://polygon-testnet.public.blastapi.io',
  walletRpcUrl: 'https://polygon-testnet.public.blastapi.io',
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
};

const MUMBAI_PRICE_CONTRACT: PriceContractConfig = {
  address: '0xF98C73Ce6eA51514E928A8c56eBAb3dC583A4994',
  chainId: MUMBAI.id,
};

const GMX_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x43686bbe40E3b4EcB8A08D521D9C084da050bF51',
    chainId: MUMBAI.id,
  },
  icon: 'gmx',
  name: 'ovGMX',
  description: "GMX's utility and governance token ($GMX)",
  supportedAssetsDescription: 'GMX',
  info: `
  Investors deposit GMX and are issued shares in the ovGMX vault.
  The price of ovGMX increases as rewards from staked GMX are harvested and auto-compounded. Yield is further boosted from staking derived esGMX and multiplier point rewards.
  `,
  moreInfoUrl:
    'https://mumbai.polygonscan.com/address/0x43686bbe40E3b4EcB8A08D521D9C084da050bF51',
};

const GLP_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x28E1e74661B6f354fcd11D3d01EDa798DcfaD894',
    chainId: MUMBAI.id,
  },
  icon: 'glp',
  name: 'ovGLP',
  description: "GMX's liquidity provider token ($GLP)",
  supportedAssetsDescription: 'staked GLP or one of the underlying GLP assets',
  info: `
  Investors deposit their existing staked GLP, or one of the underlying GLP assets (https://app.gmx.io/#/buy_glp) and are issued shares in the ovGLP vault.
  The price of ovGLP increases as rewards from staked GLP are harvested and auto-compounded. 
  `,
  moreInfoUrl:
    'https://mumbai.polygonscan.com/address/0x28E1e74661B6f354fcd11D3d01EDa798DcfaD894',
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
  address: '0x3be80dD1aC2533d91330C82aae89Fe4D2E540146',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'GMX',
  decimals: 18,
};

const OGMX_TOKEN: ExtendedTokenConfig = {
  address: '0x58893971408b4ce2c3cc326A8697Eec4471a5615',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'oGMX',
  decimals: 18,
};

const SGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x9d4Da39fB7971Eb27e951E26eC820fC137E71475',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'sGLP',
  decimals: 18,
};

const OGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'oGLP',
  decimals: 18,
};

const BTC_TOKEN: ExtendedTokenConfig = {
  address: '0x6C97233BBC1e8197688511586D46Ea7f98cBe775',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BTC',
  decimals: 18,
};

const BNB_TOKEN: ExtendedTokenConfig = {
  address: '0x6352dEabF5AC3A6f14d7A1e19092fBddcda89625',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BNB',
  decimals: 18,
};

const DAI_TOKEN: ExtendedTokenConfig = {
  address: '0x5B0eeE1336cD3f5136D3DaF6970236365b9E9cd7',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'DAI',
  decimals: 18,
};

const WETH_TOKEN: ExtendedTokenConfig = {
  address: '0x7Edb6ea1A90318E9D2B3Ae03e5617A5AAFd7b249',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WETH',
  decimals: 18,
};
