pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/TokenPrices.sol)

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAggregatorV3Interface} from "../interfaces/external/chainlink/IAggregatorV3Interface.sol";
import {IGlpManager} from "../interfaces/external/gmx/IGlpManager.sol";
import {IGmxReader} from "../interfaces/external/gmx/IGmxReader.sol";
import {IGmxVault} from "../interfaces/external/gmx/IGmxVault.sol";
import {IUniswapV3Pool} from "../interfaces/external/uniswap/IUniswapV3Pool.sol";
import {IJoePair} from "../interfaces/external/traderJoe/IJoePair.sol";

import {CommonEventsAndErrors} from "./CommonEventsAndErrors.sol";
import {ITokenPrices} from "../interfaces/common/ITokenPrices.sol";
import {IRepricingToken} from "../interfaces/common/IRepricingToken.sol";

/// @title Token Prices
/// @notice A utility contract to pull token prices from on-chain.
/// @dev composable functions (uisng encoded function calldata) to build up price formulas
contract TokenPrices is ITokenPrices, Ownable {
    uint8 public immutable override decimals;
    
    /// @notice Token address to function calldata for how to lookup the price for this token
    mapping(address => bytes) public priceFnCalldata;

    error InvalidPrice(int256);
    error FailedPriceLookup(bytes fnCalldata);
    event TokenPriceFunctionSet(address indexed token, bytes fnCalldata);

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    /// @notice Map a token address to a function calldata defining how to retrieve the price
    function setTokenPriceFunction(address token, bytes calldata fnCalldata) external onlyOwner {
        emit TokenPriceFunctionSet(token, fnCalldata);
        priceFnCalldata[token] = fnCalldata;
    }

    /** TOKEN->PRICE LOOKUP FUNCTIONS */

    /// @notice Retrieve the price for a given token.
    /// @dev If not mapped, or an underlying error occurs, FailedPriceLookup will be thrown.
    function tokenPrice(address token) public override view returns (uint256 price) {
        return runPriceFunction(priceFnCalldata[token]);
    }

    /// @notice Retrieve the price for a list of tokens.
    /// @dev If any aren't mapped, or an underlying error occurs, FailedPriceLookup will be thrown.
    /// Not particularly gas efficient - wouldn't recommend to use on-chain
    function tokenPrices(address[] memory tokens) external override view returns (uint256[] memory prices) {
        prices = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            prices[i] = runPriceFunction(priceFnCalldata[tokens[i]]);
        }
    }

    /** EXTERNAL PRICE LOOKUPS */

    /// @notice Lookup the price of an oracle, scaled to `pricePrecision`
    function oraclePrice(address _oracle) public view returns (uint256 price) {
        IAggregatorV3Interface oracle = IAggregatorV3Interface(_oracle);
        (, int256 feedValue, , , ) = oracle.latestRoundData();
        if (feedValue < 0) revert InvalidPrice(feedValue);
        price = scaleToPrecision(uint256(feedValue), oracle.decimals());
    }

    /// @notice Fetch the Trader Joe pair price.
    /// Assumes the reserves are in 1e18 precision
    function traderJoePrice(IJoePair joePair, bool inQuotedOrder) public view returns (uint256) {
        (uint112 token0Reserve, uint112 token1Reserve,) = joePair.getReserves();
        if (inQuotedOrder) {
            return scaleToPrecision(uint256(token0Reserve) * 1e18 / token1Reserve, 18);
        } else {
            return scaleToPrecision(uint256(token1Reserve) * 1e18 / token0Reserve, 18);
        }
    }

    /// @notice Fetch the price from a univ3 pool, in quoted order (token0Price), to `pricePrecision`
    /// @dev https://docs.uniswap.org/sdk/guides/fetching-prices
    function univ3Price(IUniswapV3Pool pool, bool inQuotedOrder) public view returns (uint256) {
        // Pull the current price from the pool
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            
        // Use mulDiv as otherwise the calc would overflow.        
        // https://xn--2-umb.com/21/muldiv/index.html
        if (inQuotedOrder) {
            // price = sqrtPriceX96^2 / 2^192
            return Math.mulDiv(uint256(sqrtPriceX96) * sqrtPriceX96, 10 ** decimals, 1 << 192);
        } else {
            // price = 2^192 / sqrtPriceX96^2
            return Math.mulDiv(1 << 192, 10 ** decimals, sqrtPriceX96) / sqrtPriceX96;
        }
    }

    /// @notice Lookup the price of $GLP, scaled to `pricePrecision`
    /// @dev price = assets under management / glp supply
    /// GMX FE: https://github.com/gmx-io/gmx-interface/blob/98d20457aa313b9bac08b2b5cbb18486f598d8a0/src/pages/Dashboard/DashboardV2.js#L290-L291
    function glpPrice(IGlpManager glpManager) public view returns (uint256) {
        // Assets Under Management
        uint256[] memory aums = glpManager.getAums();
        uint256 avgAum = (aums[0] + aums[1]) / 2;
        uint256 glpSupply = IERC20(glpManager.glp()).totalSupply();

        if (avgAum != 0 && glpSupply != 0) {
            // GMX reports price to 30 dp
            return scaleToPrecision(avgAum * 1e18 / glpSupply, 30);
        } else {
            return 10 ** decimals;
        }
    }

    /// @notice Fetch the token price from the GMX Vault
    function gmxVaultPrice(address vault, address token) public view returns (uint256) {
        return scaleToPrecision(IGmxVault(vault).getMinPrice(token), 30);
    }

    /// @notice Calculate the Repricing Token price based
    /// on the [reserveToken price] * [reservesPerShare()]
    function repricingTokenPrice(address _repricingToken) public view returns (uint256) {
        IRepricingToken repricingToken = IRepricingToken(_repricingToken);
        return tokenPrice(repricingToken.reserveToken()) * repricingToken.reservesPerShare() / (10 ** ERC20(_repricingToken).decimals());
    }

    /** INTERNAL PRIMATIVES AND COMPOSITION FUNCTIONS */

    /// @notice A fixed scalar amount, which can be used in mul/div operations
    function scalar(uint256 _amount) public pure returns (uint256) {
        return _amount;
    }

    /// @notice Use the price function from another source token.
    function aliasFor(address sourceToken) public view returns (uint256) {
        return tokenPrice(sourceToken);
    }

    /// @notice Multiply the result of two separate price lookup functions
    function mul(bytes calldata v1, bytes calldata v2) public view returns (uint256) {
        return runPriceFunction(v1) * runPriceFunction(v2) / 10 ** decimals;
    }

    /// @notice Divide the result of two separate price lookup functions
    function div(bytes calldata numerator, bytes calldata denominator) public view returns (uint256) {
        return runPriceFunction(numerator) * 10 ** decimals / runPriceFunction(denominator);
    }

    function runPriceFunction(bytes memory fnCalldata) internal view returns (uint256 price) {
        (bool success, bytes memory returndata) = address(this).staticcall(fnCalldata);

        if (success) {
            return abi.decode(returndata, (uint256));
        } else {
            revert FailedPriceLookup(fnCalldata);
        }
    }

    /// @notice Scale the price precision of the source to the target `pricePrecision`
    function scaleToPrecision(uint256 price, uint8 sourcePrecision) internal view returns (uint256) {
        unchecked {
            if (sourcePrecision <= decimals) {
                // Scale up (no-op if sourcePrecision == pricePrecision)
                return price * 10 ** (decimals - sourcePrecision);
            } else {
                // scale down
                return price / 10 ** (sourcePrecision - decimals);
            }
        }
    }
}