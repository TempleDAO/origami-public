pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

import { Range } from "contracts/libraries/Range.sol";
import { OrigamiVolatileChainlinkOracle } from "contracts/common/oracle/OrigamiVolatileChainlinkOracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenFlashAndBorrowManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenFlashAndBorrowManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiAaveV3FlashLoanProvider } from "contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol";
import { Origami_lovToken_TestConstants as Constants } from "test/foundry-integration/deploys/lov-wETH-wBTC-2xShort-spark/Origami_lovToken_TestConstants.t.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";

struct ExternalContracts {
    IERC20 reserveToken;
    IERC20 debtToken;

    IAggregatorV3Interface clReserveToDebtOracle;
}

struct LovTokenContracts {
    OrigamiLovToken lovToken;
    OrigamiLovTokenFlashAndBorrowManager lovTokenManager;
    OrigamiVolatileChainlinkOracle reserveToDebtOracle;
    IOrigamiSwapper swapper;
    OrigamiAaveV3FlashLoanProvider flashLoanProvider;
    OrigamiAaveV3BorrowAndLend borrowLend;
}

/* solhint-disable max-states-count */
contract Origami_lovToken_TestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
    IERC20 public reserveToken;
    IERC20 public debtToken;
    IAggregatorV3Interface public clReserveToDebtOracle;
    
    /**
     * core contracts
     */
    TokenPrices public tokenPrices;

    /**
     * lovToken contracts
     */
    OrigamiLovToken public lovToken;
    OrigamiLovTokenFlashAndBorrowManager public lovTokenManager;
    OrigamiVolatileChainlinkOracle public reserveToDebtOracle;
    IOrigamiSwapper public swapper;
    OrigamiAaveV3FlashLoanProvider public flashLoanProvider;
    OrigamiAaveV3BorrowAndLend public borrowLend;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.reserveToken = reserveToken;
        externalContracts.debtToken = debtToken;
        externalContracts.clReserveToDebtOracle = clReserveToDebtOracle;

        lovTokenContracts.lovToken = lovToken;
        lovTokenContracts.lovTokenManager = lovTokenManager;
        lovTokenContracts.reserveToDebtOracle = reserveToDebtOracle;
        lovTokenContracts.swapper = swapper;
        lovTokenContracts.flashLoanProvider = flashLoanProvider;
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

        reserveToken = new DummyMintableToken(owner, "wBTC", "wBTC", 18);
        debtToken = new DummyMintableToken(owner, "wETH", "wETH", 18);

        swapper = new DummyLovTokenSwapper();

        clReserveToDebtOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 110680464442257326562,
                answer: 2_885.56181640e8,
                startedAt: 1715572559,
                updatedAtLag: 1715572559,
                answeredInRound: 110680464442257326562
            }),
            18
        );

        _setuplovToken();
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
            reserveToken = IERC20(Constants.WBTC_ADDRESS);
            debtToken = IERC20(Constants.WETH_ADDRESS);

            // swapper = new OrigamiDexAggregatorSwapper(owner);
            swapper = new DummyLovTokenSwapper();

            clReserveToDebtOracle = IAggregatorV3Interface(Constants.ETH_BTC_ORACLE);
        }

        _setuplovToken();
        return getContracts();
    }

    function _setuplovToken() private {
        reserveToDebtOracle = new OrigamiVolatileChainlinkOracle(
            IOrigamiOracle.BaseOracleParams(
                "wETH/wBTC",
                address(debtToken),
                Constants.WETH_DECIMALS,
                address(reserveToken),
                Constants.WBTC_DECIMALS
            ),
            address(clReserveToDebtOracle),
            Constants.ETH_BTC_STALENESS_THRESHOLD,
            true, // Chainlink does use roundId
            true  // Chainlink does use lastUpdatedAt
        );

        flashLoanProvider = new OrigamiAaveV3FlashLoanProvider(Constants.SPARK_POOL_ADDRESS_PROVIDER);

        lovToken = new OrigamiLovToken(
            owner,
            "Origami lov-wETH-WBTC-2x-short",
            "lov-wETH-WBTC-2x-short",
            Constants.PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices),
            type(uint256).max
        );
        borrowLend = new OrigamiAaveV3BorrowAndLend(
            owner,
            address(reserveToken),
            address(debtToken),
            Constants.SPARK_POOL,
            Constants.SPARK_EMODE_NOT_ENABLED
        );
        lovTokenManager = new OrigamiLovTokenFlashAndBorrowManager(
            owner,
            address(reserveToken),
            address(debtToken),
            address(reserveToken),
            address(lovToken),
            address(flashLoanProvider),
            address(borrowLend)
        );

        _postDeploylovToken();
    }

    function _postDeploylovToken() private {
        userALRange = Range.Data(Constants.USER_AL_FLOOR, Constants.USER_AL_CEILING);
        rebalanceALRange = Range.Data(Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);

        borrowLend.setPositionOwner(address(lovTokenManager));

        // Initial setup of config.
        lovTokenManager.setOracles(address(reserveToDebtOracle), address(reserveToDebtOracle));
        lovTokenManager.setUserALRange(userALRange.floor, userALRange.ceiling);
        lovTokenManager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
        lovTokenManager.setSwapper(address(swapper));
        lovTokenManager.setFeeConfig(Constants.MIN_DEPOSIT_FEE_BPS, Constants.MIN_EXIT_FEE_BPS, Constants.FEE_LEVERAGE_FACTOR);

        _setExplicitAccess(
            lovTokenManager,
            overlord, 
            OrigamiLovTokenFlashAndBorrowManager.rebalanceUp.selector, 
            OrigamiLovTokenFlashAndBorrowManager.rebalanceDown.selector, 
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