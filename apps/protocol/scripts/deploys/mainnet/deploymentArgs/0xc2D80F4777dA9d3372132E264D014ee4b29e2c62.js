// mainnet: ORACLES.WBTC_SDAI=0xc2D80F4777dA9d3372132E264D014ee4b29e2c62
// yarn hardhat verify --network mainnet 0xc2D80F4777dA9d3372132E264D014ee4b29e2c62 --constructor-args scripts/deploys/mainnet/deploymentArgs/0xc2D80F4777dA9d3372132E264D014ee4b29e2c62.js
module.exports = [
  {
    "description": "wBTC/sDAI",
    "baseAssetAddress": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    "baseAssetDecimals": 8,
    "quoteAssetAddress": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
    "quoteAssetDecimals": 18
  },
  "0xAeDDad15BE7428D8c53a217Da6e245701e22D2d1",
  "0x55f84cD659c0C1A6BC225F5cE9016Ad591B49ceD",
  "0x10400DF986C4E5C295e889b114644b75A5657337"
];