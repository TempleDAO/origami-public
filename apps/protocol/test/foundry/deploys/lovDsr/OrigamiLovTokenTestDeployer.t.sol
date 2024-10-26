pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { RepricingToken } from "contracts/common/RepricingToken.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiCircuitBreakerProxy } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerProxy.sol";
import { OrigamiCircuitBreakerAllUsersPerPeriod } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol";
import { LinearWithKinkInterestRateModel } from "contracts/common/interestRate/LinearWithKinkInterestRateModel.sol";
import { OrigamiOToken } from "contracts/investments/OrigamiOToken.sol";
import { OrigamiInvestmentVault } from "contracts/investments/OrigamiInvestmentVault.sol";
import { OrigamiLendingSupplyManager } from "contracts/investments/lending/OrigamiLendingSupplyManager.sol";
import { OrigamiLendingClerk } from "contracts/investments/lending/OrigamiLendingClerk.sol";
import { OrigamiDebtToken } from "contracts/investments/lending/OrigamiDebtToken.sol";
import { OrigamiLendingRewardsMinter } from "contracts/investments/lending/OrigamiLendingRewardsMinter.sol";
import { OrigamiIdleStrategyManager } from "contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol";
import { OrigamiAaveV3IdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenErc4626Manager } from "contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";

import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyIdleStrategy } from "contracts/test/investments/lovToken/DummyIdleStrategy.m.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { MockSDaiToken } from "contracts/test/external/maker/MockSDaiToken.m.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiAbstractIdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

import { OrigamiLovTokenTestConstants as Constants } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestConstants.t.sol";

struct ExternalContracts {
    IERC20 daiToken;
    IERC20 usdcToken;
    IERC4626 sDaiToken;

    IAggregatorV3Interface clDaiUsdOracle;
    IAggregatorV3Interface clUsdcUsdOracle;
}

struct OUsdcContracts {
    OrigamiInvestmentVault ovUsdc;
    OrigamiOToken oUsdc;
    OrigamiLendingSupplyManager supplyManager;
    OrigamiLendingClerk lendingClerk;
    OrigamiIdleStrategyManager idleStrategyManager;
    OrigamiAbstractIdleStrategy idleStrategy;

    OrigamiDebtToken iUsdc;
    OrigamiLendingRewardsMinter rewardsMinter;
    OrigamiCircuitBreakerProxy cbProxy;
    OrigamiCircuitBreakerAllUsersPerPeriod cbUsdcBorrow;
    OrigamiCircuitBreakerAllUsersPerPeriod cbOUsdcExit;
    LinearWithKinkInterestRateModel globalInterestRateModel;
}

struct LovTokenContracts {
    OrigamiLovToken lovDsr;
    OrigamiLovTokenErc4626Manager lovDsrManager;
    OrigamiStableChainlinkOracle daiUsdOracle;
    OrigamiStableChainlinkOracle usdcUsdOracle;  // USDC = 6dp
    OrigamiStableChainlinkOracle iUsdcUsdOracle; // iUSDC = 18dp
    OrigamiCrossRateOracle daiUsdcOracle;  // USDC = 6dp
    OrigamiCrossRateOracle daiIUsdcOracle; // iUSDC = 18dp
    LinearWithKinkInterestRateModel borrowerInterestRateModel;
    IOrigamiSwapper swapper;
}

/* solhint-disable max-states-count */
contract OrigamiLovTokenTestDeployer {
    address public owner;
    address public feeCollector;
    address public overlord;

    /**
     * Either forked mainnet contracts, or mocks if non-forked
     */
    IERC20 public daiToken;
    IERC20 public usdcToken;
    IERC4626 public sDaiToken;
    IAggregatorV3Interface public clDaiUsdOracle;
    IAggregatorV3Interface public clUsdcUsdOracle;
    IOrigamiSwapper public swapper;
    OrigamiAbstractIdleStrategy public idleStrategy;

    /**
     * core contracts
     */
    OrigamiCircuitBreakerProxy public cbProxy;
    TokenPrices public tokenPrices;

    /**
     * ovUSDC contracts
     */
    OrigamiInvestmentVault public ovUsdc;
    OrigamiOToken public oUsdc;
    OrigamiLendingSupplyManager public supplyManager;
    OrigamiLendingClerk public lendingClerk;
    OrigamiIdleStrategyManager public idleStrategyManager;

    OrigamiDebtToken public iUsdc;
    OrigamiLendingRewardsMinter public rewardsMinter;

    OrigamiCircuitBreakerAllUsersPerPeriod public cbUsdcBorrow;
    OrigamiCircuitBreakerAllUsersPerPeriod public cbOUsdcExit;
    LinearWithKinkInterestRateModel public globalInterestRateModel;

    /**
     * lovDSR contracts
     */
    OrigamiLovToken public lovDsr;
    OrigamiLovTokenErc4626Manager public lovDsrManager;
    OrigamiStableChainlinkOracle public origamiDaiUsdOracle;
    OrigamiStableChainlinkOracle public origamiUsdcUsdOracle;  // USDC = 6dp
    OrigamiStableChainlinkOracle public origamiIUsdcUsdOracle; // iUSDC = 18dp
    OrigamiCrossRateOracle public daiUsdcOracle; // USDC = 6dp
    OrigamiCrossRateOracle public daiIUsdcOracle; // iUSDC = 18dp
    LinearWithKinkInterestRateModel public borrowerInterestRateModel;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function getContracts() public view returns (
        ExternalContracts memory externalContracts, 
        OUsdcContracts memory oUsdcContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        externalContracts.daiToken = daiToken;
        externalContracts.usdcToken = usdcToken;
        externalContracts.sDaiToken = sDaiToken;
        externalContracts.clDaiUsdOracle = clDaiUsdOracle;
        externalContracts.clUsdcUsdOracle = clUsdcUsdOracle;

        lovTokenContracts.lovDsr = lovDsr;
        lovTokenContracts.lovDsrManager = lovDsrManager;
        lovTokenContracts.daiUsdOracle = origamiDaiUsdOracle;
        lovTokenContracts.usdcUsdOracle = origamiUsdcUsdOracle;
        lovTokenContracts.iUsdcUsdOracle = origamiIUsdcUsdOracle;
        lovTokenContracts.daiUsdcOracle = daiUsdcOracle;
        lovTokenContracts.daiIUsdcOracle = daiIUsdcOracle;
        lovTokenContracts.borrowerInterestRateModel = borrowerInterestRateModel;
        lovTokenContracts.swapper = swapper;

        oUsdcContracts.ovUsdc = ovUsdc;
        oUsdcContracts.oUsdc = oUsdc;
        oUsdcContracts.supplyManager = supplyManager;
        oUsdcContracts.lendingClerk = lendingClerk;
        oUsdcContracts.idleStrategyManager = idleStrategyManager;
        oUsdcContracts.idleStrategy = idleStrategy;

        oUsdcContracts.iUsdc = iUsdc;
        oUsdcContracts.rewardsMinter = rewardsMinter;
        oUsdcContracts.cbProxy = cbProxy;
        oUsdcContracts.cbUsdcBorrow = cbUsdcBorrow;
        oUsdcContracts.cbOUsdcExit = cbOUsdcExit;
        oUsdcContracts.globalInterestRateModel = globalInterestRateModel;
    }

    function deployNonForked(
        address _owner, 
        address _feeCollector, 
        address _overlord
    ) external returns (
        ExternalContracts memory externalContracts, 
        OUsdcContracts memory oUsdcContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        owner = _owner;
        feeCollector = _feeCollector;
        overlord = _overlord;

        daiToken = new DummyMintableToken(owner, "DAI", "DAI", 18);
        usdcToken = new DummyMintableToken(owner, "USDC", "USDC", 6);
        sDaiToken = new MockSDaiToken(daiToken);
        MockSDaiToken(address(sDaiToken)).setInterestRate(Constants.SDAI_INTEREST_RATE);

        swapper = new DummyLovTokenSwapper();
        idleStrategy = new DummyIdleStrategy(owner, address(usdcToken), 10_000);

        clDaiUsdOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00044127e8,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            8
        );
        clUsdcUsdOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00006620e8,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            8
        );

        _setupOUsdc();
        _setupLovDsr();
        return getContracts();
    }

    function deployForked(
        address _owner, 
        address _feeCollector, 
        address _overlord
    ) external returns (  
        ExternalContracts memory externalContracts, 
        OUsdcContracts memory oUsdcContracts, 
        LovTokenContracts memory lovTokenContracts
    ) {
        owner = _owner;
        feeCollector = _feeCollector;
        overlord = _overlord;

        {
            daiToken = IERC20(Constants.DAI_ADDRESS);
            usdcToken = IERC20(Constants.USDC_ADDRESS);
            sDaiToken = IERC4626(Constants.SDAI_ADDRESS);

            swapper = new OrigamiDexAggregatorSwapper(owner);
            OrigamiDexAggregatorSwapper(address(swapper)).whitelistRouter(Constants.ONE_INCH_ROUTER, true);

            idleStrategy = new OrigamiAaveV3IdleStrategy(owner, address(usdcToken), Constants.AAVE_POOL_ADDRESS_PROVIDER);

            // https://data.chain.link/ethereum/mainnet/stablecoins/dai-usd
            clDaiUsdOracle = IAggregatorV3Interface(Constants.DAI_USD_ORACLE);

            // https://data.chain.link/ethereum/mainnet/stablecoins/usdc-usd
            clUsdcUsdOracle = IAggregatorV3Interface(Constants.USDC_USD_ORACLE);
        }

        _setupOUsdc();
        _setupLovDsr();
        return getContracts();
    }

    function _setupOUsdc() private {
        idleStrategyManager = new OrigamiIdleStrategyManager(owner, address(usdcToken));

        iUsdc = new OrigamiDebtToken("Origami iUSDC", "iUSDC", owner);
        cbProxy = new OrigamiCircuitBreakerProxy(owner);
        tokenPrices = new TokenPrices(30);
    
        oUsdc = new OrigamiOToken(owner, "Origami USDC Token", "oUSDC");
        ovUsdc = new OrigamiInvestmentVault(
            owner,
            "Origami USDC Vault",
            "ovUSDC",
            address(oUsdc),
            address(tokenPrices),
            Constants.OUSDC_PERFORMANCE_FEE_BPS,
            2 days // Two days vesting of reserves
        );

        supplyManager = new OrigamiLendingSupplyManager(
            owner, 
            address(usdcToken), 
            address(oUsdc),
            address(ovUsdc),
            address(cbProxy),
            feeCollector,
            Constants.OUSDC_EXIT_FEE_BPS
        );

        cbUsdcBorrow = new OrigamiCircuitBreakerAllUsersPerPeriod(
            owner, 
            address(cbProxy), 
            26 hours, 
            13, 
            Constants.CB_DAILY_USDC_BORROW_LIMIT
        );
        cbOUsdcExit = new OrigamiCircuitBreakerAllUsersPerPeriod(
            owner, 
            address(cbProxy), 
            26 hours, 
            13, 
            Constants.CB_DAILY_OUSDC_EXIT_LIMIT
        );

        globalInterestRateModel = new LinearWithKinkInterestRateModel(
            owner,
            Constants.GLOBAL_IR_AT_0_UR,     // 5% interest rate (rate% at 0% UR)
            Constants.GLOBAL_IR_AT_100_UR,   // 20% percent interest rate (rate% at 100% UR)
            Constants.UTILIZATION_RATIO_90,  // 90% utilization (UR for when the kink starts)
            Constants.GLOBAL_IR_AT_KINK      // 10% percent interest rate (rate% at kink% UR)
        );

        rewardsMinter = new OrigamiLendingRewardsMinter(
            owner,
            address(oUsdc),
            address(ovUsdc),
            address(iUsdc),
            Constants.OUSDC_CARRY_OVER_BPS, // Carry over 5%
            feeCollector
        );

        lendingClerk = new OrigamiLendingClerk(
            owner, 
            address(usdcToken), 
            address(oUsdc), 
            address(idleStrategyManager),
            address(iUsdc),
            address(cbProxy),
            address(supplyManager),
            address(globalInterestRateModel)
        );

        _postDeployOusdc();
    }

    function _postDeployOusdc() private {
        // Setup the circuit breaker for daily borrows of USDC
        cbProxy.setIdentifierForCaller(address(lendingClerk), "USDC_BORROW");
        cbProxy.setCircuitBreaker(keccak256("USDC_BORROW"), address(usdcToken), address(cbUsdcBorrow));

        // Setup the circuit breaker for exits of USDC from oUSDC
        cbProxy.setIdentifierForCaller(address(supplyManager), "OUSDC_EXIT");
        cbProxy.setCircuitBreaker(keccak256("OUSDC_EXIT"), address(oUsdc), address(cbOUsdcExit));

        // Hook up the lendingClerk to the supplyManager
        supplyManager.setLendingClerk(address(lendingClerk));

        // Set the fee collector for the oUSDC exit fees to be the ovUSDC rewards minter
        // Exit fees are recycled into pending rewards for remaining vault users.
        supplyManager.setFeeCollector(address(rewardsMinter));

        // Hook up the supplyManager to oUsdc
        oUsdc.setManager(address(supplyManager));

        // Allow the lendingClerk to mint/burn iUSDC
        iUsdc.setMinter(address(lendingClerk), true);

        // Set the idle strategy interest rate
        lendingClerk.setIdleStrategyInterestRate(Constants.IDLE_STRATEGY_IR);

        // Allow the LendingManager allocate/withdraw from the idle strategy
        _setExplicitAccess(
            idleStrategyManager, 
            address(lendingClerk), 
            OrigamiIdleStrategyManager.allocate.selector, 
            OrigamiIdleStrategyManager.withdraw.selector, 
            true
        );

        // Allow the idle strategy manager to allocate/withdraw to the aave strategy
        _setExplicitAccess(
            idleStrategy, 
            address(idleStrategyManager), 
            OrigamiIdleStrategyManager.allocate.selector, 
            OrigamiIdleStrategyManager.withdraw.selector, 
            true
        );
        
        // Allow the RewardsMinter to mint new oUSDC and add as pending reserves into ovUSDC
        oUsdc.addMinter(address(rewardsMinter));
        _setExplicitAccess(
            ovUsdc,
            address(rewardsMinter),
            RepricingToken.addPendingReserves.selector,
            true
        );

        // Set the idle strategy config
        idleStrategyManager.setIdleStrategy(address(idleStrategy));
        idleStrategyManager.setThresholds(Constants.AAVE_STRATEGY_DEPOSIT_THRESHOLD, Constants.AAVE_STRATEGY_WITHDRAWAL_THRESHOLD);
        idleStrategyManager.setDepositsEnabled(true);
    }

    function _setupLovDsr() private {
        origamiDaiUsdOracle = new OrigamiStableChainlinkOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "DAI/USD",
                address(daiToken),
                Constants.DAI_DECIMALS,
                Constants.INTERNAL_USD_ADDRESS,
                Constants.USD_DECIMALS
            ),
            Constants.DAI_USD_HISTORIC_STABLE_PRICE,
            address(clDaiUsdOracle),
            Constants.DAI_USD_STALENESS_THRESHOLD,
            Range.Data(Constants.DAI_USD_MIN_THRESHOLD, Constants.DAI_USD_MAX_THRESHOLD),
            true, // Chainlink does use roundId
            true // It does use lastUpdatedAt
        );
        origamiUsdcUsdOracle = new OrigamiStableChainlinkOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "USDC/USD",
                address(usdcToken),
                Constants.USDC_DECIMALS,
                Constants.INTERNAL_USD_ADDRESS,
                Constants.USD_DECIMALS
            ),
            Constants.USDC_USD_HISTORIC_STABLE_PRICE,
            address(clUsdcUsdOracle),
            Constants.USDC_USD_STALENESS_THRESHOLD,
            Range.Data(Constants.USDC_USD_MIN_THRESHOLD, Constants.USDC_USD_MAX_THRESHOLD),
            true, // Chainlink does use roundId
            true // It does use lastUpdatedAt
        );
        origamiIUsdcUsdOracle = new OrigamiStableChainlinkOracle(
            owner,
            IOrigamiOracle.BaseOracleParams(
                "iUSDC/USD",
                // Intentionally uses the USDC token address
                // iUSDC oracle is just a proxy for the USDC price, 
                // but with 18dp instead of 6
                address(usdcToken),
                Constants.IUSDC_DECIMALS,
                Constants.INTERNAL_USD_ADDRESS,
                Constants.USD_DECIMALS
            ),
            Constants.USDC_USD_HISTORIC_STABLE_PRICE,
            address(clUsdcUsdOracle),
            Constants.USDC_USD_STALENESS_THRESHOLD,
            Range.Data(Constants.USDC_USD_MIN_THRESHOLD, Constants.USDC_USD_MAX_THRESHOLD),
            true,
            true
        );
        daiUsdcOracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "DAI/USDC",
                address(daiToken),
                Constants.DAI_DECIMALS,
                address(usdcToken),
                Constants.USDC_DECIMALS
            ),
            address(origamiDaiUsdOracle),
            address(origamiUsdcUsdOracle),
            address(0)
        );
        daiIUsdcOracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "DAI/iUSDC",
                address(daiToken),
                Constants.DAI_DECIMALS,
                // Intentionally uses the USDC token address
                // iUSDC oracle is just a proxy for the USDC price, 
                // but with 18dp instead of 6
                address(usdcToken),
                Constants.IUSDC_DECIMALS
            ),
            address(origamiDaiUsdOracle),
            address(origamiIUsdcUsdOracle),
            address(0)
        );

        lovDsr = new OrigamiLovToken(
            owner,
            "Origami lovDSR",
            "lovDSR",
            Constants.LOV_DSR_PERFORMANCE_FEE_BPS,
            feeCollector,
            address(tokenPrices),
            type(uint256).max
        );
        lovDsrManager = new OrigamiLovTokenErc4626Manager(
            owner,
            address(daiToken),
            address(usdcToken),
            address(sDaiToken),
            address(lovDsr)
        );

        borrowerInterestRateModel = new LinearWithKinkInterestRateModel(
            owner,
            Constants.BORROWER_IR_AT_0_UR,   // 10% interest rate (rate% at 0% UR)
            Constants.BORROWER_IR_AT_100_UR, // 25% percent interest rate (rate% at 100% UR)
            Constants.UTILIZATION_RATIO_90,  // 90% utilization (UR for when the kink starts)
            Constants.BORROWER_IR_AT_KINK    // 15% percent interest rate (rate% at kink% UR)
        );

        _postDeployLovDsr();
    }

    function _postDeployLovDsr() private {
        userALRange = Range.Data(Constants.USER_AL_FLOOR, Constants.USER_AL_CEILING);
        rebalanceALRange = Range.Data(Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);

        // Initial setup of config.
        lovDsrManager.setLendingClerk(address(lendingClerk));
        lovDsrManager.setOracle(address(daiIUsdcOracle));
        lovDsrManager.setUserALRange(userALRange.floor, userALRange.ceiling);
        lovDsrManager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
        lovDsrManager.setSwapper(address(swapper));
        lovDsrManager.setFeeConfig(
            Constants.LOV_DSR_MIN_DEPOSIT_FEE_BPS, 
            Constants.LOV_DSR_MIN_EXIT_FEE_BPS, 
            Constants.LOV_DSR_FEE_LEVERAGE_FACTOR
        );

        _setExplicitAccess(
            lovDsrManager, 
            overlord, 
            OrigamiLovTokenErc4626Manager.rebalanceUp.selector, 
            OrigamiLovTokenErc4626Manager.rebalanceDown.selector, 
            true
        );

        lovDsr.setManager(address(lovDsrManager));

        // Only needed in lovDsrManager tests so we can mint/burn
        // (ordinarily lovDSR will do this via internal fns -- but we prank using foundry)
        lovDsr.addMinter(address(lovDsr));

        lendingClerk.addBorrower(address(lovDsrManager), address(borrowerInterestRateModel), Constants.LOV_DSR_IUSDC_BORROW_CAP);
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