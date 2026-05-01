// sepolia: EXTERNAL.CHAINLINK.USDC_USD_ORACLE=0x712841C85E296Eb3e52e5b935bA9C6F038b58De4
// yarn hardhat verify --network sepolia 0x712841C85E296Eb3e52e5b935bA9C6F038b58De4 --constructor-args scripts/deploys/sepolia/deploymentArgs/0x712841C85E296Eb3e52e5b935bA9C6F038b58De4.js
module.exports = [
  "USDC/USD",
  {
    "roundId": 1,
    "answer": 100006620,
    "startedAt": 0,
    "updatedAt": 0,
    "answeredInRound": 1
  },
  8
];