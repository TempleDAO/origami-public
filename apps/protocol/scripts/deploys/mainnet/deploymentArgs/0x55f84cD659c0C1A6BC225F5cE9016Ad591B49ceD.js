// mainnet: ORACLES.SDAI_DAI=0x55f84cD659c0C1A6BC225F5cE9016Ad591B49ceD
// yarn hardhat verify --network mainnet 0x55f84cD659c0C1A6BC225F5cE9016Ad591B49ceD --constructor-args scripts/deploys/mainnet/deploymentArgs/0x55f84cD659c0C1A6BC225F5cE9016Ad591B49ceD.js
module.exports = [
  {
    "description": "sDAI/DAI",
    "baseAssetAddress": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    "quoteAssetDecimals": 18
  },
  "0x0000000000000000000000000000000000000000"
];