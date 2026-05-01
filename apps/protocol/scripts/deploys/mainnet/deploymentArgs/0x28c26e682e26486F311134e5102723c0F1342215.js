// mainnet: ORACLES.EZETH_WETH=0x28c26e682e26486F311134e5102723c0F1342215
// yarn hardhat verify --network mainnet 0x28c26e682e26486F311134e5102723c0F1342215 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x28c26e682e26486F311134e5102723c0F1342215.js
module.exports = [
  "0xb20AaE0Fe007519b7cE6f090a2aB8353B3Da5d80",
  {
    "description": "ezETH/wETH",
    "baseAssetAddress": "0xbf5495Efe5DB9ce00f80364C8B423567e58d2110",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "quoteAssetDecimals": 18
  },
  "0xF4a3e183F59D2599ee3DF213ff78b1B3b1923696",
  43500,
  30,
  "0x74a09653A083691711cF8215a6ab074BB4e99ef5"
];