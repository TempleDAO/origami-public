// sepolia: ORACLES.DAI_USD=0x2117ACfE78fac4Bf58021dC73AF60a1997EEBD8b
// yarn hardhat verify --network sepolia 0x2117ACfE78fac4Bf58021dC73AF60a1997EEBD8b --constructor-args scripts/deploys/sepolia/deploymentArgs/0x2117ACfE78fac4Bf58021dC73AF60a1997EEBD8b.js
module.exports = [
  "0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526",
  "DAI/USD",
  "0x50B44A8e5f299A453Fc7d8862Ffa09A248274817",
  18,
  "0x000000000000000000000000000000000000115d",
  18,
  "1000000000000000000",
  "0x3c978bA11E9ff892334F65bAbAe26321f84C5EF3",
  87300,
  {
    "floor": "990000000000000000",
    "ceiling": "1010000000000000000"
  }
];