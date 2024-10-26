// mainnet: ORACLES.WOETH_WETH=0x9d492B172eF372c33E63FfD867E7A534DDCd62Fb
// yarn hardhat verify --network mainnet 0x9d492B172eF372c33E63FfD867E7A534DDCd62Fb --constructor-args scripts/deploys/mainnet/deploymentArgs/0x9d492B172eF372c33E63FfD867E7A534DDCd62Fb.js
module.exports = [
  {
    "description": "woETH/wETH",
    "baseAssetAddress": "0xDcEe70654261AF21C44c093C300eD3Bb97b78192",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "quoteAssetDecimals": 18
  },
  "0x0000000000000000000000000000000000000000"
];