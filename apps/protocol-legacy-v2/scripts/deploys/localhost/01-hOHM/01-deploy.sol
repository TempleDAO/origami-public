// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script } from "forge-std/Script.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IGOHM } from "contracts/interfaces/external/olympus/IGOHM.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";
import { Kernel } from "contracts/test/external/olympus/src/Kernel.sol";
import { RolesAdmin, Actions } from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";
import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";
import { IMonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { DelegateEscrowFactory } from "contracts/test/external/olympus/src/external/cooler/DelegateEscrowFactory.sol";
import { OlympusGovDelegation } from "contracts/test/external/olympus/src/modules/DLGTE/OlympusGovDelegation.sol";
import { CoolerLtvOracle } from "contracts/test/external/olympus/src/policies/cooler/CoolerLtvOracle.sol";
import { CoolerTreasuryBorrower } from "contracts/test/external/olympus/src/policies/cooler/CoolerTreasuryBorrower.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { MockRolesAdminPolicy } from "./MockRolesAdminPolicy.sol";
import { MockOhmMinterPolicy } from "./MockOhmMinterPolicy.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { OrigamiHOhmManager } from "contracts/investments/olympus/OrigamiHOhmManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiCoolerMigrator } from "contracts/investments/olympus/OrigamiCoolerMigrator.sol";
import { IOrigamiCoolerMigrator } from "contracts/interfaces/investments/olympus/IOrigamiCoolerMigrator.sol";
import { ICooler } from "contracts/interfaces/external/olympus/IOlympusCoolerV1.sol";
import { IUniswapV3Factory } from "contracts/interfaces/external/uniswap/IUniswapV3Factory.sol";
import { IUniswapV3NonfungiblePositionManager } from "contracts/interfaces/external/uniswap/IUniswapV3NonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";
import { sqrt } from "@prb/math/src/Common.sol";

contract TestnetMonoCoolerDeployer is Script, StdAssertions {
    using OrigamiMath for uint256;

    uint96 internal constant DEFAULT_OLTV = 2_961.64e18; // [USDS/gOHM] == ~11 [USDS/OHM]
    uint96 internal constant DEFAULT_OLTV_MAX_DELTA = 1000e18; // 1000 USDS
    uint32 internal constant DEFAULT_OLTV_MIN_TARGET_TIME_DELTA = 1 weeks;
    uint96 internal constant DEFAULT_OLTV_MAX_RATE_OF_CHANGE = uint96(10e18) / 1 days; // 10 USDS / day
    uint16 internal constant DEFAULT_LLTV_MAX_PREMIUM_BPS = 333;
    uint16 internal constant DEFAULT_LLTV_PREMIUM_BPS = 100; // LLTV is 1% above OLTV

    uint96 internal constant DEFAULT_INTEREST_RATE_BPS = 0.00498754151103897e18; // 0.5% APY
    uint256 internal constant DEFAULT_MIN_DEBT_REQUIRED = 1_000e18;

    address internal constant ORIGAMI_MULTISIG = 0x781B4c57100738095222bd92D37B07ed034AB696;

    uint16 internal constant HOHM_PERFORMANCE_FEE = 330; // 3.3%
    uint16 internal constant HOHM_EXIT_FEE_BPS = 100; // 1%

    // Starting share price:
    // 1 hOHM = 0.000003714158 gOHM
    //   1 [OHM] / 269.24 [OHM/gOHM] / 1000
    // 1 hOHM = 0.011 USDS
    //   11 [USDS/OHM] / 1000
    uint256 internal constant OHM_PER_GOHM = 269.24e18;
    uint256 internal constant HOHM_SEED_GOHM_AMOUNT = 10e18;
    uint256 internal constant HOHM_SEED_HOHM_SHARES = HOHM_SEED_GOHM_AMOUNT * OHM_PER_GOHM * 1_000 / OrigamiMath.WAD;

    // Intentionally at the starting cooler origination LTV
    // This means no surplus to start - but as the OLTV increases (per second) hOHM can borrow more from cooler.
    uint256 internal constant HOHM_SEED_USDS_AMOUNT = HOHM_SEED_GOHM_AMOUNT * DEFAULT_OLTV / OrigamiMath.WAD;
    uint256 internal constant HOHM_MAX_TOTAL_SUPPLY = type(uint256).max;

    // The uniswap v3 fee param for sUSDS/hOHM
    uint24 internal constant SUSDS_HOHM_FEE = 10_000; // 1%

    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = 887272;

    IERC20 internal constant ohmToken = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    IGOHM internal constant gOhmToken = IGOHM(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
    IERC4626 internal constant sUsdsToken = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
    IERC20 internal constant usdsToken = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    IERC20 internal constant daiToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    Kernel internal constant kernel = Kernel(0x2286d7f9639e8158FaD1169e76d1FbC38247f54b);
    IOlympusStaking internal constant staking = IOlympusStaking(0xB63cac384247597756545b500253ff8E607a8020);
    RolesAdmin internal constant rolesAdmin = RolesAdmin(0xb216d714d91eeC4F7120a732c11428857C659eC8);
    
    address internal constant clearinghousev1 = 0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880;
    address internal constant clearinghousev2 = 0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c;
    address internal constant clearinghousev3 = 0x1e094fE00E13Fd06D64EeA4FB3cD912893606fE0;

    address internal constant daiUsdsConverter = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    address internal constant daiFlashLoanLender = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
    address internal constant exampleCoolerOwner = 0xB4fb31E7B1471A8e52dD1e962A281a732EaD59c1;

    IUniswapV3Factory internal uniV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IUniswapV3NonfungiblePositionManager internal uniV3PositionManager = IUniswapV3NonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    DelegateEscrowFactory internal escrowFactory;
    OlympusGovDelegation internal DLGTE;
    CoolerLtvOracle internal ltvOracle;
    CoolerTreasuryBorrower internal treasuryBorrower;
    MonoCooler internal monoCooler;

    MockRolesAdminPolicy internal mockRolesAdmin;
    MockOhmMinterPolicy internal mockOhmMinter;

    OrigamiHOhmVault internal hOhmVault;
    OrigamiHOhmManager internal hOhmManager;
    TokenPrices internal tokenPrices;

    OrigamiCoolerMigrator internal hOhmMigrator;

    IUniswapV3Pool internal hOhmSusdsPool;

    function run() external {
        bytes32 dummySalt = bytes32(0);

        // Create our mock policies which can freely grant roles and mint OHM
        vm.startBroadcast();
        mockRolesAdmin = new MockRolesAdminPolicy{salt: dummySalt}(kernel);
        mockOhmMinter = new MockOhmMinterPolicy{salt: dummySalt}(kernel);
        vm.stopBroadcast();

        monoCoolerDeploy(dummySalt);
        monoCoolerInstallModulesAndPolicies();
        monoCoolerSetAccessAndEnable();

        // Start the LTV drip in cooler
        vm.startBroadcast();
        ltvOracle.setOriginationLtvAt(uint96(uint256(11.5e18) * OHM_PER_GOHM / 1e18), uint32(vm.getBlockTimestamp()) + 182.5 days);
        vm.stopBroadcast();

        doBorrow(msg.sender);

        depoloyHohm(dummySalt);
        seedDeposit(ORIGAMI_MULTISIG, HOHM_MAX_TOTAL_SUPPLY);
        seedUniV3();

        migrateCoolers();

        console.log("============= Contract Addresses: ===============");
        console.log("");
        console.log("~~ External Tokens ~~");
        console.log("OHM:", address(ohmToken));
        console.log("gOHM:", address(gOhmToken));
        console.log("USDS:", address(usdsToken));
        console.log("sUSDS:", address(sUsdsToken));
        console.log("sUSDS/hOHM UniV3 Pool:", address(hOhmSusdsPool));
        console.log("");
        console.log("~~ Olympus ~~");
        console.log("kernel:", address(kernel));
        console.log("staking:", address(staking));
        console.log("DLGTE:", address(DLGTE));
        console.log("mockRolesAdmin:", address(mockRolesAdmin));
        console.log("mockOhmMinter:", address(mockOhmMinter));
        console.log("escrowFactory:", address(escrowFactory));
        console.log("ltvOracle:", address(ltvOracle));
        console.log("treasuryBorrower:", address(treasuryBorrower));
        console.log("monoCooler:", address(monoCooler));
        console.log("");
        console.log("~~ Origami ~~");
        console.log("TokenPrices:", address(tokenPrices));
        console.log("hOHM Vault:", address(hOhmVault));
        console.log("hOHM Manager:", address(hOhmManager));
        console.log("");
        console.log("==================== Status: ====================");
        console.log("MonoCooler totalCollateral:", monoCooler.totalCollateral());
        console.log("MonoCooler totalDebt:", monoCooler.totalDebt());
        console.log("hOHM TotalSupply:", hOhmVault.totalSupply());
        console.log("Multisig hOHM Shares:", hOhmVault.balanceOf(ORIGAMI_MULTISIG));
        console.log("Migrated user hOHM Shares:", hOhmVault.balanceOf(exampleCoolerOwner));
        console.log("=================================================");   
    }

    function monoCoolerDeploy(bytes32 salt) internal {
        vm.startBroadcast();

        escrowFactory = new DelegateEscrowFactory{salt: salt}(address(gOhmToken));
        DLGTE = new OlympusGovDelegation{salt: salt}(kernel, address(gOhmToken), escrowFactory);

        ltvOracle = new CoolerLtvOracle{salt: salt}(
            address(kernel),
            address(gOhmToken),
            address(usdsToken),
            DEFAULT_OLTV, 
            DEFAULT_OLTV_MAX_DELTA, 
            DEFAULT_OLTV_MIN_TARGET_TIME_DELTA, 
            DEFAULT_OLTV_MAX_RATE_OF_CHANGE,
            DEFAULT_LLTV_MAX_PREMIUM_BPS,
            DEFAULT_LLTV_PREMIUM_BPS
        );

        monoCooler = new MonoCooler{salt: salt}(
            address(ohmToken),
            address(gOhmToken),
            address(staking),
            address(kernel),
            address(ltvOracle),
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );

        treasuryBorrower = new CoolerTreasuryBorrower{salt: salt}(
            address(kernel),
            address(sUsdsToken)
        );

        monoCooler.setTreasuryBorrower(address(treasuryBorrower));

        vm.stopBroadcast();
    }

    function monoCoolerInstallModulesAndPolicies() internal {
        vm.startBroadcast(kernel.executor());

        kernel.executeAction(Actions.InstallModule, address(DLGTE));
        kernel.executeAction(Actions.ActivatePolicy, address(monoCooler));
        kernel.executeAction(Actions.ActivatePolicy, address(ltvOracle));
        kernel.executeAction(Actions.ActivatePolicy, address(treasuryBorrower));

        kernel.executeAction(Actions.ActivatePolicy, address(mockRolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(mockOhmMinter));

        vm.stopBroadcast();
    }

    function monoCoolerSetAccessAndEnable() internal {
        vm.startBroadcast();

        // Grant roles and enable policy
        mockRolesAdmin.grantRole("treasuryborrower_cooler", address(monoCooler));
        mockRolesAdmin.grantRole("admin", msg.sender);
        treasuryBorrower.enable(bytes(""));

        vm.stopBroadcast();
    }

    function delegationRequest(
        address to,
        uint256 amount
    ) internal pure returns (IDLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new IDLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = IDLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }

    function mintGohm(address to, uint256 amount) internal {
        // Mint OHM then stake to get gOHM
        uint256 ohmAmount = gOhmToken.balanceFrom(amount);
        ohmToken.approve(address(staking), ohmAmount);
        mockOhmMinter.mintOhm(to, ohmAmount);
        staking.stake(to, ohmAmount, false, true);
    }

    function doBorrow(address caller) private {
        uint128 collateralAmount = 10e18; // [gOHM]
        uint128 borrowAmount = 25_000e18; // [USDS]

        vm.startBroadcast(caller);
        mintGohm(caller, collateralAmount);
        gOhmToken.approve(address(monoCooler), collateralAmount);

        monoCooler.addCollateral(collateralAmount, caller, delegationRequest(caller, collateralAmount));
        monoCooler.borrow(borrowAmount, caller, caller);

        vm.stopBroadcast();

        checkAccountPosition(
            caller,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: borrowAmount,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.196502560000000000e18,
                currentLtv: 2_500e18,
                totalDelegated: collateralAmount,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );
    }

    function checkAccountPosition(address account, IMonoCooler.AccountPosition memory expectedPosition) internal view {
        IMonoCooler.AccountPosition memory position = monoCooler.accountPosition(account);
        assertEq(position.collateral, expectedPosition.collateral, "AccountPosition::collateral");
        assertEq(
            position.currentDebt,
            expectedPosition.currentDebt,
            "AccountPosition::currentDebt"
        );
        assertEq(
            position.maxOriginationDebtAmount,
            expectedPosition.maxOriginationDebtAmount,
            "AccountPosition::maxOriginationDebtAmount"
        );
        assertEq(
            position.liquidationDebtAmount,
            expectedPosition.liquidationDebtAmount,
            "AccountPosition::liquidationDebtAmount"
        );
        assertEq(
            position.healthFactor,
            expectedPosition.healthFactor,
            "AccountPosition::healthFactor"
        );
        assertEq(position.currentLtv, expectedPosition.currentLtv, "AccountPosition::currentLtv");
        assertEq(
            position.totalDelegated,
            expectedPosition.totalDelegated,
            "AccountPosition::totalDelegated"
        );
        assertEq(
            position.numDelegateAddresses,
            expectedPosition.numDelegateAddresses,
            "AccountPosition::numDelegateAddresses"
        );
        assertEq(
            position.maxDelegateAddresses,
            expectedPosition.maxDelegateAddresses,
            "AccountPosition::maxDelegateAddresses"
        );
        
        assertEq(monoCooler.accountDebt(account), expectedPosition.currentDebt, "accountDebt()");
        assertEq(monoCooler.accountCollateral(account), expectedPosition.collateral, "accountCollateral()");
    }

    function depoloyHohm(bytes32 salt) internal {
        vm.startBroadcast(ORIGAMI_MULTISIG);
        {
            // Can't use create2 here, because the owner would be the Create2Deployer
            tokenPrices = new TokenPrices(30);

            hOhmVault = new OrigamiHOhmVault{salt: salt}(
                ORIGAMI_MULTISIG, 
                "Origami hOHM", 
                "hOHM",
                address(gOhmToken),
                address(tokenPrices)
            );

            hOhmManager = new OrigamiHOhmManager{salt: salt}(
                ORIGAMI_MULTISIG, 
                address(hOhmVault),
                address(monoCooler),
                address(sUsdsToken),
                HOHM_PERFORMANCE_FEE,
                ORIGAMI_MULTISIG
            );

            address[3] memory clearinghouses = [clearinghousev1, clearinghousev2, clearinghousev3];
            hOhmMigrator = new OrigamiCoolerMigrator{salt: salt}(
                ORIGAMI_MULTISIG,
                address(hOhmVault),
                address(gOhmToken),
                address(daiToken),
                address(usdsToken),
                daiUsdsConverter,
                address(monoCooler),
                daiFlashLoanLender,
                clearinghouses
            );
        }
        vm.stopBroadcast();

        vm.startBroadcast(ORIGAMI_MULTISIG);
        {
            hOhmVault.setManager(address(hOhmManager));
            hOhmManager.setExitFees(HOHM_EXIT_FEE_BPS);

            tokenPrices.setTokenPriceFunction(
                address(usdsToken),
                abi.encodeCall(TokenPrices.scalar, (0.999e30))
            );
            tokenPrices.setTokenPriceFunction(
                address(ohmToken),
                abi.encodeCall(TokenPrices.scalar, (22.5e30))
            );
            tokenPrices.setTokenPriceFunction(
                address(gOhmToken),
                abi.encodeCall(TokenPrices.mul, (
                    abi.encodeCall(TokenPrices.tokenPrice, (address(ohmToken))),
                    abi.encodeCall(TokenPrices.scalar, (OHM_PER_GOHM * 10 ** (30-18)))
                ))
            );
            tokenPrices.setTokenPriceFunction(
                address(hOhmVault),
                abi.encodeCall(TokenPrices.tokenizedBalanceSheetTokenPrice, (address(hOhmVault)))
            );
        }
        vm.stopBroadcast();
    }

    function seedDeposit(address account, uint256 maxSupply) internal {
        uint256[] memory assetAmounts = new uint256[](1);
        assetAmounts[0] = HOHM_SEED_GOHM_AMOUNT;
        uint256[] memory liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = HOHM_SEED_USDS_AMOUNT;

        vm.startBroadcast(account);
        mintGohm(account, assetAmounts[0]);
        gOhmToken.approve(address(hOhmVault), assetAmounts[0]);
        vm.stopBroadcast();

        vm.startBroadcast(account);
        hOhmVault.seed(assetAmounts, liabilityAmounts, HOHM_SEED_HOHM_SHARES, account, maxSupply);
        vm.stopBroadcast();
    }

    function _convertLoansForMigration(
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory previewLoans
    ) internal pure returns (IOrigamiCoolerMigrator.AllCoolerLoansMigration memory migrateLoans) {
        migrateLoans.v1_1.cooler = previewLoans.v1_1.cooler;
        migrateLoans.v1_1.loanIds = new uint256[](previewLoans.v1_1.loans.length);
        for (uint256 i; i < previewLoans.v1_1.loans.length; ++i) {
            migrateLoans.v1_1.loanIds[i] = previewLoans.v1_1.loans[i].loanId;
        }

        migrateLoans.v1_2.cooler = previewLoans.v1_2.cooler;
        migrateLoans.v1_2.loanIds = new uint256[](previewLoans.v1_2.loans.length);
        for (uint256 i; i < previewLoans.v1_2.loans.length; ++i) {
            migrateLoans.v1_2.loanIds[i] = previewLoans.v1_2.loans[i].loanId;
        }

        migrateLoans.v1_3.cooler = previewLoans.v1_3.cooler;
        migrateLoans.v1_3.loanIds = new uint256[](previewLoans.v1_3.loans.length);
        for (uint256 i; i < previewLoans.v1_3.loans.length; ++i) {
            migrateLoans.v1_3.loanIds[i] = previewLoans.v1_3.loans[i].loanId;
        }

        migrateLoans.migrateMonoCooler = previewLoans.monoCooler.collateral != 0;
    }

    function uncheckedSlippageParams() internal pure returns (IOrigamiCoolerMigrator.SlippageParams memory) {
        return IOrigamiCoolerMigrator.SlippageParams(0, 0, type(uint256).max);
    }

    function _checkAllMigrated(
        address account,
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans
    ) public view {
        IOrigamiCoolerMigrator.CoolerPreviewInfo memory info = allLoans.v1_1;
        for (uint256 i; i < info.loans.length; ++i) {
            ICooler.Loan memory loan = ICooler(info.cooler).getLoan(info.loans[i].loanId);
            assertEq(loan.principal, 0);
            assertEq(loan.collateral, 0);
        }

        info = allLoans.v1_2;
        for (uint256 i; i < info.loans.length; ++i) {
            ICooler.Loan memory loan = ICooler(info.cooler).getLoan(info.loans[i].loanId);
            assertEq(loan.principal, 0);
            assertEq(loan.collateral, 0);
        }

        info = allLoans.v1_3;
        for (uint256 i; i < info.loans.length; ++i) {
            ICooler.Loan memory loan = ICooler(info.cooler).getLoan(info.loans[i].loanId);
            assertEq(loan.principal, 0);
            assertEq(loan.collateral, 0);
        }

        if (allLoans.monoCooler.collateral != 0) {
            assertEq(monoCooler.accountDebt(account), 0);
            assertEq(monoCooler.accountCollateral(account), 0);
        }
    }
    
    function migrateCoolers() internal {
        // chud, 1 loan v1
        address exampleCoolerV1 = 0x6f40DF8cC60F52125467838D15f9080748c2baea;
        address owner = ICooler(exampleCoolerV1).owner();
        assertEq(owner, exampleCoolerOwner);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = hOhmMigrator.getCoolerLoansFor(owner, exampleCoolerV1);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = hOhmMigrator.previewMigration(allLoans);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        uint256 startingBalance = usdsToken.balanceOf(owner);
        assertEq(startingBalance, 1.454909382878426784e18);

        vm.startBroadcast(owner);
        monoCooler.setAuthorization(address(hOhmMigrator), uint96(vm.getBlockTimestamp() + 1 days));
        gOhmToken.approve(address(hOhmMigrator), mPreview.totalCollateral);
        hOhmMigrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());

        _checkAllMigrated(owner, allLoans);
        assertEq(hOhmVault.balanceOf(owner), mPreview.hOhmShares);
        assertEq(usdsToken.balanceOf(owner), startingBalance + mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt));

        vm.stopBroadcast();
    }
    
    function seedUniV3() internal {
        uint256 liquidityAmountUsd = 25_000_000e18;

        vm.startBroadcast(0x2d4d2A025b10C09BDbd794B4FCe4F7ea8C7d7bB4);
        sUsdsToken.transfer(ORIGAMI_MULTISIG, liquidityAmountUsd);
        vm.stopBroadcast();

        vm.startBroadcast(ORIGAMI_MULTISIG);

        hOhmSusdsPool = IUniswapV3Pool(uniV3Factory.createPool(address(sUsdsToken), address(hOhmVault), SUSDS_HOHM_FEE));
        int24 tickSpacing = hOhmSusdsPool.tickSpacing();
        address token0 = hOhmSusdsPool.token0();
        assertEq(tickSpacing, 200);

        // Each hOHM is worth roughly 0.011 USDS
        uint256 numHohmShares = uint256(liquidityAmountUsd) * 1e18 / 0.011e18;

        joinWithShares(ORIGAMI_MULTISIG, numHohmShares);

        // 1mm hOHM == 11_000 USDS == 10,573 sUSDS
        if (address(token0) == address(sUsdsToken)) {
            hOhmSusdsPool.initialize(calculateSqrtPriceX96(sUsdsToken.convertToShares(11_000e18), 1_000_000e18));
            mintLiquidity(sUsdsToken, hOhmVault, sUsdsToken.convertToShares(liquidityAmountUsd), numHohmShares, SUSDS_HOHM_FEE, tickSpacing, ORIGAMI_MULTISIG);
        } else {
            hOhmSusdsPool.initialize(calculateSqrtPriceX96(1_000_000e18, sUsdsToken.convertToShares(11_000e18)));
            mintLiquidity(hOhmVault, sUsdsToken, numHohmShares, sUsdsToken.convertToShares(liquidityAmountUsd), SUSDS_HOHM_FEE, tickSpacing, ORIGAMI_MULTISIG);
        }
        vm.stopBroadcast();
        
        assertEq(hOhmVault.balanceOf(address(hOhmSusdsPool)), 2_272_727_272.727272727272727271e18);
        assertEq(sUsdsToken.balanceOf(address(hOhmSusdsPool)), 23_923_503.910043278638803739e18);
    }

    function calculateSqrtPriceX96(uint256 token0Amount, uint256 token1Amount) internal pure returns (uint160) {
        return uint160(
            sqrt(
                token1Amount.mulDiv(
                    1 << 192,
                    token0Amount,
                    OrigamiMath.Rounding.ROUND_DOWN)
            )
        );
    }

    function calcMaxTick(int24 tickSpacing) internal pure returns (int24) {
        return (MAX_TICK / tickSpacing) * tickSpacing;
    }

    function mintLiquidity(
        IERC20 token0,
        IERC20 token1,
        uint256 token0Amount,
        uint256 token1Amount,
        uint24 fee,
        int24 tickSpacing,
        address recipient
    ) internal {
        token0.approve(address(uniV3PositionManager), token0Amount);
        token1.approve(address(uniV3PositionManager), token1Amount);

        int24 maxTick = calcMaxTick(tickSpacing);

        uniV3PositionManager.mint(IUniswapV3NonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: fee,
            tickLower: -maxTick,
            tickUpper: maxTick,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: vm.getBlockTimestamp() + 1 days
        }));
    }

    function joinWithShares(address account, uint256 shares) internal {
        (
            uint256[] memory previewAssets,
            // uint256[] memory previewLiabilities
        ) = hOhmVault.previewJoinWithShares(shares);

        // Add a small fraction for rounding
        mintGohm(account, previewAssets[0] + 1e10);
        gOhmToken.approve(address(hOhmVault), previewAssets[0] + 1e10);
        hOhmVault.joinWithShares(shares, account);
    }
}
