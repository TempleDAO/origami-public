// mainnet: ORACLES.WEETH_WETH=0xE0Db69920e90CA56E29F71b7F566655De923c32B
// yarn hardhat verify --network mainnet 0xE0Db69920e90CA56E29F71b7F566655De923c32B --constructor-args scripts/deploys/mainnet/deploymentArgs/0xE0Db69920e90CA56E29F71b7F566655De923c32B.js
module.exports = [
  "0xb20AaE0Fe007519b7cE6f090a2aB8353B3Da5d80",
  {
    "description": "weETH/wETH",
    "baseAssetAddress": "0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "quoteAssetDecimals": 18
  },
  "0x8751F736E94F6CD167e8C5B97E245680FbD9CC36",
  86700,
  30,
  "0x308861A430be4cce5502d0A12724771Fc6DaF216"
];