// sepolia: EXTERNAL.CHAINLINK.ETH_USD_ORACLE=0xb28b54D9674c11a05B267120B507321d42B6702f
// yarn hardhat verify --network sepolia 0xb28b54D9674c11a05B267120B507321d42B6702f --constructor-args scripts/deploys/sepolia/deploymentArgs/0xb28b54D9674c11a05B267120B507321d42B6702f.js
module.exports = [
  "ETH/USD",
  {
    "roundId": 1,
    "answer": "2500000000000000000000",
    "startedAt": 0,
    "updatedAt": 1710824592,
    "answeredInRound": 1
  },
  8
];