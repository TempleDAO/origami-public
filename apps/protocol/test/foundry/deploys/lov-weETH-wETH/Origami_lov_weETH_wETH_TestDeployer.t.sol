pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IEtherFiLiquidityPool } from "contracts/interfaces/external/etherfi/IEtherFiLiquidityPool.sol";

import { Range } from "contracts/libraries/Range.sol";
import { OrigamiEtherFiEthToEthOracle } from "contracts/common/oracle/OrigamiEtherFiEthToEthOracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

import { Origami_lov_weETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-weETH-wETH/Origami_lov_weETH_wETH_TestConstants.t.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";

struct ExternalContracts {
    IERC20 weEthToken;
    IERC20 wEthToken;

    IAggregatorV3Interface redstoneWeEthToEthOracle;
    IEtherFiLiquidityPool etherfiLiquidityPool;
}

struct LovTokenContracts {
    OrigamiLovToken lovToken;
    OrigamiLovTokenMorphoManager lovTokenManager;
    OrigamiEtherFiEthToEthOracle weEthToEthOracle;
    IOrigamiSwapper swapper;
    OrigamiMorphoBorrowAndLend borrowLend;
}

/* solhint-disable max-states-count */
contract Origami_lov_weETH_wETH_TestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
    IERC20 public wEthToken;
    IERC20 public weEthToken;
    IAggregatorV3Interface public redstoneWeEthToEthOracle;
    IEtherFiLiquidityPool public etherfiLiquidityPool;
    
    /**
     * core contracts
     */
    TokenPrices public tokenPrices;

    /**
     * LovToken contracts
     */
    OrigamiLovToken public lovToken;
    OrigamiLovTokenMorphoManager public lovTokenManager;
    OrigamiEtherFiEthToEthOracle public weEthToEthOracle;
    IOrigamiSwapper public swapper;
    OrigamiMorphoBorrowAndLend public borrowLend;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.wEthToken = wEthToken;
        externalContracts.weEthToken = weEthToken;
        externalContracts.redstoneWeEthToEthOracle = redstoneWeEthToEthOracle;
        externalContracts.etherfiLiquidityPool = etherfiLiquidityPool;

        lovTokenContracts.lovToken = lovToken;
        lovTokenContracts.lovTokenManager = lovTokenManager;
        lovTokenContracts.weEthToEthOracle = weEthToEthOracle;
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

        wEthToken = new DummyMintableToken(owner, "wEth", "wEth", 18);
        weEthToken = new DummyMintableToken(owner, "weEth", "weEth", 18);

        swapper = new DummyLovTokenSwapper();

        redstoneWeEthToEthOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 132,
                answer: 1.00795447e8,
                startedAt: 1713394343,
                updatedAtLag: 1713394343,
                answeredInRound: 132
            }),
            8
        );

        // @todo Need a dummy contract
        // renzoRestakeManager = IRenzoRestakeManager(Constants.RENZO_RESTAKE_MANAGER);

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
            wEthToken = IERC20(Constants.WETH_ADDRESS);
            weEthToken = IERC20(Constants.WEETH_ADDRESS);

            swapper = new OrigamiDexAggregatorSwapper(owner);
            OrigamiDexAggregatorSwapper(address(swapper)).whitelistRouter(Constants.ONE_INCH_ROUTER, true);

            // https://docs.redstone.finance/docs/smart-contract-devs/price-feeds#available-on-chain-classic-model
            redstoneWeEthToEthOracle = IAggregatorV3Interface(Constants.REDSTONE_WEETH_ETH_ORACLE);

            etherfiLiquidityPool = IEtherFiLiquidityPool(Constants.ETHERFI_LIQUIDITY_POOL);
        }

        _setupLovToken();
        return getContracts();
    }

    function _setupLovToken() private {
        weEthToEthOracle = new OrigamiEtherFiEthToEthOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "weETH/wETH",
                address(weEthToken),
                Constants.WEETH_DECIMALS,
                Constants.WETH_ADDRESS,
                Constants.WETH_DECIMALS
            ),
            address(redstoneWeEthToEthOracle),
            Constants.WEETH_ETH_STALENESS_THRESHOLD,
            Constants.WEETH_ETH_MAX_REL_DIFF_THRESHOLD_BPS,
            address(etherfiLiquidityPool)
        );

        lovToken = new OrigamiLovToken(
            owner,
            "Origami lov-weETH-a",
            "lov-weETH-a",
            Constants.PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices),
            type(uint256).max
        );
        borrowLend = new OrigamiMorphoBorrowAndLend(
            owner,
            address(weEthToken),
            address(wEthToken),
            Constants.MORPHO,
            Constants.MORPHO_MARKET_ORACLE,
            Constants.MORPHO_MARKET_IRM,
            Constants.MORPHO_MARKET_LLTV,
            Constants.MAX_SAFE_LLTV
        );
        lovTokenManager = new OrigamiLovTokenMorphoManager(
            owner,
            address(weEthToken),
            address(wEthToken),
            address(weEthToken),
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
        lovTokenManager.setOracles(address(weEthToEthOracle), address(weEthToEthOracle));
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