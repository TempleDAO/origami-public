// mainnet: ORACLES.USD0pp_USDC_MARKET_PRICE=0x48ba243c871bab14713A8147FB35a98B243eD4BB
// yarn hardhat verify --network mainnet 0x48ba243c871bab14713A8147FB35a98B243eD4BB --constructor-args scripts/deploys/mainnet/deploymentArgs/0x48ba243c871bab14713A8147FB35a98B243eD4BB.js
module.exports = [
  {
    "description": "USD0++/USDC (market price)",
    "baseAssetAddress": "0x35D8949372D46B7a3D5A56006AE77B215fc69bC0",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "quoteAssetDecimals": 6
  },
  "0xFC9e30Cf89f8A00dba3D34edf8b65BCDAdeCC1cB",
  86700,
  true,
  true
];