// sepolia: EXTERNAL.CHAINLINK.ETH_USD_ORACLE=0x67E1C43325D1d27FA60f4D580171C0334688C581
// yarn hardhat verify --network sepolia 0x67E1C43325D1d27FA60f4D580171C0334688C581 --constructor-args scripts/deploys/sepolia/deploymentArgs/0x67E1C43325D1d27FA60f4D580171C0334688C581.js
module.exports = [
  "ETH/USD",
  {
    "roundId": 1,
    "answer": 100006620,
    "startedAt": 0,
    "updatedAt": 0,
    "answeredInRound": 1
  },
  8
];