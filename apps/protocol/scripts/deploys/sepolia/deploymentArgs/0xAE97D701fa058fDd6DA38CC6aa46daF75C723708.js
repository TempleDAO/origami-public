// sepolia: EXTERNAL.CHAINLINK.ETH_USD_ORACLE=0xAE97D701fa058fDd6DA38CC6aa46daF75C723708
// yarn hardhat verify --network sepolia 0xAE97D701fa058fDd6DA38CC6aa46daF75C723708 --constructor-args scripts/deploys/sepolia/deploymentArgs/0xAE97D701fa058fDd6DA38CC6aa46daF75C723708.js
module.exports = [
  "ETH/USD",
  {
    "roundId": 1,
    "answer": "2500000000000000000000",
    "startedAt": 0,
    "updatedAt": 1710561564,
    "answeredInRound": 1
  },
  18
];