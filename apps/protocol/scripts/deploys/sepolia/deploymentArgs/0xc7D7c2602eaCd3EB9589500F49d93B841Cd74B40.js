// sepolia: EXTERNAL.CHAINLINK.STETH_ETH_ORACLE=0xc7D7c2602eaCd3EB9589500F49d93B841Cd74B40
// yarn hardhat verify --network sepolia 0xc7D7c2602eaCd3EB9589500F49d93B841Cd74B40 --constructor-args scripts/deploys/sepolia/deploymentArgs/0xc7D7c2602eaCd3EB9589500F49d93B841Cd74B40.js
module.exports = [
  "STETH/ETH",
  {
    "roundId": 1,
    "answer": "999498580736552700",
    "startedAt": 0,
    "updatedAt": 1710561516,
    "answeredInRound": 1
  },
  18
];