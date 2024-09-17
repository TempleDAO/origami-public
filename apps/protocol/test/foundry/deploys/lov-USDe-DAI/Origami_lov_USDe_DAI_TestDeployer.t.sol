pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

import { Range } from "contracts/libraries/Range.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

import { Origami_lov_USDe_DAI_TestConstants as Constants } from "test/foundry/deploys/lov-USDe-DAI/Origami_lov_USDe_DAI_TestConstants.t.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";

struct ExternalContracts {
    IERC20 daiToken;
    IERC20 usdeToken;

    IAggregatorV3Interface redstoneUsdeToUsdOracle;
}

struct LovTokenContracts {
    OrigamiLovToken lovToken;
    OrigamiLovTokenMorphoManager lovTokenManager;
    OrigamiStableChainlinkOracle usdeToDaiOracle;
    IOrigamiSwapper swapper;
    OrigamiMorphoBorrowAndLend borrowLend;
}

/* solhint-disable max-states-count */
contract Origami_lov_USDe_DAI_TestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
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
    OrigamiLovTokenMorphoManager public lovTokenManager;
    OrigamiStableChainlinkOracle public usdeToDaiOracle;
    IOrigamiSwapper public swapper;
    OrigamiMorphoBorrowAndLend public borrowLend;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.daiToken = daiToken;
        externalContracts.usdeToken = usdeToken;
        externalContracts.redstoneUsdeToUsdOracle = redstoneUsdeToUsdOracle;

        lovTokenContracts.lovToken = lovToken;
        lovTokenContracts.lovTokenManager = lovTokenManager;
        lovTokenContracts.usdeToDaiOracle = usdeToDaiOracle;
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

        daiToken = new DummyMintableToken(owner, "DAI", "DAI", 18);
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
            daiToken = IERC20(Constants.DAI_ADDRESS);
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
        usdeToDaiOracle = new OrigamiStableChainlinkOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "USDe/DAI",
                address(usdeToken),
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

        lovToken = new OrigamiLovToken(
            owner,
            "Origami lov-USDe-a",
            "lov-USDe-a",
            Constants.PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices),
            type(uint256).max
        );
        borrowLend = new OrigamiMorphoBorrowAndLend(
            owner,
            address(usdeToken),
            address(daiToken),
            Constants.MORPHO,
            Constants.MORPHO_MARKET_ORACLE,
            Constants.MORPHO_MARKET_IRM,
            Constants.MORPHO_MARKET_LLTV,
            Constants.MAX_SAFE_LLTV
        );
        lovTokenManager = new OrigamiLovTokenMorphoManager(
            owner,
            address(usdeToken),
            address(daiToken),
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
        lovTokenManager.setOracles(address(usdeToDaiOracle), address(usdeToDaiOracle));
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