import type { ApiConfig, ExtendedTokenConfig } from '@/api/ethers';
import { polygonMumbai } from '@wagmi/core/chains';

import {
  ChainConfig,
  InvestmentConfig,
  PriceContractConfig,
} from '@/api/types';

export function getApiConfig(): ApiConfig {
  return {
    chainConfigs: [MUMBAI],
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

const MUMBAI: ChainConfig = {
  chain: polygonMumbai,
  subgraphUrl:
    'https://api.thegraph.com/subgraphs/name/medariox/origami-mumbai',
  urlBuilders: {
    transactionUrl: (hash) =>
      `${polygonMumbai.blockExplorers.etherscan}/tx/${hash}`,
    tokenUrl: (hash) =>
      `${polygonMumbai.blockExplorers.etherscan}/token/${hash}`,
  },
  origamiRpcUrl: 'https://polygon-testnet.public.blastapi.io',
};

const MUMBAI_PRICE_CONTRACT: PriceContractConfig = {
  address: '0x303125Ce3D60C9B6C4CA3d6f034aD4CeedE708b3',
  chainId: MUMBAI.chain.id,
};

const GMX_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x3553F668a936758bA9edff93D35D9903802196A4',
    chainId: MUMBAI.chain.id,
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
    'https://mumbai.polygonscan.com/address/0xd085fe61150Ed7C721E9a4cCe891e35Bf5483148',
};

const GLP_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x8f92595Ba9cFBF941838e158bf35244eBF401E99',
    chainId: MUMBAI.chain.id,
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
    'https://mumbai.polygonscan.com/address/0x09317dcf1450b62E8aa092d680fee7905CeCC99f',
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
  address: '0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37',
  chainId: MUMBAI.chain.id,
  iconName: 'gmx',
  symbol: 'GMX',
  decimals: 18,
};

const OGMX_TOKEN: ExtendedTokenConfig = {
  address: '0x56561230c92e9bDD97b33Cc6cA76F30b32F54a8A',
  chainId: MUMBAI.chain.id,
  iconName: 'gmx',
  symbol: 'oGMX',
  decimals: 18,
};

const SGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02',
  chainId: MUMBAI.chain.id,
  iconName: 'glp',
  symbol: 'sGLP',
  decimals: 18,
};

const OGLP_TOKEN: ExtendedTokenConfig = {
  address: '0xe8A3f2005fc81773D5CAA647722478bDc94E8296',
  chainId: MUMBAI.chain.id,
  iconName: 'glp',
  symbol: 'oGLP',
  decimals: 18,
};

const BTC_TOKEN: ExtendedTokenConfig = {
  address: '0x0D345CF1b62901A4c5BBE65810f1dB2513a2284A',
  chainId: MUMBAI.chain.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BTC',
  decimals: 18,
};

const BNB_TOKEN: ExtendedTokenConfig = {
  address: '0x6b047bd68cA46bdCFa75e68DbD9Aca74c4d32C56',
  chainId: MUMBAI.chain.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BNB',
  decimals: 18,
};

const DAI_TOKEN: ExtendedTokenConfig = {
  address: '0x4451564f1e9E8487203769B0581173ef776B9116',
  chainId: MUMBAI.chain.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'DAI',
  decimals: 18,
};

const WETH_TOKEN: ExtendedTokenConfig = {
  address: '0x851dCde48989F1C6dc56e1272117A317a80dFE67',
  chainId: MUMBAI.chain.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WETH',
  decimals: 18,
};
