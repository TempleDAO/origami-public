// sepolia: EXTERNAL.REDSTONE.SUSDE_USD_ORACLE=0xdafFc8AA780213B8F828DdAE75fCe0900b773e38
// yarn hardhat verify --network sepolia 0xdafFc8AA780213B8F828DdAE75fCe0900b773e38 --constructor-args scripts/deploys/sepolia/deploymentArgs/0xdafFc8AA780213B8F828DdAE75fCe0900b773e38.js
module.exports = [
  "sUSDe/USD",
  {
    "roundId": 1,
    "answer": "103728410",
    "startedAt": 0,
    "updatedAt": 1711527420,
    "answeredInRound": 1
  },
  8
];