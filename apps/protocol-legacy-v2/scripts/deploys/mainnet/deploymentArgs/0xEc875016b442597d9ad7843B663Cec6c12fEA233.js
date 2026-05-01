// mainnet: ORACLES.SDAI_USD_INTERNAL=0xEc875016b442597d9ad7843B663Cec6c12fEA233
// yarn hardhat verify --network mainnet 0xEc875016b442597d9ad7843B663Cec6c12fEA233 --constructor-args scripts/deploys/mainnet/deploymentArgs/0xEc875016b442597d9ad7843B663Cec6c12fEA233.js
module.exports = [
  {
    "description": "sDAI/USD",
    "baseAssetAddress": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x000000000000000000000000000000000000115d",
    "quoteAssetDecimals": 18
  },
  "0x0000000000000000000000000000000000000000"
];