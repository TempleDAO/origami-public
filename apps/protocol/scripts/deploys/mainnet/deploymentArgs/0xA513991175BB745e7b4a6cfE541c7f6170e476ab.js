// mainnet: ORACLES.USD0pp_USD0=0xA513991175BB745e7b4a6cfE541c7f6170e476ab
// yarn hardhat verify --network mainnet 0xA513991175BB745e7b4a6cfE541c7f6170e476ab --constructor-args scripts/deploys/mainnet/deploymentArgs/0xA513991175BB745e7b4a6cfE541c7f6170e476ab.js
module.exports = [
  "0xb20AaE0Fe007519b7cE6f090a2aB8353B3Da5d80",
  {
    "description": "USD0++/USD0",
    "baseAssetAddress": "0x35D8949372D46B7a3D5A56006AE77B215fc69bC0",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x73A15FeD60Bf67631dC6cd7Bc5B6e8da8190aCF5",
    "quoteAssetDecimals": 18
  },
  "0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52",
  {
    "floor": "990000000000000000",
    "ceiling": "100000000000000000000"
  }
];