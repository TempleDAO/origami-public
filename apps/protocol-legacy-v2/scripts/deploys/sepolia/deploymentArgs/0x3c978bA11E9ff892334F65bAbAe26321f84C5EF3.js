// sepolia: EXTERNAL.CHAINLINK.DAI_USD_ORACLE=0x3c978bA11E9ff892334F65bAbAe26321f84C5EF3
// yarn hardhat verify --network sepolia 0x3c978bA11E9ff892334F65bAbAe26321f84C5EF3 --constructor-args scripts/deploys/sepolia/deploymentArgs/0x3c978bA11E9ff892334F65bAbAe26321f84C5EF3.js
module.exports = [
  "DAI/USD",
  {
    "roundId": 1,
    "answer": 100044127,
    "startedAt": 0,
    "updatedAt": 0,
    "answeredInRound": 1
  },
  8
];