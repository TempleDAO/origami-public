// mainnet: ORACLES.USD0_USDC=0x6668daECe8FeB73d186c543fFC162694b847BE99
// yarn hardhat verify --network mainnet 0x6668daECe8FeB73d186c543fFC162694b847BE99 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x6668daECe8FeB73d186c543fFC162694b847BE99.js
module.exports = [
  "0xb20AaE0Fe007519b7cE6f090a2aB8353B3Da5d80",
  {
    "description": "USD0/USDC",
    "baseAssetAddress": "0x73A15FeD60Bf67631dC6cd7Bc5B6e8da8190aCF5",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "quoteAssetDecimals": 6
  },
  "0x14100f81e33C33Ecc7CDac70181Fb45B6E78569F",
  {
    "floor": "990000000000000000",
    "ceiling": "1010000000000000000"
  }
];