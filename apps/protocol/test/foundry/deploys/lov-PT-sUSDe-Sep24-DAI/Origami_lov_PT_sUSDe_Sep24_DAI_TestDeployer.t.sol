pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

import { Range } from "contracts/libraries/Range.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiPendlePtToAssetOracle } from "contracts/common/oracle/OrigamiPendlePtToAssetOracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";

import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenMorphoManagerMarketAL } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManagerMarketAL.sol";
import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

import { Origami_lov_PT_sUSDe_Sep24_DAI_TestConstants as Constants } from "test/foundry/deploys/lov-PT-sUSDe-Sep24-DAI/Origami_lov_PT_sUSDe_Sep24_DAI_TestConstants.t.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";

import { PendlePYLpOracle } from "@pendle/core-v2/contracts/oracles/PendlePYLpOracle.sol";
import { IPMarket } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";

import { Vm } from "forge-std/Vm.sol";

import { 
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

struct ExternalContracts {
    IERC20 ptSUSDeToken;
    IERC20 daiToken;
    IERC20 usdeToken;

    IAggregatorV3Interface redstoneUsdeToUsdOracle;
}

struct LovTokenContracts {
    OrigamiLovToken lovToken;
    OrigamiLovTokenMorphoManagerMarketAL lovTokenManager;
    OrigamiStableChainlinkOracle usdeToDaiOracle;
    OrigamiPendlePtToAssetOracle ptSUsdeToUSDeOracle;
    OrigamiCrossRateOracle ptSUsdeToDaiOracle;
    IOrigamiSwapper swapper;
    OrigamiMorphoBorrowAndLend borrowLend;
}

/* solhint-disable max-states-count */
contract Origami_lov_PT_sUSDe_Sep24_DAI_TestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
    IERC20 public ptSUSDeToken;
    IERC20 public daiToken;
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
    OrigamiLovTokenMorphoManagerMarketAL public lovTokenManager;
    OrigamiStableChainlinkOracle public usdeToDaiOracle;
    OrigamiPendlePtToAssetOracle public ptSUsdeToUSDeOracle;
    OrigamiCrossRateOracle public ptSUsdeToDaiOracle;
    IOrigamiSwapper public swapper;
    OrigamiMorphoBorrowAndLend public borrowLend;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.ptSUSDeToken = ptSUSDeToken;
        externalContracts.daiToken = daiToken;
        externalContracts.usdeToken = usdeToken;
        externalContracts.redstoneUsdeToUsdOracle = redstoneUsdeToUsdOracle;

        lovTokenContracts.lovToken = lovToken;
        lovTokenContracts.lovTokenManager = lovTokenManager;
        lovTokenContracts.usdeToDaiOracle = usdeToDaiOracle;
        lovTokenContracts.ptSUsdeToUSDeOracle = ptSUsdeToUSDeOracle;
        lovTokenContracts.ptSUsdeToDaiOracle = ptSUsdeToDaiOracle;
        lovTokenContracts.swapper = swapper;
        lovTokenContracts.borrowLend = borrowLend;
    }

    function deployNonForked(
        address _owner, 
        address _feeCollector, 
        address _overlord,
        Vm vm
    ) external returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        owner = _owner;
        feeCollector = _feeCollector;
        overlord = _overlord;

        ptSUSDeToken = new DummyMintableToken(owner, "PT-sUSDe-Sep24", "PT-sUSDe-Sep24", 18);
        daiToken = new DummyMintableToken(owner, "DAI", "DAI", 18);
        usdeToken = new DummyMintableToken(owner, "USDe", "USDe", 18);

        swapper = new DummyLovTokenSwapper();

        redstoneUsdeToUsdOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00135613e8,
                startedAt: 1721006984,
                updatedAtLag: 1721006984,
                answeredInRound: 1
            }),
            8
        );

        _createMorphoMarket();
        
        _setupLovToken(vm);
        return getContracts();
    }

    function deployForked(
        address _owner, 
        address _feeCollector, 
        address _overlord,
        Vm vm
    ) external returns (  
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        owner = _owner;
        feeCollector = _feeCollector;
        overlord = _overlord;

        {
            ptSUSDeToken = IERC20(Constants.PT_SUSDE_SEP24_ADDRESS);
            daiToken = IERC20(Constants.DAI_ADDRESS);
            usdeToken = IERC20(Constants.USDE_ADDRESS);

            // Too challenging to do the on chain swapper repeatedly.
            // It has been confirmed once manually.
            // swapper = new OrigamiDexAggregatorSwapper(owner);

            swapper = new DummyLovTokenSwapper();

            // https://docs.redstone.finance/docs/smart-contract-devs/price-feeds#available-on-chain-classic-model
            redstoneUsdeToUsdOracle = IAggregatorV3Interface(Constants.USDE_USD_ORACLE);
        }

        _createMorphoMarket();

        _setupLovToken(vm);
        return getContracts();
    }

    function _createMorphoMarket() private {
        
        MorphoMarketParams memory params = MorphoMarketParams({
            loanToken: Constants.DAI_ADDRESS,
            collateralToken: Constants.PT_SUSDE_SEP24_ADDRESS,
            oracle: Constants.MORPHO_MARKET_ORACLE,
            irm: Constants.MORPHO_MARKET_IRM,
            lltv: Constants.MORPHO_MARKET_LLTV
        });
        IMorpho(Constants.MORPHO).createMarket(params);
    }

    function _setupLovToken(Vm vm) private {
        // Might need to init the pendle oracle
        (bool increaseCardinalityRequired, uint16 cardinalityRequired,) = PendlePYLpOracle(Constants.PENDLE_ORACLE).getOracleState(
            Constants.PT_SUSDE_SEP24_MARKET, 
            Constants.PENDLE_TWAP_DURATION
        );
        if (increaseCardinalityRequired) {
            IPMarket(Constants.PT_SUSDE_SEP24_MARKET).increaseObservationsCardinalityNext(cardinalityRequired);
            vm.warp(block.timestamp + Constants.PENDLE_TWAP_DURATION);
        }

        ptSUsdeToUSDeOracle = new OrigamiPendlePtToAssetOracle(
            IOrigamiOracle.BaseOracleParams(
                "PT-sUSDe-Sep24/USDe",
                Constants.PT_SUSDE_SEP24_ADDRESS,
                Constants.PT_SUSDE_SEP24_DECIMALS,
                Constants.USDE_ADDRESS,
                Constants.USDE_DECIMALS
            ),
            Constants.PENDLE_ORACLE,
            Constants.PT_SUSDE_SEP24_MARKET,
            Constants.PENDLE_TWAP_DURATION
        );

        usdeToDaiOracle = new OrigamiStableChainlinkOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "USDe/DAI",
                Constants.USDE_ADDRESS,
                Constants.USDE_DECIMALS,
                Constants.DAI_ADDRESS,
                Constants.DAI_DECIMALS
            ),
            Constants.USDE_USD_HISTORIC_STABLE_PRICE,
            address(redstoneUsdeToUsdOracle),
            Constants.USDE_USD_STALENESS_THRESHOLD,
            Range.Data(Constants.USDE_USD_MIN_THRESHOLD, Constants.USDE_USD_MAX_THRESHOLD),
            false, // Redstone does not use roundId
            true // It does use lastUpdatedAt
        );
        
        ptSUsdeToDaiOracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "PT-sUSDe-Sep24/DAI",
                Constants.PT_SUSDE_SEP24_ADDRESS,
                Constants.PT_SUSDE_SEP24_DECIMALS,
                Constants.DAI_ADDRESS,
                Constants.DAI_DECIMALS
            ),
            address(ptSUsdeToUSDeOracle),
            address(usdeToDaiOracle),
            address(0)
        );

        lovToken = new OrigamiLovToken(
            owner,
            "Origami lov-PT-sUSDe-Sep24",
            "lov-PT-sUSDe-Sep24",
            Constants.PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices),
            type(uint256).max
        );

        borrowLend = new OrigamiMorphoBorrowAndLend(
            owner,
            address(ptSUSDeToken),
            address(daiToken),
            Constants.MORPHO,
            Constants.MORPHO_MARKET_ORACLE,
            Constants.MORPHO_MARKET_IRM,
            Constants.MORPHO_MARKET_LLTV,
            Constants.MAX_SAFE_LLTV
        );
        lovTokenManager = new OrigamiLovTokenMorphoManagerMarketAL(
            owner,
            address(ptSUSDeToken),
            address(daiToken),
            address(ptSUSDeToken),
            address(lovToken),
            address(borrowLend),
            address(ptSUsdeToDaiOracle)
        );

        _postDeployLovToken();
    }

    function _postDeployLovToken() private {
        userALRange = Range.Data(Constants.USER_AL_FLOOR, Constants.USER_AL_CEILING);
        rebalanceALRange = Range.Data(Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);

        borrowLend.setPositionOwner(address(lovTokenManager));
        borrowLend.setSwapper(address(swapper));

        // Initial setup of config.
        lovTokenManager.setOracles(address(ptSUsdeToDaiOracle), address(ptSUsdeToDaiOracle));
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