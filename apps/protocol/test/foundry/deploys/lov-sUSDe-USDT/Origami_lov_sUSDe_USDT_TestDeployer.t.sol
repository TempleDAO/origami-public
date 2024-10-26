pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

import { Range } from "contracts/libraries/Range.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiErc4626Oracle } from "contracts/common/oracle/OrigamiErc4626Oracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

import { Origami_lov_sUSDe_USDT_TestConstants as Constants } from "test/foundry/deploys/lov-sUSDe-USDT/Origami_lov_sUSDe_USDT_TestConstants.t.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";

struct ExternalContracts {
    IERC20 usdtToken;
    IERC20 sUsdeToken;
    IERC20 usdeToken;

    IAggregatorV3Interface redstoneUsdeToUsdOracle;
}

struct LovTokenContracts {
    OrigamiLovToken lovToken;
    OrigamiLovTokenMorphoManager lovTokenManager;
    OrigamiStableChainlinkOracle usdeToUsdtOracle;
    OrigamiErc4626Oracle sUsdeToUsdtOracle;
    IOrigamiSwapper swapper;
    OrigamiMorphoBorrowAndLend borrowLend;
}

/* solhint-disable max-states-count */
contract Origami_lov_sUSDe_USDT_TestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
    IERC20 public usdtToken;
    IERC20 public sUsdeToken;
    IERC20 public usdeToken;
    IAggregatorV3Interface public redstoneUsdeToUsdOracle;
    
    /**
     * core contracts
     */
    TokenPrices public tokenPrices;

    /**
     * LovToken contracts
     */
    OrigamiLovToken public lovToken;
    OrigamiLovTokenMorphoManager public lovTokenManager;
    OrigamiStableChainlinkOracle public usdeToUsdtOracle;
    OrigamiErc4626Oracle public sUsdeToUsdtOracle;
    IOrigamiSwapper public swapper;
    OrigamiMorphoBorrowAndLend public borrowLend;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.usdtToken = usdtToken;
        externalContracts.sUsdeToken = sUsdeToken;
        externalContracts.usdeToken = usdeToken;
        externalContracts.redstoneUsdeToUsdOracle = redstoneUsdeToUsdOracle;

        lovTokenContracts.lovToken = lovToken;
        lovTokenContracts.lovTokenManager = lovTokenManager;
        lovTokenContracts.usdeToUsdtOracle = usdeToUsdtOracle;
        lovTokenContracts.sUsdeToUsdtOracle = sUsdeToUsdtOracle;
        lovTokenContracts.swapper = swapper;
        lovTokenContracts.borrowLend = borrowLend;
    }

    function deployNonForked(
        address _owner, 
        address _feeCollector, 
        address _overlord
    ) external returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        owner = _owner;
        feeCollector = _feeCollector;
        overlord = _overlord;

        usdtToken = new DummyMintableToken(owner, "USDT", "USDT", 6);
        sUsdeToken = new DummyMintableToken(owner, "sUSDe", "sUSDe", 18);
        usdeToken = new DummyMintableToken(owner, "USDe", "USDe", 18);

        swapper = new DummyLovTokenSwapper();

        redstoneUsdeToUsdOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00135613e8,
                startedAt: 1711046891,
                updatedAtLag: 1711046891,
                answeredInRound: 1
            }),
            8
        );

        _setupLovToken();
        return getContracts();
    }

    function deployForked(
        address _owner, 
        address _feeCollector, 
        address _overlord
    ) external returns (  
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        owner = _owner;
        feeCollector = _feeCollector;
        overlord = _overlord;

        {
            usdtToken = IERC20(Constants.USDT_ADDRESS);
            sUsdeToken = IERC20(Constants.SUSDE_ADDRESS);
            usdeToken = IERC20(Constants.USDE_ADDRESS);

            swapper = new OrigamiDexAggregatorSwapper(owner);
            OrigamiDexAggregatorSwapper(address(swapper)).whitelistRouter(Constants.ONE_INCH_ROUTER, true);

            // https://docs.redstone.finance/docs/smart-contract-devs/price-feeds#available-on-chain-classic-model
            redstoneUsdeToUsdOracle = IAggregatorV3Interface(Constants.USDE_USD_ORACLE);
        }

        _setupLovToken();
        return getContracts();
    }

    function _setupLovToken() private {
        usdeToUsdtOracle = new OrigamiStableChainlinkOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "USDe/USDT",
                address(usdeToken),
                Constants.USDE_DECIMALS,
                Constants.USDT_ADDRESS,
                Constants.USDT_DECIMALS
            ),
            Constants.USDE_USD_HISTORIC_STABLE_PRICE,
            address(redstoneUsdeToUsdOracle),
            Constants.USDE_USD_STALENESS_THRESHOLD,
            Range.Data(Constants.USDE_USD_MIN_THRESHOLD, Constants.USDE_USD_MAX_THRESHOLD),
            false, // Redstone does not use roundId
            true // It does use lastUpdatedAt
        );
        sUsdeToUsdtOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sUSDe/USDT",
                address(sUsdeToken),
                Constants.SUSDE_DECIMALS,
                Constants.USDT_ADDRESS,
                Constants.USDT_DECIMALS
            ),
            address(usdeToUsdtOracle)
        );

        lovToken = new OrigamiLovToken(
            owner,
            "Origami lov-sUSDe",
            "lov-sUSDe",
            Constants.PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices),
            type(uint256).max
        );
        borrowLend = new OrigamiMorphoBorrowAndLend(
            owner,
            address(sUsdeToken),
            address(usdtToken),
            Constants.MORPHO,
            Constants.MORPHO_MARKET_ORACLE,
            Constants.MORPHO_MARKET_IRM,
            Constants.MORPHO_MARKET_LLTV,
            Constants.MAX_SAFE_LLTV
            // lovStEth.decimals()
        );
        lovTokenManager = new OrigamiLovTokenMorphoManager(
            owner,
            address(sUsdeToken),
            address(usdtToken),
            address(usdeToken),
            address(lovToken),
            address(borrowLend)
        );

        _postDeployLovToken();
    }

    function _postDeployLovToken() private {
        userALRange = Range.Data(Constants.USER_AL_FLOOR, Constants.USER_AL_CEILING);
        rebalanceALRange = Range.Data(Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);

        borrowLend.setPositionOwner(address(lovTokenManager));
        borrowLend.setSwapper(address(swapper));

        // Initial setup of config.
        lovTokenManager.setOracles(address(sUsdeToUsdtOracle), address(usdeToUsdtOracle));
        lovTokenManager.setUserALRange(userALRange.floor, userALRange.ceiling);
        lovTokenManager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
        lovTokenManager.setFeeConfig(Constants.MIN_DEPOSIT_FEE_BPS, Constants.MIN_EXIT_FEE_BPS, Constants.FEE_LEVERAGE_FACTOR);

        _setExplicitAccess(
            lovTokenManager, 
            overlord, 
            OrigamiLovTokenMorphoManager.rebalanceUp.selector, 
            OrigamiLovTokenMorphoManager.rebalanceDown.selector, 
            true
        );

        lovToken.setManager(address(lovTokenManager));

        // Only needed in lovTokenManager tests so we can mint/burn
        // (ordinarily lovToken will do this via internal fns -- but we prank using foundry)
        lovToken.addMinter(address(lovToken));
    }

    function _setExplicitAccess(
        IOrigamiElevatedAccess theContract, 
        address allowedCaller, 
        bytes4 fnSelector, 
        bool value
    ) private {
        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](1);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector, value);
        theContract.setExplicitAccess(allowedCaller, access);
    }

    function _setExplicitAccess(
        IOrigamiElevatedAccess theContract, 
        address allowedCaller, 
        bytes4 fnSelector1, 
        bytes4 fnSelector2, 
        bool value
    ) private {
        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](2);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector1, value);
        access[1] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector2, value);
        theContract.setExplicitAccess(allowedCaller, access);
    }
}