// mainnet: ORACLES.SUSDE_USD_INTERNAL=0x943F1e9dE4508e9eb6863A10697B26D3678A2A52
// yarn hardhat verify --network mainnet 0x943F1e9dE4508e9eb6863A10697B26D3678A2A52 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x943F1e9dE4508e9eb6863A10697B26D3678A2A52.js
module.exports = [
  {
    "description": "sUSDe/USD",
    "baseAssetAddress": "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x000000000000000000000000000000000000115d",
    "quoteAssetDecimals": 18
  },
  "0x0000000000000000000000000000000000000000"
];