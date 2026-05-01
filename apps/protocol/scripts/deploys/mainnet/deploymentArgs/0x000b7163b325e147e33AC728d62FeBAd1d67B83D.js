// mainnet: ORACLES.WETH_WBTC=0x000b7163b325e147e33AC728d62FeBAd1d67B83D
// yarn hardhat verify --network mainnet 0x000b7163b325e147e33AC728d62FeBAd1d67B83D --constructor-args scripts/deploys/mainnet/deploymentArgs/0x000b7163b325e147e33AC728d62FeBAd1d67B83D.js
module.exports = [
  {
    "description": "wETH/wBTC",
    "baseAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    "quoteAssetDecimals": 8
  },
  "0xAc559F25B1619171CbC396a50854A3240b6A4e99",
  3900,
  true
];