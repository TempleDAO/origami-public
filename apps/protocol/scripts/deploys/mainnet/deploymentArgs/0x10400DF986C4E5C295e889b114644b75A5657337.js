// mainnet: ORACLES.DAI_USD=0x10400DF986C4E5C295e889b114644b75A5657337
// yarn hardhat verify --network mainnet 0x10400DF986C4E5C295e889b114644b75A5657337 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x10400DF986C4E5C295e889b114644b75A5657337.js
module.exports = [
  "0xb20AaE0Fe007519b7cE6f090a2aB8353B3Da5d80",
  {
    "description": "DAI/USD",
    "baseAssetAddress": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x000000000000000000000000000000000000115d",
    "quoteAssetDecimals": 18
  },
  "1000000000000000000",
  "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9",
  3900,
  {
    "floor": "990000000000000000",
    "ceiling": "999000000000000000000"
  },
  true
];