// mainnet: ORACLES.SDAI_USDC=0x690939cf345793BD7950915F84ADbd1AEBCFa9a3
// yarn hardhat verify --network mainnet 0x690939cf345793BD7950915F84ADbd1AEBCFa9a3 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x690939cf345793BD7950915F84ADbd1AEBCFa9a3.js
module.exports = [
  {
    "description": "sDAI/USDC",
    "baseAssetAddress": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "quoteAssetDecimals": 6
  },
  "0x0000000000000000000000000000000000000000"
];