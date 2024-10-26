pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library OrigamiAaveV3BorrowAndLendConstants {
    // address public constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    
    // aave v3 pool
    address internal constant SPARK_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    uint8 public constant SPARK_EMODE_NOT_ENABLED = 0; // No emode for wBTC/DAI market

    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    
    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant RETH_ADDRESS = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDC_WHALE = 0xD6153F5af5679a75cC85D8974463545181f48772;

    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
}
