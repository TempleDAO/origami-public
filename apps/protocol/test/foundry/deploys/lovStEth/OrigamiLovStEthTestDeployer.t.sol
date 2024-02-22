pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

import { Range } from "contracts/libraries/Range.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiWstEthToEthOracle } from "contracts/common/oracle/OrigamiWstEthToEthOracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenFlashAndBorrowManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenFlashAndBorrowManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiAaveV3FlashLoanProvider } from "contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol";
import { OrigamiLovStEthTestConstants as Constants } from "test/foundry/deploys/lovStEth/OrigamiLovStEthTestConstants.t.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";

struct ExternalContracts {
    IERC20 wethToken;
    IERC20 wstEthToken;
    IERC20 stEthToken;

    IAggregatorV3Interface clStEthToEthOracle;
}

struct LovTokenContracts {
    OrigamiLovToken lovStEth;
    OrigamiLovTokenFlashAndBorrowManager lovStEthManager;
    OrigamiStableChainlinkOracle stEthToEthOracle;
    OrigamiWstEthToEthOracle wstEthToEthOracle;
    IOrigamiSwapper swapper;
    OrigamiAaveV3FlashLoanProvider flashLoanProvider;
    OrigamiAaveV3BorrowAndLend borrowLend;
}

/* solhint-disable max-states-count */
contract OrigamiLovStEthTestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
    IERC20 public wethToken;
    IERC20 public wstEthToken;
    IERC20 public stEthToken;
    IAggregatorV3Interface public clStEthToEthOracle;
    
    /**
     * core contracts
     */
    TokenPrices public tokenPrices;

    /**
     * LovStEth contracts
     */
    OrigamiLovToken public lovStEth;
    OrigamiLovTokenFlashAndBorrowManager public lovStEthManager;
    OrigamiStableChainlinkOracle public stEthToEthOracle;
    OrigamiWstEthToEthOracle public wstEthToEthOracle;
    IOrigamiSwapper public swapper;
    OrigamiAaveV3FlashLoanProvider public flashLoanProvider;
    OrigamiAaveV3BorrowAndLend public borrowLend;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.wethToken = wethToken;
        externalContracts.wstEthToken = wstEthToken;
        externalContracts.stEthToken = stEthToken;
        externalContracts.clStEthToEthOracle = clStEthToEthOracle;

        lovTokenContracts.lovStEth = lovStEth;
        lovTokenContracts.lovStEthManager = lovStEthManager;
        lovTokenContracts.stEthToEthOracle = stEthToEthOracle;
        lovTokenContracts.wstEthToEthOracle = wstEthToEthOracle;
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

        wethToken = new DummyMintableToken(owner, "wETH", "wETH", 18);
        wstEthToken = new DummyMintableToken(owner, "wstETH", "wstETH", 18);
        stEthToken = new DummyMintableToken(owner, "stETH", "stETH", 18);

        swapper = new DummyLovTokenSwapper();

        clStEthToEthOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 18446744073709552516,
                answer: 0.9987854203488546e18,
                startedAt: 1706225627,
                updatedAtLag: 1706225627,
                answeredInRound: 18446744073709552516
            }),
            18
        );

        _setupLovStEth();
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
            wethToken = IERC20(Constants.WETH_ADDRESS);
            wstEthToken = IERC20(Constants.WSTETH_ADDRESS);
            stEthToken = IERC20(Constants.STETH_ADDRESS);

            swapper = new OrigamiDexAggregatorSwapper(owner, Constants.ONE_INCH_ROUTER);

            // https://data.chain.link/feeds/ethereum/mainnet/steth-eth
            clStEthToEthOracle = IAggregatorV3Interface(Constants.STETH_ETH_ORACLE);
        }

        _setupLovStEth();
        return getContracts();
    }

    function _setupLovStEth() private {
        stEthToEthOracle = new OrigamiStableChainlinkOracle(
            owner,
            "stETH/ETH",
            address(stEthToken),
            Constants.STETH_DECIMALS,
            address(wethToken),
            Constants.ETH_DECIMALS,
            Constants.STETH_ETH_HISTORIC_STABLE_PRICE,
            address(clStEthToEthOracle),
            Constants.STETH_ETH_STALENESS_THRESHOLD,
            Range.Data(Constants.STETH_ETH_MIN_THRESHOLD, Constants.STETH_ETH_MAX_THRESHOLD)
        );
        wstEthToEthOracle = new OrigamiWstEthToEthOracle(
            "wstETH/ETH",
            address(wstEthToken),
            Constants.WSTETH_DECIMALS,
            address(wethToken),
            Constants.ETH_DECIMALS,
            address(stEthToken),
            address(stEthToEthOracle)
        );

        flashLoanProvider = new OrigamiAaveV3FlashLoanProvider(Constants.SPARK_POOL_ADDRESS_PROVIDER);

        lovStEth = new OrigamiLovToken(
            owner,
            "Origami LovStEth",
            "LovStEth",
            Constants.LOV_ETH_PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices)
        );
        borrowLend = new OrigamiAaveV3BorrowAndLend(
            owner,
            address(wstEthToken),
            address(wethToken),
            Constants.SPARK_POOL,
            lovStEth.decimals(),
            Constants.SPARK_EMODE_ETH
        );
        lovStEthManager = new OrigamiLovTokenFlashAndBorrowManager(
            owner,
            address(wstEthToken),
            address(wethToken),
            address(lovStEth),
            address(flashLoanProvider),
            address(borrowLend)
        );

        _postDeployLovStEth();
    }

    function _postDeployLovStEth() private {
        userALRange = Range.Data(Constants.USER_AL_FLOOR, Constants.USER_AL_CEILING);
        rebalanceALRange = Range.Data(Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);

        borrowLend.setPositionOwner(address(lovStEthManager));

        // Initial setup of config.
        lovStEthManager.setOracle(address(wstEthToEthOracle));
        lovStEthManager.setUserALRange(userALRange.floor, userALRange.ceiling);
        lovStEthManager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
        lovStEthManager.setSwapper(address(swapper));
        lovStEthManager.setFeeConfig(Constants.LOV_ETH_MIN_DEPOSIT_FEE_BPS, Constants.LOV_ETH_MIN_EXIT_FEE_BPS, Constants.LOV_ETH_FEE_LEVERAGE_FACTOR);

        _setExplicitAccess(
            lovStEthManager, 
            overlord, 
            OrigamiLovTokenFlashAndBorrowManager.rebalanceUp.selector, 
            OrigamiLovTokenFlashAndBorrowManager.rebalanceDown.selector, 
            true
        );

        lovStEth.setManager(address(lovStEthManager));

        // Only needed in lovStEthManager tests so we can mint/burn
        // (ordinarily lovStEth will do this via internal fns -- but we prank using foundry)
        lovStEth.addMinter(address(lovStEth));
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