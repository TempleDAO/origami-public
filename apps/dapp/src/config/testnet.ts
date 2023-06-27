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
  address: '0xfB720eAa483beF207400D6561b5E17b8d6f2BB2f',
  chainId: MUMBAI.id,
};

const GMX_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0x084E1ceB358Fc9A78BB2799424A407419F28F3cf',
    chainId: MUMBAI.id,
  },
  icon: 'gmx',
  name: 'ovGMX',
  description: "GMX's utility and governance token (GMX)",
  supportedAssetsDescription: 'GMX',
  info: `
  Users deposit GMX and receive proportional ovGMX vault shares.
  \n
  The ovGMX price per GMX will gradually rise, as GMX staking rewards are harvested and auto-compounded daily into vault reserves.
  \n
  The GMX vault yield is further boosted from staking GMX's esGMX and multiplier point rewards.
  `,
};

const GLP_ON_MUMBAI: InvestmentConfig = {
  contractAddress: {
    address: '0xE781bF69e3dfaB3E7161B3f718897BcbDE17539a',
    chainId: MUMBAI.id,
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
  The ovGMX price per GLP will gradually rise, as GLP staking rewards are harvested and auto-compounded daily into vault reserves. 
  \n
  Users may exit the vault directly into staked GLP or into one of the [underlying GLP assets](https://app.gmx.io/#/buy_glp)
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
  address: '0x79264843745dD81127B42Cffe30584A11a08C8F5',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'GMX',
  decimals: 18,
};

const OGMX_TOKEN: ExtendedTokenConfig = {
  address: '0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61',
  chainId: MUMBAI.id,
  iconName: 'gmx',
  symbol: 'oGMX',
  decimals: 18,
};

const SGLP_TOKEN: ExtendedTokenConfig = {
  address: '0x947d2B5ADc3882FA5D4E86E065f7340a5465Dd91',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'sGLP',
  decimals: 18,
};

const OGLP_TOKEN: ExtendedTokenConfig = {
  address: '0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded',
  chainId: MUMBAI.id,
  iconName: 'glp',
  symbol: 'oGLP',
  decimals: 18,
};

const BTC_TOKEN: ExtendedTokenConfig = {
  address: '0xc8Daa4E13780E59B50150980beF3469B7E0Cff25',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BTC',
  decimals: 8,
};

const BNB_TOKEN: ExtendedTokenConfig = {
  address: '0xDAAe5236C1b4cE822ac5beDDb597e8a6E0604b4e',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'BNB',
  decimals: 18,
};

const DAI_TOKEN: ExtendedTokenConfig = {
  address: '0x133B3e03B9164d846204Bf1B7780F948c95A36Ea',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'DAI',
  decimals: 18,
};

const WETH_TOKEN: ExtendedTokenConfig = {
  address: '0xaDA4020481b166219DE50884dD710b3aD18573e4',
  chainId: MUMBAI.id,
  iconName: 'error', // TODO: create icon when needed
  symbol: 'WETH',
  decimals: 18,
};
