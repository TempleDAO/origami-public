// mainnet: ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION=0xfc50DDE4d7dF9da9410b93E2Cc8d6b4e2d3dAAd2
// yarn hardhat verify --network mainnet 0xfc50DDE4d7dF9da9410b93E2Cc8d6b4e2d3dAAd2 --constructor-args scripts/deploys/mainnet/deploymentArgs/0xfc50DDE4d7dF9da9410b93E2Cc8d6b4e2d3dAAd2.js
module.exports = [
  {
    "description": "USD0++ Morpho to Market conversion",
    "baseAssetAddress": "0x0000000000000000000000000000000000000000",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x0000000000000000000000000000000000000000",
    "quoteAssetDecimals": 18
  },
  "1000000000000000000",
  "0x0000000000000000000000000000000000000000"
];