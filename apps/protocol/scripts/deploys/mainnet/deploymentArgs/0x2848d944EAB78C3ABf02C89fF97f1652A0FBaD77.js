// mainnet: ORACLES.WSTETH_WETH=0x2848d944EAB78C3ABf02C89fF97f1652A0FBaD77
// yarn hardhat verify --network mainnet 0x2848d944EAB78C3ABf02C89fF97f1652A0FBaD77 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x2848d944EAB78C3ABf02C89fF97f1652A0FBaD77.js
module.exports = [
  {
    "description": "wstETH/wETH",
    "baseAssetAddress": "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "quoteAssetDecimals": 18
  },
  "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
  "0x1B184454E6C02370927789A3564f9D16368d55E4"
];