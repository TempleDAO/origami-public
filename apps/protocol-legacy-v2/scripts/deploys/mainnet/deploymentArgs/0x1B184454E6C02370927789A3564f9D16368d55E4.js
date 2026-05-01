// mainnet: ORACLES.STETH_WETH=0x1B184454E6C02370927789A3564f9D16368d55E4
// yarn hardhat verify --network mainnet 0x1B184454E6C02370927789A3564f9D16368d55E4 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x1B184454E6C02370927789A3564f9D16368d55E4.js
module.exports = [
  "0xb20AaE0Fe007519b7cE6f090a2aB8353B3Da5d80",
  {
    "description": "stETH/wETH",
    "baseAssetAddress": "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "quoteAssetDecimals": 18
  },
  "1000000000000000000",
  "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",
  86700,
  {
    "floor": "997000000000000000",
    "ceiling": "1003000000000000000"
  },
  true
];