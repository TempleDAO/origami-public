// berachain: ORACLES.ORIBGT_WBERA_PEGGED=0x18A9000d8b947ea3005e61e8bAAaDAeAeA7ccEAB
// yarn hardhat verify --network berachain 0x18A9000d8b947ea3005e61e8bAAaDAeAeA7ccEAB --constructor-args scripts/deploys/berachain/deploymentArgs/0x18A9000d8b947ea3005e61e8bAAaDAeAeA7ccEAB.js
module.exports = [
  {
    "description": "oriBGT/WBERA (fixed 1:1)",
    "baseAssetAddress": "0x69f1E971257419B1E9C405A553f252c64A29A30a",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x6969696969696969696969696969696969696969",
    "quoteAssetDecimals": 18
  },
  "1000000000000000000",
  "0x0000000000000000000000000000000000000000"
];