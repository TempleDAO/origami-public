// mainnet: ORACLES.WETH_SDAI=0x075766cB4eFcFF684FeCa227C80546F30B8de783
// yarn hardhat verify --network mainnet 0x075766cB4eFcFF684FeCa227C80546F30B8de783 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x075766cB4eFcFF684FeCa227C80546F30B8de783.js
module.exports = [
  {
    "description": "wETH/sDAI",
    "baseAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
    "quoteAssetDecimals": 18
  },
  "0xc9A161601B76C0333dCa022efd45b2549396B8b9",
  "0x55f84cD659c0C1A6BC225F5cE9016Ad591B49ceD",
  "0x10400DF986C4E5C295e889b114644b75A5657337"
];