// mainnet: ORACLES.WBTC_DAI=0xAeDDad15BE7428D8c53a217Da6e245701e22D2d1
// yarn hardhat verify --network mainnet 0xAeDDad15BE7428D8c53a217Da6e245701e22D2d1 --constructor-args scripts/deploys/mainnet/deploymentArgs/0xAeDDad15BE7428D8c53a217Da6e245701e22D2d1.js
module.exports = [
  {
    "description": "wBTC/DAI",
    "baseAssetAddress": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    "baseAssetDecimals": 8,
    "quoteAssetAddress": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    "quoteAssetDecimals": 18
  },
  "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
  3900,
  true
];