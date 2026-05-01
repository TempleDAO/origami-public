pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { IKodiakV3Pool } from "contracts/interfaces/external/kodiak/IKodiakV3Pool.sol";
import { IKodiakIsland } from "contracts/interfaces/external/kodiak/IKodiakIsland.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

contract TokenPricesTestBase is OrigamiTest {
    TokenPrices internal tokenPrices;

    function setUp() public virtual {
        tokenPrices = new TokenPrices(30);
    }
}

contract TokenPricesTestAdmin is TokenPricesTestBase {
    event TokenPriceFunctionSet(address indexed token, bytes fnCalldata);

    function test_init() public view {
        assertEq(tokenPrices.decimals(), 30);
    }

    function test_setTokenPriceFunction_once() public {
        address token = address(1);
        bytes memory fnData = abi.encodeCall(tokenPrices.scalar, (69.420e30));

        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token, fnData);
        tokenPrices.setTokenPriceFunction(token, fnData);

        assertEq(tokenPrices.priceFnCalldata(token), fnData);
        assertEq(tokenPrices.mappedTokenAt(0), token);
        assertEq(tokenPrices.numMappedTokens(), 1);
        address[] memory tokens = tokenPrices.allMappedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token);
        assertEq(tokenPrices.tokenPrice(token), 69.420e30);
        uint256[] memory prices = tokenPrices.tokenPrices(tokens);
        assertEq(prices.length, 1);
        assertEq(prices[0], 69.420e30);
    }

    function test_setTokenPriceFunction_multi() public {
        address token1 = address(1);
        address token2 = address(2);
        bytes memory fnData = abi.encodeCall(tokenPrices.scalar, (69.420e30));

        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token1, fnData);
        tokenPrices.setTokenPriceFunction(token1, fnData);

        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token2, fnData);
        tokenPrices.setTokenPriceFunction(token2, fnData);

        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token1, abi.encodeCall(tokenPrices.scalar, (123e30)));
        tokenPrices.setTokenPriceFunction(token1, abi.encodeCall(tokenPrices.scalar, (123e30)));

        assertEq(tokenPrices.priceFnCalldata(token1), abi.encodeCall(tokenPrices.scalar, (123e30)));
        assertEq(tokenPrices.priceFnCalldata(token2), fnData);
        assertEq(tokenPrices.numMappedTokens(), 2);
        assertEq(tokenPrices.mappedTokenAt(0), token1);
        assertEq(tokenPrices.mappedTokenAt(1), token2);
        address[] memory tokens = tokenPrices.allMappedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);
        assertEq(tokenPrices.tokenPrice(token1), 123e30);
        assertEq(tokenPrices.tokenPrice(token2), 69.420e30);
        uint256[] memory prices = tokenPrices.tokenPrices(tokens);
        assertEq(prices.length, 2);
        assertEq(prices[0], 123e30);
        assertEq(prices[1], 69.420e30);
    }

    function test_setTokenPriceFunctions() public {
        address token1 = address(1);
        address token2 = address(2);
        bytes memory fnData = abi.encodeCall(tokenPrices.scalar, (69.420e30));

        TokenPrices.PriceMapping[] memory mappings = new TokenPrices.PriceMapping[](3);
        mappings[0] = TokenPrices.PriceMapping(token1, fnData);
        mappings[1] = TokenPrices.PriceMapping(token2, fnData);
        mappings[2] = TokenPrices.PriceMapping(token1, abi.encodeCall(tokenPrices.scalar, (123e30)));

        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token1, fnData);
        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token2, fnData);
        vm.expectEmit(address(tokenPrices));
        emit TokenPriceFunctionSet(token1, abi.encodeCall(tokenPrices.scalar, (123e30)));
        tokenPrices.setTokenPriceFunctions(mappings);

        assertEq(tokenPrices.priceFnCalldata(token1), abi.encodeCall(tokenPrices.scalar, (123e30)));
        assertEq(tokenPrices.priceFnCalldata(token2), fnData);
        assertEq(tokenPrices.numMappedTokens(), 2);
        assertEq(tokenPrices.mappedTokenAt(0), token1);
        assertEq(tokenPrices.mappedTokenAt(1), token2);
        address[] memory tokens = tokenPrices.allMappedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);
        assertEq(tokenPrices.tokenPrice(token1), 123e30);
        assertEq(tokenPrices.tokenPrice(token2), 69.420e30);
        uint256[] memory prices = tokenPrices.tokenPrices(tokens);
        assertEq(prices.length, 2);
        assertEq(prices[0], 123e30);
        assertEq(prices[1], 69.420e30);
    }
}

contract TokenPricesTestAccess is TokenPricesTestBase {
    function expectOnlyOwner() internal {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Ownable: caller is not the owner");
    }

    function test_setTokenPriceFunction_access() public {
        expectOnlyOwner();
        tokenPrices.setTokenPriceFunction(address(1), abi.encodeCall(tokenPrices.scalar, (69.420e30)));
    }
}

contract TokenPricesTestBerachain is TokenPricesTestBase {
    // https://app.kodiak.finance/#/liquidity/pools/0x564f011d557aad1ca09bfc956eb8a17c35d490e0?chain=berachain_mainnet
    IKodiakV3Pool internal WBERA_IBGT_POOL = IKodiakV3Pool(0x12bf773F18cEC56F14e7cb91d82984eF5A3148EE);
    IKodiakV3Pool internal WBERA_IBERA_POOL = IKodiakV3Pool(0xFCB24b3b7E87E3810b150d25D5964c566D9A2B6F);
    IKodiakV3Pool internal OHM_WBERA_POOL = IKodiakV3Pool(0x3445BC3099A8e06f0106CEb8F116D759A1b36Af9);
    IKodiakV3Pool internal OHM_HONEY_POOL = IKodiakV3Pool(0x75159c541BD49B1b6C51F5F3e796579e7CCCb071);
    IKodiakV3Pool internal BREAD_OHM_POOL = IKodiakV3Pool(0x5Bb06B78a434eD297CD474EbC79c28A20C20E5cD);

    IKodiakIsland internal WBERA_IBERA_ISLAND = IKodiakIsland(0xE3EeB9e48934634d8B5B39A0d15DD89eE0F969C4);
    IKodiakIsland internal OHM_HONEY_ISLAND = IKodiakIsland(0x98bDEEde9A45C28d229285d9d6e9139e9F505391);

    // https://app.redstone.finance/app/feeds/berachain/bera/
    address internal REDSTONE_BERA_USD_FEED = 0x29d2fEC890B037B2d34f061F9a50f76F85ddBcAE;
    address internal REDSTONE_HONEY_USD_FEED = 0x2D4f3199a80b848F3d094745F3Bbd4224892654e;

    address internal IBGT_TOKEN = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;
    address internal IBERA_TOKEN = 0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5;
    address internal WBERA_TOKEN = 0x6969696969696969696969696969696969696969;
    address internal HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address internal BYUSD_TOKEN = 0x688e72142674041f8f6Af4c808a4045cA1D6aC82;
    address internal OHM_TOKEN = 0x18878Df23e2a36f81e820e4b47b4A40576D3159C;

    IBalancerVault internal BALANCER_VAULT = IBalancerVault(0x4Be03f781C497A489E3cB0287833452cA9B9E80B);
    IBalancerBptToken internal BALANCER_HONEY_BYUSD_BPT = IBalancerBptToken(0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8);

    function setUp() public override {
        TokenPricesTestBase.setUp();
        fork("berachain_mainnet", 3429337);
    }

    function test_kodiakV3Price() public view {
        // WBERA per iBGT (iBGT/WBERA)
        assertEq(tokenPrices.kodiakV3Price(WBERA_IBGT_POOL, true), 0.649402242368059319001389387165e30);

        // iBGT per WBERA (WBERA/iBGT)
        assertEq(tokenPrices.kodiakV3Price(WBERA_IBGT_POOL, false), 1.539877651720878537037996215186e30);
    }

    function test_oraclePrice() public view {
        assertEq(tokenPrices.oraclePrice(REDSTONE_BERA_USD_FEED, 6 hours + 5 minutes), 3.86051522e30);
    }

    function test_ibgt_usd_cross() public {
        tokenPrices.setTokenPriceFunction(WBERA_TOKEN, abi.encodeCall(tokenPrices.oraclePrice, (REDSTONE_BERA_USD_FEED, 6 hours + 5 minutes)));
        tokenPrices.setTokenPriceFunction(IBGT_TOKEN, 
            abi.encodeCall(tokenPrices.mul, (
                abi.encodeCall(tokenPrices.tokenPrice, WBERA_TOKEN),
                abi.encodeCall(tokenPrices.kodiakV3Price, (WBERA_IBGT_POOL, false))
            ))
        );

        assertEq(tokenPrices.tokenPrice(WBERA_TOKEN), 3.86051522e30);
        assertEq(tokenPrices.tokenPrice(IBGT_TOKEN), 5.944721111406310784006518107027e30);
    }

    function test_kodiakIslandPrice_wbera_ibera() public {
        tokenPrices.setTokenPriceFunction(WBERA_TOKEN, abi.encodeCall(tokenPrices.oraclePrice, (REDSTONE_BERA_USD_FEED, 6 hours + 5 minutes)));
        tokenPrices.setTokenPriceFunction(IBERA_TOKEN, 
            abi.encodeCall(tokenPrices.mul, (
                abi.encodeCall(tokenPrices.tokenPrice, WBERA_TOKEN),
                abi.encodeCall(tokenPrices.kodiakV3Price, (WBERA_IBERA_POOL, false))
            ))
        );

        assertEq(tokenPrices.tokenPrice(WBERA_TOKEN), 3.86051522e30);
        assertEq(tokenPrices.tokenPrice(IBERA_TOKEN), 3.875849390061647110450658879604e30);
        assertEq(tokenPrices.kodiakIslandPrice(WBERA_IBERA_ISLAND), 0.527314422245838965547914616519e30);
    }

    function test_kodiakV3Price_non18dp() public view {
        // OHM-WBERA: token0=OHM (9dp), token1=BREAD (18dp)
        // OHM => WBERA
        assertEq(tokenPrices.kodiakV3Price(OHM_WBERA_POOL, true), 6.067581489857267420949388680356e30);
        // WBERA => OHM
        assertEq(tokenPrices.kodiakV3Price(OHM_WBERA_POOL, false), 0.164810312258949784772129444611e30);
        
        // BREAD-OHM: token0=BREAD (18dp), token1=OHM (9dp)
        // BREAD => OHM
        assertEq(tokenPrices.kodiakV3Price(BREAD_OHM_POOL, true), 0.180090609114754011213049871974e30);
        // OHM => BREAD
        assertEq(tokenPrices.kodiakV3Price(BREAD_OHM_POOL, false), 5.552760384983752664849921867655e30);
    }

    function test_kodiakIslandPrice_non18dp() public {
        tokenPrices.setTokenPriceFunction(HONEY_TOKEN, abi.encodeCall(tokenPrices.oraclePrice, (REDSTONE_HONEY_USD_FEED, 6 hours + 5 minutes)));
        tokenPrices.setTokenPriceFunction(OHM_TOKEN, 
            abi.encodeCall(tokenPrices.mul, (
                abi.encodeCall(tokenPrices.tokenPrice, HONEY_TOKEN),
                abi.encodeCall(tokenPrices.kodiakV3Price, (OHM_HONEY_POOL, true))
            ))
        );

        assertEq(tokenPrices.tokenPrice(HONEY_TOKEN), 1.00235409e30);
        assertEq(tokenPrices.tokenPrice(OHM_TOKEN), 23.508317222179071844060987056188e30);
        assertEq(tokenPrices.kodiakIslandPrice(OHM_HONEY_ISLAND), 197_857.970896186004948445002231117799e30);
    }

    function test_balancerV2BptPrice() public {
        tokenPrices.setTokenPriceFunction(HONEY_TOKEN, abi.encodeCall(tokenPrices.oraclePrice, (REDSTONE_HONEY_USD_FEED, 6 hours + 5 minutes)));
        tokenPrices.setTokenPriceFunction(BYUSD_TOKEN, abi.encodeCall(tokenPrices.scalar, 1e30));
        assertEq(tokenPrices.balancerV2BptPrice(BALANCER_VAULT, BALANCER_HONEY_BYUSD_BPT), 1.001620864826226683040726583251e30);
    }
}
