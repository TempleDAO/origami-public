import { ApiConfig, ExtendedTokenConfig } from '@/api/ethers';
import {
  ChainConfig,
  InvestmentConfig,
  PriceContractConfig,
} from '@/api/types';

export function getApiConfig(): ApiConfig {
  return {
    chains: [MUMBAI],
    tokens: [
      GMX_TOKEN,
      SGLP_TOKEN,
      OSGMX_TOKEN,
      OSGLP_TOKEN,
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
};

const MUMBAI_PRICE_CONTRACT: PriceContractConfig = {
  address: '0x303125Ce3D60C9B6C4CA3d6f034aD4CeedE708b3',
  chainId: MUMBAI.id,
};

const GMX_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x02aE0A50234Df57E094684B02B35c4CF1b88cC63',
    chainId: MUMBAI.id,
  },
  icon: 'gmx',
  name: 'osGMX',
  description: 'Origami wrapper for the GMX utility token',
  info: `
  Info on the GMX investment. Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book.
  `,
  moreInfoUrl:
    'https://mumbai.polygonscan.com/address/0x02aE0A50234Df57E094684B02B35c4CF1b88cC63',
};

const GLP_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x22662bBa4e2b7b1E674F37D8013Fe245d278abce',
    chainId: MUMBAI.id,
  },
  icon: 'glp',
  name: 'osGLP',
  description: 'Origami wrapper for the GMX liquidity provider token',
  info: `
  Info on the GLP investment. Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book.
  `,
  moreInfoUrl:
    'https://mumbai.polygonscan.com/address/0x22662bBa4e2b7b1E674F37D8013Fe245d278abce',
};

const OSGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x22662bBa4e2b7b1E674F37D8013Fe245d278abce',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'osGLP',
  decimals: 18,
};

const OSGMX_TOKEN: ExtendedTokenConfig = {
  address: '0x02aE0A50234Df57E094684B02B35c4CF1b88cC63',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'osGMX',
  decimals: 18,
};

const GMX_TOKEN: ExtendedTokenConfig = {
  address: '0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'GMX',
  decimals: 18,
};

const OGMX_TOKEN: ExtendedTokenConfig = {
  address: '0xBCd6BA024a179Dfd441CF2418c687e80F1AeAf0D',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'oGMX',
  decimals: 18,
};

const SGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x8Dc53cd512cbA18635B8C0b4f9d0a0ea4ce5AA02',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'sGLP',
  decimals: 18,
};

const OGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x6e78520fd07591B459AA3a4F8B4474215C7C8aF7',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'oGLP',
  decimals: 18,
};

const BTC_TOKEN: ExtendedTokenConfig = {
  address: '0x0D345CF1b62901A4c5BBE65810f1dB2513a2284A',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BTC',
  decimals: 18,
};

const BNB_TOKEN: ExtendedTokenConfig = {
  address: '0x6b047bd68cA46bdCFa75e68DbD9Aca74c4d32C56',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BNB',
  decimals: 18,
};

const DAI_TOKEN: ExtendedTokenConfig = {
  address: '0x4451564f1e9E8487203769B0581173ef776B9116',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'DAI',
  decimals: 18,
};

const WETH_TOKEN: ExtendedTokenConfig = {
  address: '0x851dCde48989F1C6dc56e1272117A317a80dFE67',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WETH',
  decimals: 18,
};
