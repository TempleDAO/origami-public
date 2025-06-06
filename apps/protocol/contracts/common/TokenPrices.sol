pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/TokenPrices.sol)

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IUniswapV3Pool } from "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";
import { IKodiakV3Pool } from "contracts/interfaces/external/kodiak/IKodiakV3Pool.sol";
import { IKodiakIsland } from "contracts/interfaces/external/kodiak/IKodiakIsland.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";
import { IJoeLBQuoter } from "contracts/interfaces/external/traderJoe/IJoeLBQuoter.sol";
import { IStETH } from "contracts/interfaces/external/lido/IStETH.sol";

import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { IRepricingToken } from "contracts/interfaces/common/IRepricingToken.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";

/// @title Token Prices
/// @notice A utility contract to pull token prices on-chain.
/// @dev Composable functions (using encoded function calldata) to build up price formulas
/// Do NOT use these prices for direct on-chain purposes, as they can generally be abused.
/// eg single block sandwich attacks, multi-block attacks by block producers, etc.
/// They are only to be used for utilities such as showing estimated $USD equiv. prices in a dapp, etc
contract TokenPrices is ITokenPrices, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint8 public immutable override decimals;
    
    /// @notice Token address to function calldata for how to lookup the price for this token
    mapping(address token => bytes fnCalldata) public override priceFnCalldata;

    /// @dev The list of token addresses which have been mapped.
    EnumerableSet.AddressSet internal _mappedTokens;

    error InvalidPrice(int256);
    error FailedPriceLookup(bytes fnCalldata);
    event TokenPriceFunctionSet(address indexed token, bytes fnCalldata);
    
    struct PriceMapping {
        address token;
        bytes fnCalldata;
    }

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    /// @notice Map a token address to a function calldata defining how to retrieve the price
    function setTokenPriceFunction(address token, bytes calldata fnCalldata) external onlyOwner {
        emit TokenPriceFunctionSet(token, fnCalldata);
        priceFnCalldata[token] = fnCalldata;
        _mappedTokens.add(token);
    }

    /// @notice Map a token address to a function calldata defining how to retrieve the price
    function setTokenPriceFunctions(PriceMapping[] calldata mappings) external onlyOwner {
        PriceMapping calldata m;
        for (uint256 i; i < mappings.length; ++i) {
            m = mappings[i];
            emit TokenPriceFunctionSet(m.token, m.fnCalldata);
            priceFnCalldata[m.token] = m.fnCalldata;
            _mappedTokens.add(m.token);
        }
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
    function tokenPrices(address[] calldata tokens) external override view returns (uint256[] memory prices) {
        prices = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            prices[i] = runPriceFunction(priceFnCalldata[tokens[i]]);
        }
    }

    /// @notice The set of all mapped tokens
    function mappedTokenAt(uint256 i) external override view returns (address token) {
        return _mappedTokens.at(i);
    }

    /// @notice The set of all mapped tokens
    function allMappedTokens() external override view returns (address[] memory) {
        return _mappedTokens.values();
    }

    /// @notice The number of mapped tokens
    function numMappedTokens() external override view returns (uint256) {
        return _mappedTokens.length();
    }

    /** EXTERNAL PRICE LOOKUPS */

    /// @notice Lookup the price of an oracle, scaled to `pricePrecision`
    function oraclePrice(address _oracle, uint256 _stalenessThreshold) external view returns (uint256 price) {
        IAggregatorV3Interface oracle = IAggregatorV3Interface(_oracle);
        (uint80 roundId, int256 feedValue, , uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
		if (answeredInRound <= roundId && block.timestamp - updatedAt > _stalenessThreshold) revert InvalidPrice(feedValue);

        if (feedValue < 0) revert InvalidPrice(feedValue);
        price = scaleToPrecision(uint256(feedValue), oracle.decimals());
    }

    /// @notice The wstEth -> stETH conversion ratio
    function wstEthRatio(address _stEthToken) external view returns (uint256 ratio) {
        return IStETH(_stEthToken).getPooledEthByShares(10 ** decimals);
    }

    /// @notice Fetch the Trader Joe pair price, not inclusive of swap fees or price impact.
    /// @dev Do not use this for on-chain calculations, as it can be exploited 
    /// with a single block sandwhich attack. Only use for off-chain utilities (eg informational purposes only)
    function traderJoeBestPrice(IJoeLBQuoter joeQuoter, address sellToken, address buyToken) external view returns (uint256) {
        address[] memory route = new address[](2);
        route[0] = sellToken;
        route[1] = buyToken;
        uint8 buyTokenDecimals = ERC20(buyToken).decimals();
        uint8 sellTokenDecimals = ERC20(sellToken).decimals();

        // Get the quote details to sell 1 token, across all v1 and v2 pools
        IJoeLBQuoter.Quote memory quote = joeQuoter.findBestPathFromAmountIn(route, 10 ** sellTokenDecimals);

        // Scale to 1e30.
        uint256 sellTokenAmount = scaleToPrecision(quote.virtualAmountsWithoutSlippage[0], sellTokenDecimals);
        uint256 sellTokenFeeAmount = sellTokenAmount * quote.fees[0] / 1e18; // fees are a percentage of the sell token amount
        uint256 buyTokenAmount = scaleToPrecision(quote.virtualAmountsWithoutSlippage[1], buyTokenDecimals);

        return buyTokenAmount * 10 ** decimals / (sellTokenAmount - sellTokenFeeAmount);
    }

    /// @notice Fetch the price from a univ3 pool, in quoted order (token0Price), to `pricePrecision`
    /// @dev https://web.archive.org/web/20210918154903/https://docs.uniswap.org/sdk/guides/fetching-prices
    /// @dev Do not use this for on-chain calculations, as it can be exploited 
    /// with a multi block attacks by block producers. Only use for off-chain utilities (eg informational purposes only)
    function univ3Price(IUniswapV3Pool pool, bool inQuotedOrder) external view returns (uint256) {
        // Pull the current price from the pool
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        return _priceFromSqrtX96(
            sqrtPriceX96,
            inQuotedOrder,
            IERC20Metadata(pool.token0()),
            IERC20Metadata(pool.token1())
        );
    }

    /// @notice Fetch the price from a kodiak v3 pool, in quoted order (token0Price), to `pricePrecision`
    /// @dev The same as `univ3Price()` above, except the Kodiak fork has a minor interface change.
    /// @dev Do not use this for on-chain calculations, as it can be exploited 
    /// with a multi block attacks by block producers. Only use for off-chain utilities (eg informational purposes only)
    function kodiakV3Price(IKodiakV3Pool pool, bool inQuotedOrder) external view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        return _priceFromSqrtX96(
            sqrtPriceX96,
            inQuotedOrder,
            IERC20Metadata(pool.token0()),
            IERC20Metadata(pool.token1())
        );
    }

    /// @notice Calculate the price of a Kodiak Island ERC20 token
    /// @dev Based on the total token value of the island v3 position divided by the total supply
    function kodiakIslandPrice(IKodiakIsland island) external view returns (uint256) {
        IERC20Metadata token0 = IERC20Metadata(address(island.token0()));
        IERC20Metadata token1 = IERC20Metadata(address(island.token1()));
        (uint256 amount0Current, uint256 amount1Current) = island.getUnderlyingBalances();

        uint256 totalIslandUsd = (
            OrigamiMath.mulDiv(
                amount0Current,
                tokenPrice(address(token0)),
                10 ** token0.decimals(),
                OrigamiMath.Rounding.ROUND_DOWN
            ) +
            OrigamiMath.mulDiv(
                amount1Current,
                tokenPrice(address(token1)),
                10 ** token1.decimals(),
                OrigamiMath.Rounding.ROUND_DOWN
            )
        );

        return OrigamiMath.mulDiv(
            totalIslandUsd,
            10 ** IERC20Metadata(address(island)).decimals(),
            island.totalSupply(),
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }

    /// @notice Calculate the price of a Balancer BPT token
    /// @dev Based on the total token value in the BPT divided by the total supply
    function balancerV2BptPrice(IBalancerVault balancerVault, IBalancerBptToken bptToken) external view returns (uint256) {
        (address[] memory tokens, uint256[] memory balances,) = balancerVault.getPoolTokens(
            bptToken.getPoolId()
        );

        uint256 totalPoolUsd;
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(bptToken)) continue;

            totalPoolUsd += OrigamiMath.mulDiv(
                balances[i],
                tokenPrice(token),
                10 ** IERC20Metadata(token).decimals(),
                OrigamiMath.Rounding.ROUND_DOWN
            );
        }

        return OrigamiMath.mulDiv(
            totalPoolUsd,
            10 ** IERC20Metadata(address(bptToken)).decimals(),
            bptToken.getActualSupply(),
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }

    /// @notice Use the origami defined oracle price
    function origamiOraclePrice(
        IOrigamiOracle origamiOracle, 
        IOrigamiOracle.PriceType priceType, 
        OrigamiMath.Rounding roundingMode
    ) external view returns (uint256) {
        return scaleToPrecision(origamiOracle.latestPrice(priceType, roundingMode), origamiOracle.decimals());
    }

    /// @notice Calculate the Repricing Token price based
    /// on the [reserveToken price] * [reservesPerShare()]
    function repricingTokenPrice(address _repricingToken) external view returns (uint256) {
        IRepricingToken repricingToken = IRepricingToken(_repricingToken);

        // reservesPerShare is quoted in the reserve token decimals. The final result should be in `decimals` precision
        address reserveToken = repricingToken.reserveToken();
        return tokenPrice(reserveToken) * repricingToken.reservesPerShare() / (10 ** IERC20Metadata(reserveToken).decimals());
    }

    /// @notice Calculate the price of an ERC-4626 token vault
    /// [asset price] * [assets per share]
    function erc4626TokenPrice(address vault) external view returns (uint256) {
        uint8 _vaultDecimals = IERC20Metadata(vault).decimals();
        IERC4626 _vault = IERC4626(vault);
        address _underlyingAsset = _vault.asset();
        uint8 _underlyingAssetDecimals = IERC20Metadata(_underlyingAsset).decimals();

        // Return the price to this contract's `decimals` precision
        return OrigamiMath.mulDiv(
            tokenPrice(_underlyingAsset),                 // 30 decimals
            _vault.convertToAssets(10 ** _vaultDecimals), // 1 share in underlying asset decimals
            10 ** _underlyingAssetDecimals,               // 1 underlying asset
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }

    /// @notice Calculate the price of a Tokenized Balance Sheet token vault
    /// @dev Each of the underlying tokens in the vault needs to be mapped
    /// price is floored at zero
    function tokenizedBalanceSheetTokenPrice(address vault) external view returns (uint256) {
        uint8 _vaultDecimals = IERC20Metadata(vault).decimals();
        ITokenizedBalanceSheetVault _vault = ITokenizedBalanceSheetVault(vault);

        (uint256[] memory _assetPerShare, uint256[] memory _liabilitiesPerShare) = _vault.convertFromShares(10 ** _vaultDecimals);
        (address[] memory _assetTokens, address[] memory _liabilityTokens) = _vault.tokens();

        int256 _totalPrice;
        for (uint256 i; i < _assetTokens.length; ++i) {
            _totalPrice += int256(_underlyingAssetPrice(_assetTokens[i], _assetPerShare[i]));
        }
        for (uint256 i; i < _liabilityTokens.length; ++i) {
            _totalPrice -= int256(_underlyingAssetPrice(_liabilityTokens[i], _liabilitiesPerShare[i]));
        }

        return _totalPrice > 0 ? uint256(_totalPrice) : 0;
    }

    function _underlyingAssetPrice(address token, uint256 assetPerShare) private view returns (uint256) {
        return OrigamiMath.mulDiv(
            tokenPrice(token),                      // 30 decimals
            assetPerShare,                          // 1 share in underlying asset decimals
            10 ** IERC20Metadata(token).decimals(), // 1 underlying asset
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }

    /** INTERNAL PRIMATIVES AND COMPOSITION FUNCTIONS */

    /// @notice A fixed scalar amount, which can be used in mul/div operations
    function scalar(uint256 _amount) external pure returns (uint256) {
        return _amount;
    }

    /// @notice Use the price function from another source token.
    function aliasFor(address sourceToken) external view returns (uint256) {
        return tokenPrice(sourceToken);
    }

    /// @notice Multiply the result of two separate price lookup functions
    function mul(bytes calldata v1, bytes calldata v2) external view returns (uint256) {
        return runPriceFunction(v1) * runPriceFunction(v2) / 10 ** decimals;
    }

    /// @notice Divide the result of two separate price lookup functions
    function div(bytes calldata numerator, bytes calldata denominator) external view returns (uint256) {
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

    function _priceFromSqrtX96(
        uint160 sqrtPriceX96,
        bool inQuotedOrder,
        IERC20Metadata token0,
        IERC20Metadata token1
    ) private view returns (uint256) {
        // Use mulDiv as otherwise the calc would overflow.        
        // https://xn--2-umb.com/21/muldiv/index.html
        if (inQuotedOrder) {
            // price = sqrtPriceX96^2 / 2^192
            uint256 decimalsScalar = 10 ** (decimals + token0.decimals() - token1.decimals());
            return OrigamiMath.mulDiv(uint256(sqrtPriceX96) * sqrtPriceX96, decimalsScalar, 1 << 192, OrigamiMath.Rounding.ROUND_DOWN);
        } else {
            // price = 2^192 / sqrtPriceX96^2
            uint256 decimalsScalar = 10 ** (decimals + token1.decimals() - token0.decimals());
            return OrigamiMath.mulDiv(1 << 192, decimalsScalar, sqrtPriceX96, OrigamiMath.Rounding.ROUND_DOWN) / sqrtPriceX96;
        }
    }
}
