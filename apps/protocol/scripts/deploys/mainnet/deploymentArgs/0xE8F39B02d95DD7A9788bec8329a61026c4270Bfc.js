// mainnet: ORACLES.WETH_CBBTC=0xE8F39B02d95DD7A9788bec8329a61026c4270Bfc
// yarn hardhat verify --network mainnet 0xE8F39B02d95DD7A9788bec8329a61026c4270Bfc --constructor-args scripts/deploys/mainnet/deploymentArgs/0xE8F39B02d95DD7A9788bec8329a61026c4270Bfc.js
module.exports = [
  {
    "description": "WETH/cbBTC",
    "baseAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
    "quoteAssetDecimals": 8
  },
  "0xAc559F25B1619171CbC396a50854A3240b6A4e99",
  3900,
  true,
  true
];