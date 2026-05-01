// mainnet: ORACLES.SDAI_SUSDE=0x73DCA51d16711dbE50212c50e80675B60CADb184
// yarn hardhat verify --network mainnet 0x73DCA51d16711dbE50212c50e80675B60CADb184 --constructor-args scripts/deploys/mainnet/deploymentArgs/0x73DCA51d16711dbE50212c50e80675B60CADb184.js
module.exports = [
  {
    "description": "sDAI/sUSDe",
    "baseAssetAddress": "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
    "baseAssetDecimals": 18,
    "quoteAssetAddress": "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497",
    "quoteAssetDecimals": 18
  },
  "0xEc875016b442597d9ad7843B663Cec6c12fEA233",
  "0x943F1e9dE4508e9eb6863A10697B26D3678A2A52",
  "0x0000000000000000000000000000000000000000"
];