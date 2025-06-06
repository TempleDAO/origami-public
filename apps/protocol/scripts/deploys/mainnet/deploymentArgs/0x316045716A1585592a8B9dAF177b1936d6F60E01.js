// mainnet: ORACLES.MKR_USDS=0x316045716A1585592a8B9dAF177b1936d6F60E01
// yarn hardhat verify --network mainnet 0x316045716A1585592a8B9dAF177b1936d6F60E01 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x316045716A1585592a8B9dAF177b1936d6F60E01.js
module.exports = [
  {
    "description": "MKR/USDS",
    "baseAssetAddress": "0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xdC035D45d973E3EC169d2276DDab16f1e407384F",
    "quoteAssetDecimals": 18
  },
  "0xec1D1B3b0443256cc3860e24a46F108e699484Aa",
  3900,
  true,
  true
];