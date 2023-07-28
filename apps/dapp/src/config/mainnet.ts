import { ApiConfig, ExtendedTokenConfig } from '@/api/ethers';
import { Chain, InvestmentConfig, PriceContractConfig } from '@/api/types';

export function getApiConfig(): ApiConfig {
  return {
    chains: [ARBITRUM],
    tokens: [
      GMX_TOKEN_ON_ARBITRUM,
      SGLP_TOKEN_ON_ARBITRUM,
      OVGMX_TOKEN_ON_ARBITRUM,
      OVGLP_TOKEN_ON_ARBITRUM,
      OGMX_TOKEN_ON_ARBITRUM,
      OGLP_TOKEN_ON_ARBITRUM,

      WETH_TOKEN_ON_ARBITRUM,
      WBTC_TOKEN_ON_ARBITRUM,
      LINK_TOKEN_ON_ARBITRUM,
      UNI_TOKEN_ON_ARBITRUM,
      USDC_TOKEN_ON_ARBITRUM,
      USDCE_TOKEN_ON_ARBITRUM,
      USDT_TOKEN_ON_ARBITRUM,
      DAI_TOKEN_ON_ARBITRUM,
      FRAX_TOKEN_ON_ARBITRUM,
    ],
    investments: [GMX_ON_ARBITRUM, GLP_ON_ARBITRUM],
    priceContracts: [PRICE_CONTRACT_ON_ARBITRUM],
  };
}

const ARBITRUM: Chain = {
  name: 'Arbitrum One',
  id: 42161,
  rpcUrl: 'https://arb1.arbitrum.io/rpc',
  walletRpcUrl: 'https://arb1.arbitrum.io/rpc',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  subgraphUrl: 'https://api.thegraph.com/subgraphs/name/templedao/origami-arb',
  explorer: {
    transactionUrl: (hash) => `https://arbiscan.io/tx/${hash}`,
    tokenUrl: (hash) => `https://arbiscan.io/token/${hash}`,
  },
  iconName: 'arbitrum',
};

const PRICE_CONTRACT_ON_ARBITRUM: PriceContractConfig = {
  address: '0x534fe8c14d291950da1022d25D0f7d38Fe057ef4',
  chainId: ARBITRUM.id,
};

const GMX_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
  chainId: ARBITRUM.id,
  iconName: 'gmx',
  symbol: 'GMX',
  decimals: 18,
};

const OGMX_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0x784f75C39bD7D3EBC377e64991e99178341c831D',
  chainId: ARBITRUM.id,
  iconName: 'gmx',
  symbol: 'oGMX',
  decimals: 18,
};

const SGLP_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf',
  chainId: ARBITRUM.id,
  iconName: 'glp',
  symbol: 'sGLP',
  decimals: 18,
};

const OGLP_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xb48aC9c5585e5F3c88c63CF9bcbAEdC921F76Df2',
  chainId: ARBITRUM.id,
  iconName: 'glp',
  symbol: 'oGLP',
  decimals: 18,
};

const WETH_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WETH',
  decimals: 18,
};

const WBTC_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WBTC',
  decimals: 8,
};

const LINK_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'LINK',
  decimals: 18,
};

const UNI_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'UNI',
  decimals: 18,
};

// Bridged USDC from mainnet
const USDCE_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'USDC.e',
  decimals: 6,
};

// Native USDC (Circle minted) on Arbi
const USDC_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'USDC',
  decimals: 6,
};

const USDT_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'USDT',
  decimals: 6,
};

const DAI_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'DAI',
  decimals: 18,
};

const FRAX_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'FRAX',
  decimals: 18,
};

const MIM_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: '0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A',
  chainId: ARBITRUM.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'MIM',
  decimals: 18,
};

const GMX_ON_ARBITRUM: InvestmentConfig = {
  contractAddress: {
    address: '0xe488A643E4b0Aaae60E4bdC02045a10d8a323bae',
    chainId: ARBITRUM.id,
  },
  icon: 'gmx',
  name: 'ovGMX',
  description: "GMX's utility and governance token (GMX)",
  supportedAssetsDescription: 'GMX',
  info: `
  Users deposit GMX and receive proportional ovGMX vault shares.
  \n
  The GMX price per ovGMX will gradually rise, as GMX staking rewards are harvested and auto-compounded daily into vault reserves.
  \n
  The GMX vault yield is further boosted from staking GMX's esGMX and multiplier point rewards.
  `,
};

const excludedGlpTokens = [
  FRAX_TOKEN_ON_ARBITRUM.address,
  USDT_TOKEN_ON_ARBITRUM.address,
  MIM_TOKEN_ON_ARBITRUM.address,
];

const GLP_ON_ARBITRUM: InvestmentConfig = {
  contractAddress: {
    address: '0x7FC862A47BBCDe3812CA772Ae851d0A9D1619eDa',
    chainId: ARBITRUM.id,
  },
  icon: 'glp',
  name: 'ovGLP',
  description: "GMX's liquidity pool token (GLP)",
  supportedAssetsDescription: 'staked GLP or one of the underlying GLP assets',
  info: `
  Users deposit staked GLP and receive proportional ovGLP vault shares. 
  \n
  Alternatively users may provide one of the [underlying GLP assets](https://app.gmx.io/#/buy_glp), 
  and Origami will purchase GLP and deposit into the ovGLP vault on their behalf.
  \n
  The GLP price per ovGLP will gradually rise, as GLP staking rewards are harvested and auto-compounded daily into vault reserves. 
  \n
  Users may exit the vault directly into staked GLP or into one of the [underlying GLP assets](https://app.gmx.io/#/buy_glp)
  `,
  excludedDepositTokens: excludedGlpTokens,
  excludedExitTokens: excludedGlpTokens,
};

const OVGLP_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: GLP_ON_ARBITRUM.contractAddress.address,
  chainId: GLP_ON_ARBITRUM.contractAddress.chainId,
  iconName: GLP_ON_ARBITRUM.icon,
  symbol: GLP_ON_ARBITRUM.name,
  decimals: 18,
};

const OVGMX_TOKEN_ON_ARBITRUM: ExtendedTokenConfig = {
  address: GMX_ON_ARBITRUM.contractAddress.address,
  chainId: GMX_ON_ARBITRUM.contractAddress.chainId,
  iconName: GMX_ON_ARBITRUM.icon,
  symbol: GMX_ON_ARBITRUM.name,
  decimals: 18,
};

const _AVALANCHE: Chain = {
  name: 'Avalanche C-Chain',
  id: 43114,
  rpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  walletRpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  nativeCurrency: {
    name: 'ETH',
    symbol: 'ETH',
    decimals: 18,
  },
  subgraphUrl: 'https://TODO',
  explorer: {
    transactionUrl: (hash) => `https://snowtrace.io/tx/${hash}`,
    tokenUrl: (hash) => `https://snowtrace.io/token${hash}`,
  },
  iconName: 'error', // TODO: create icon
};
