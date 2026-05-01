// mainnet: ORACLES.WETH_DAI=0xc9A161601B76C0333dCa022efd45b2549396B8b9
// yarn hardhat verify --network mainnet 0xc9A161601B76C0333dCa022efd45b2549396B8b9 --constructor-args scripts/deploys/mainnet/deploymentArgs/0xc9A161601B76C0333dCa022efd45b2549396B8b9.js
module.exports = [
  {
    "description": "wETH/DAI",
    "baseAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    "quoteAssetDecimals": 18
  },
  "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
  3900,
  true
];