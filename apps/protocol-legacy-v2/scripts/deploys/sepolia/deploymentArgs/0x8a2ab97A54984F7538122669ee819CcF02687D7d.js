// sepolia: EXTERNAL.REDSTONE.USDE_USD_ORACLE=0x8a2ab97A54984F7538122669ee819CcF02687D7d
// yarn hardhat verify --network sepolia 0x8a2ab97A54984F7538122669ee819CcF02687D7d --constructor-args scripts/deploys/sepolia/deploymentArgs/0x8a2ab97A54984F7538122669ee819CcF02687D7d.js
module.exports = [
  "USDe/USD",
  {
    "roundId": 1,
    "answer": "100159255",
    "startedAt": 0,
    "updatedAt": 1711527384,
    "answeredInRound": 1
  },
  8
];