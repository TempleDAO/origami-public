// mainnet: ORACLES.USD0pp_USDC_FLOOR_PRICE=0x9A88075d4cB5aa45eC5417a648F23ddA15f7c2cD
// yarn hardhat verify --network mainnet 0x9A88075d4cB5aa45eC5417a648F23ddA15f7c2cD --constructor-args scripts/deploys/mainnet/deploymentArgs/0x9A88075d4cB5aa45eC5417a648F23ddA15f7c2cD.js
module.exports = [
  {
    "description": "USD0++/USDC (floor price)",
    "baseAssetAddress": "0x35D8949372D46B7a3D5A56006AE77B215fc69bC0",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "quoteAssetDecimals": 6
  },
  "0x36d70e02e96897CE2002313CB7ea55FffDf074FC",
  0,
  false,
  false
];