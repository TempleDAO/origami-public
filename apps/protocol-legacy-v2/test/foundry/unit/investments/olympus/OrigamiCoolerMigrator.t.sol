pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { OrigamiHOhmCommon } from "test/foundry/unit/investments/olympus/OrigamiHOhmCommon.t.sol";
import { OrigamiHOhmManager } from "contracts/investments/olympus/OrigamiHOhmManager.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";

import { ICooler } from "contracts/interfaces/external/olympus/IOlympusCoolerV1.sol";
import { IMonoCooler } from "contracts/interfaces/external/olympus/IMonoCooler.sol";
import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";
import { IERC3156FlashLender } from "contracts/interfaces/external/makerdao/IERC3156FlashLender.sol";
import { IDaiUsds } from "contracts/interfaces/external/makerdao/IDaiUsds.sol";
import { ICoolerLtvOracle } from "contracts/interfaces/external/olympus/ICoolerLtvOracle.sol";

import { Kernel } from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";

import { IOrigamiCoolerMigrator } from "contracts/interfaces/investments/olympus/IOrigamiCoolerMigrator.sol";
import { OrigamiCoolerMigrator } from "contracts/investments/olympus/OrigamiCoolerMigrator.sol";

import { OrigamiCoolerMigratorHelperLib } from "test/foundry/unit/investments/olympus/OrigamiCoolerMigratorHelperLib.m.sol";
import { MockGohm } from "contracts/test/external/olympus/test/mocks/MockGohm.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";

contract OrigamiCoolerMigratorTestBase is OrigamiHOhmCommon {
    using SafeCast for uint256;

    event CoolerLoansMigrated(
        address indexed account,
        uint256 totalDebtRepaid,
        uint256 totalCollateralWithdrawn,
        uint256 hohmSharesReceived,
        uint256 usdsReceived
    );
    event MaxLoansSet(uint256 maxLoans);

    OrigamiCoolerMigrator internal migrator;
    OrigamiHOhmManager internal manager;
    IERC3156FlashLender internal flashloanLender;

    MonoCooler internal monoCooler;
    IERC4626 internal sUSDS;
    IERC4626 internal sDai;
    IDaiUsds internal daiUsds;

    Kernel internal kernel;

    IERC20 internal DAI;
    IERC20 internal OHM;

    address[3] internal clearinghouses;

    address public signer;
    uint256 public signerPk;

    ICoolerLtvOracle internal ltvOracle;
    OlympusMonoCoolerDeployerLib.Contracts _olympusMonoCoolerContracts;
    OrigamiCoolerMigratorHelperLib.MigratorTestContracts _mtContracts;

    uint256 internal constant MAINNET_FORK_BLOCK_NUMBER = 21873957;
    uint256 internal constant MAX_LOANS = 50;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint96 authorizationDeadline,uint256 nonce,uint256 signatureDeadline)"
        );

    function setUp() public {
        setUpMainnetFork();
        (signer, signerPk) = makeAddrAndKey("signer");
    }

    function setUpMainnetFork() public {
        fork("mainnet", MAINNET_FORK_BLOCK_NUMBER);

        OrigamiCoolerMigratorHelperLib.ContractAddresses memory addresses =
            OrigamiCoolerMigratorHelperLib.getMainnetAddresses();
        OlympusMonoCoolerDeployerLib.Contracts memory contracts = fillMainnetContracts(addresses);

        address executor = contracts.kernel.executor();
        deployAndConfigureMonoCooler(executor, addresses.timelock, contracts);

        ltvOracle = contracts.ltvOracle;
        monoCooler = contracts.monoCooler;
        flashloanLender = _mtContracts.flashloanLender;

        ltvOracle.setOriginationLtvAt(uint96(uint256(11.5e18) * OHM_PER_GOHM / 1e18), uint32(vm.getBlockTimestamp()) + 182.5 days);
        mintGOhm(origamiMultisig, 100e18);

        deployVault();
        seedDeposit(origamiMultisig, MAX_TOTAL_SUPPLY);

        deployMigrator();

        // deposit sDai for clearing house
        depositErc4626(sDai, clearinghouses[0], 1_000_000e18);
        depositErc4626(sDai, clearinghouses[1], 1_000_000e18);
        depositErc4626(sUSDS, clearinghouses[2], 1_000_000e18);

        // fund enough for withdrawReserves during ohm join in migration
        depositErc4626(sUSDS, addresses.trsry, 500_000_000e18);
        vm.stopPrank();
    }

    /// @dev important to use this rather than deal() when dealing with the ERC20Votes
    function mintGOhm(address to, uint256 amount) internal {
        vm.startPrank(gOHM.approved());
        gOHM.mint(to, amount);
        vm.stopPrank();
    }

    function fillMainnetContracts(
        OrigamiCoolerMigratorHelperLib.ContractAddresses memory addresses
    ) internal returns (OlympusMonoCoolerDeployerLib.Contracts memory contracts) {
        OrigamiCoolerMigratorHelperLib.MigratorTestContracts memory mtContracts;
        addresses = OrigamiCoolerMigratorHelperLib.getMainnetAddresses();
        OrigamiCoolerMigratorHelperLib.fillContractsFromMainnet(contracts, mtContracts);
        USDS = MockERC20(addresses.usds);
        sUSDS = IERC4626(addresses.sUsds);
        OHM = IERC20(addresses.ohm);
        gOHM = MockGohm(addresses.gOHM);

        kernel = contracts.kernel;
        
        DAI = mtContracts.DAI;
        sDai = mtContracts.sDai;
        daiUsds = mtContracts.daiUsds;
        clearinghouses[0] = address(mtContracts.clearinghousev1);
        clearinghouses[1] = address(mtContracts.clearinghousev2);
        clearinghouses[2] = address(mtContracts.clearinghousev3);
        _mtContracts = mtContracts;
        _olympusMonoCoolerContracts = contracts;
    }

    function deployAndConfigureMonoCooler(
        address executor,
        address timelock,
        OlympusMonoCoolerDeployerLib.Contracts memory contracts
    ) internal {
        vm.startPrank(executor);
        OrigamiCoolerMigratorHelperLib.deployAndConfigureMonoCooler(contracts);

        vm.startPrank(timelock);
        OrigamiCoolerMigratorHelperLib.setAccessMonoCooler(contracts, origamiMultisig);
        vm.startPrank(address(this));
        OrigamiCoolerMigratorHelperLib.enableOracleAndTrsryBorrowerPolicies(contracts);
    }

    function deployMigrator() internal {
        migrator = new OrigamiCoolerMigrator(
            origamiMultisig,
            address(vault),
            address(gOHM),
            address(DAI),
            address(USDS),
            address(daiUsds),
            address(monoCooler),
            address(flashloanLender),
            clearinghouses
        );
    }

    function deployVault() internal {
        vault = new OrigamiHOhmVault(
             origamiMultisig, 
            "Origami hOHM", 
            "hOHM",
            address(gOHM),
            address(0)
        );

        manager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(monoCooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        manager.setExitFees(EXIT_FEE_BPS);
        vm.stopPrank();
    }

    function buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(monoCooler)));
    }

    function seedDeposit(address account, uint256 maxSupply) internal {
        uint256[] memory assetAmounts = new uint256[](1);
        assetAmounts[0] = SEED_GOHM_AMOUNT;
        uint256[] memory liabilityAmounts = new uint256[](1);
        liabilityAmounts[0] = SEED_USDS_AMOUNT;

        vm.startPrank(account);
        gOHM.approve(address(vault), assetAmounts[0]);
        vault.seed(assetAmounts, liabilityAmounts, SEED_HOHM_SHARES, account, maxSupply);
        vm.stopPrank();
    }

    function depositErc4626(
        IERC4626 sVault,
        address account,
        uint256 amount
    ) internal {
        address asset = sVault.asset();
        deal(asset, account, amount);
        vm.startPrank(account);
        IERC20(asset).approve(address(sVault), amount);
        sVault.deposit(amount, account);
        vm.stopPrank();
    }

    function _getCoolerDebtAndCollateral(
        address cooler
    ) internal view returns (uint256 debt, uint256 collateral) {
        for (uint i; i < MAX_LOANS; ++i) {
            try ICooler(cooler).getLoan(i) returns (ICooler.Loan memory loan) {
                if (loan.principal == 0 || vm.getBlockTimestamp() > loan.expiry) { continue; }
                debt += loan.principal + loan.interestDue;
                collateral += loan.collateral;
            } catch Panic(uint256) {
                break;
            }
        }
    }

     function _createCoolerV3AndBorrow(
        address signer_,
        uint256 collateral_
    ) internal returns (address cooler, uint256 principal, uint256 interest) {
        mintGOhm(signer, collateral_);
        vm.startPrank(signer_);
        address ch3 = address(_mtContracts.clearinghousev3);
        cooler = _mtContracts.factoryv2.generateCooler(ERC20(gOHM), ERC20(USDS));

        // approve
        gOHM.approve(ch3, collateral_);
        (principal, interest) = _mtContracts.clearinghousev3.getLoanForCollateral(collateral_);

        _mtContracts.clearinghousev3.lendToCooler(ICooler(cooler), principal);
        vm.stopPrank();
    }

    function _addToMonoCooler(
        address account,
        uint128 collateral,
        uint128 borrowAmount
    ) internal {
        mintGOhm(account, collateral);
        vm.startPrank(account);
        IERC20(gOHM).approve(address(monoCooler), collateral);
        monoCooler.addCollateral(collateral, account, noDelegations());

        if (borrowAmount > 0)
            monoCooler.borrow(borrowAmount, account, account);
        
        // skip to increase debt
        skip(3600 seconds);

        vm.stopPrank();
    }

    function checkLoans(
        IOrigamiCoolerMigrator.CoolerLoanPreviewInfo[] memory loans,
        uint256 expectedLoanId1,
        uint128 debt1,
        uint128 collateral1
    ) internal pure {
        assertEq(loans.length, 1, "loans::length");
        assertEq(loans[0].loanId, expectedLoanId1, "loans[0]::loanId");
        assertEq(loans[0].debt, debt1, "loans[0]::debt");
        assertEq(loans[0].collateral, collateral1, "loans[0]::collateral");
    }

    function checkLoans(
        IOrigamiCoolerMigrator.CoolerLoanPreviewInfo[] memory loans,
        uint256 expectedLoanId1,
        uint128 debt1,
        uint128 collateral1,
        uint256 expectedLoanId2,
        uint128 debt2,
        uint128 collateral2,
        uint256 expectedLoanId3,
        uint128 debt3,
        uint128 collateral3
    ) internal pure {
        assertEq(loans.length, 3, "loans::length");
        assertEq(loans[0].loanId, expectedLoanId1, "loans[0]::loanId");
        assertEq(loans[0].debt, debt1, "loans[0]::debt");
        assertEq(loans[0].collateral, collateral1, "loans[0]::collateral");
        assertEq(loans[1].loanId, expectedLoanId2, "loans[1]::loanId");
        assertEq(loans[1].debt, debt2, "loans[1]::debt");
        assertEq(loans[1].collateral, collateral2, "loans[1]::collateral");
        assertEq(loans[2].loanId, expectedLoanId3, "loans[2]::loanId");
        assertEq(loans[2].debt, debt3, "loans[2]::debt");
        assertEq(loans[2].collateral, collateral3, "loans[2]::collateral");
    }

    function checkMonoCoolerLoan(
        IOrigamiCoolerMigrator.MonoCoolerLoanPreviewInfo memory loan,
        uint128 debt,
        uint128 collateral
    ) internal pure {
        assertEq(loan.debt, debt, "monocooler::debt");
        assertEq(loan.collateral, collateral, "monocooler::collateral");
    }

    function checkPreview(
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans,
        uint256 totalDaiDebt,
        uint256 totalUsdsDebt,
        uint256 totalCollateral,
        uint256 hOhmShares,
        uint256 hOhmLiabilities
    ) internal view returns (IOrigamiCoolerMigrator.MigrationPreview memory mPreview) {
        mPreview = migrator.previewMigration(allLoans);

        assertEq(mPreview.totalDaiDebt, totalDaiDebt, "previewMigration::totalDaiDebt");
        assertEq(mPreview.totalUsdsDebt, totalUsdsDebt, "previewMigration::totalUsdsDebt");
        assertEq(mPreview.totalCollateral, totalCollateral, "previewMigration::totalCollateral");
        assertEq(mPreview.hOhmShares, hOhmShares, "previewMigration::hOhmShares");
        assertEq(mPreview.hOhmLiabilities, hOhmLiabilities, "previewMigration::hOhmLiabilities");
    }

    function noDelegations() internal view returns (IDLGTEv1.DelegationRequest[] memory delegationRequests) {
    }

    function uncheckedSlippageParams() internal pure returns (IOrigamiCoolerMigrator.SlippageParams memory) {
        return IOrigamiCoolerMigrator.SlippageParams(0, 0, type(uint256).max);
    }

    function setupAllCoolers(bool withMonoCooler) internal returns (
        address owner,
        address v1_1Cooler,
        uint256 expectedShares,
        uint256 expectedUsds,
        uint256 totalDaiDebt,
        uint256 totalUsdsDebt,
        uint256 totalCollateral
    ) {
        v1_1Cooler = OrigamiCoolerMigratorHelperLib.exampleCoolers()[0];
        owner = ICooler(v1_1Cooler).owner();
        vm.label(owner, "COOLER_OWNER");

        if (withMonoCooler) {
            uint128 monoCoolerCollateral = 10e18;
            uint128 monoCoolerBorrow = 25_000e18;
            _addToMonoCooler(owner, monoCoolerCollateral, monoCoolerBorrow);

            totalUsdsDebt += monoCooler.accountDebt(owner);
            totalCollateral += monoCoolerCollateral;
        }
        
        // The other version
        {
            address v1_2Cooler = _mtContracts.factoryv2.getCoolerFor(owner, address(gOHM), address(DAI));
            address v1_3Cooler = _mtContracts.factoryv2.getCoolerFor(owner, address(gOHM), address(USDS));

            (uint256 debt, uint256 collateral) = _getCoolerDebtAndCollateral(v1_1Cooler);
            totalDaiDebt += debt;
            totalCollateral += collateral;

            if (v1_2Cooler != address(0)) {
                (debt, collateral) = _getCoolerDebtAndCollateral(v1_2Cooler);
                totalDaiDebt += debt;
                totalCollateral += collateral;
            }

            if (v1_3Cooler != address(0)) {
                (debt, collateral) = _getCoolerDebtAndCollateral(v1_3Cooler);
                totalUsdsDebt += debt;
                totalCollateral += collateral;
            }
        }

        (uint256 shares,, uint256[] memory liabilities) = vault.previewJoinWithToken(address(gOHM), totalCollateral);
        expectedShares = shares;
        expectedUsds = liabilities[0];
    }

    function _createMonoCoolerMigrationParams(
        address giveAuthTo,
        IDLGTEv1.DelegationRequest[] memory delegationRequests
    ) internal view returns (IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams) {
        uint96 deadline = uint96(vm.getBlockTimestamp() + 1 hours);
        IMonoCooler.Authorization memory authorization = IMonoCooler.Authorization(
            signer, giveAuthTo, deadline, monoCooler.authorizationNonces(signer), deadline
        );

        IMonoCooler.Signature memory signature;
        {
            bytes32 domainSeparator = buildDomainSeparator();
            bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
            bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
            (signature.v, signature.r, signature.s) = vm.sign(signerPk, typedDataHash);
        }

        mcParams = IOrigamiCoolerMigrator.MonoCoolerMigration(authorization, signature, delegationRequests);
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
}

contract OrigamiCoolerMigratorTestAdmin is OrigamiCoolerMigratorTestBase {
    function test_init() public view {
        assertEq(address(migrator.hOHM()), address(vault));
        assertEq(address(migrator.dai()), address(DAI));
        assertEq(address(migrator.gOHM()), address(gOHM));
        assertEq(address(migrator.usds()), address(USDS));
        assertEq(address(migrator.daiUsds()), address(daiUsds));
        assertEq(address(migrator.monoCooler()), address(monoCooler));
        assertEq(address(migrator.flashloanLender()), address(flashloanLender));
        assertEq(migrator.maxLoans(), MAX_LOANS);
        (address _v1_1, address _v1_2, address _v1_3) = migrator.getClearinghouses();
        assertEq(_v1_1, clearinghouses[0]);
        assertEq(_v1_2, clearinghouses[1]);
        assertEq(_v1_3, clearinghouses[2]);
    }

    function test_settMaxLoans() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(migrator));
        emit MaxLoansSet(50);
        migrator.setMaxLoans(50);
        assertEq(migrator.maxLoans(), 50);

        vm.expectEmit(address(migrator));
        emit MaxLoansSet(0);
        migrator.setMaxLoans(0);
    }
}

contract OrigamiCoolerMigratorTestAccess is OrigamiCoolerMigratorTestBase {
    function test_access_setMaxLoans() public {
        expectElevatedAccess();
        migrator.setMaxLoans(2);
    }

    function test_access_onFlashLoan_invalid_caller() public {
        vm.startPrank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        migrator.onFlashLoan(address(migrator), address(DAI), 0, 0, bytes(""));
    }

    function test_access_onFlashLoan_invalid_initiator() public {
        vm.startPrank(address(flashloanLender));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        migrator.onFlashLoan(alice, address(DAI), 0, 0, bytes(""));
    }
}

contract OrigamiCoolerMigratorTestView is OrigamiCoolerMigratorTestBase {
    using SafeCast for uint256;

    function test_getCoolerV1_1Params() public view {
        (
            address factory,
            address collateralToken,
            address debtToken
        ) = migrator.getCoolerV1_1Params();
        assertEq(factory, 0xDE3e735d37A8498AD2F141F603A6d0F976A6F772);
        assertEq(collateralToken, address(gOHM));
        assertEq(debtToken, address(DAI));
    }

    function test_getCoolerLoansFor_v1_coolers_failInvalidCooler() public {
        address v1_1Cooler = OrigamiCoolerMigratorHelperLib.exampleCoolers()[0];
        address owner = ICooler(v1_1Cooler).owner();
        
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidCooler.selector, alice));
        migrator.getCoolerLoansFor(owner, alice);
    }

    function test_getCoolerLoansFor_invalidLoanLender() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        assertEq(allLoans.v1_1.cooler, v1_1Cooler);
        assertEq(allLoans.v1_1.loans.length, 1);

        ICooler.Loan memory mockLoan = ICooler(allLoans.v1_1.cooler).getLoan(0);
        mockLoan.lender = alice;
        vm.mockCall(
            allLoans.v1_1.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 0),
            abi.encode(mockLoan)
        );

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory badLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        assertEq(badLoans.v1_1.cooler, v1_1Cooler);
        assertEq(badLoans.v1_1.loans.length, 0);
    }
    
    function test_getCoolerLoansFor_alreadyPaidDown() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        assertEq(allLoans.v1_1.cooler, v1_1Cooler);
        assertEq(allLoans.v1_1.loans.length, 1);

        ICooler.Loan memory mockLoan = ICooler(allLoans.v1_1.cooler).getLoan(0);
        mockLoan.principal = 0;
        vm.mockCall(
            allLoans.v1_1.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 0),
            abi.encode(mockLoan)
        );

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory badLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        assertEq(badLoans.v1_1.cooler, v1_1Cooler);
        assertEq(badLoans.v1_1.loans.length, 0);
    }
    
    function test_getCoolerLoansFor_expired() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        assertEq(allLoans.v1_1.cooler, v1_1Cooler);
        assertEq(allLoans.v1_1.loans.length, 1);

        ICooler.Loan memory mockLoan = ICooler(allLoans.v1_1.cooler).getLoan(0);
        mockLoan.expiry = vm.getBlockTimestamp() - 1;
        vm.mockCall(
            allLoans.v1_1.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 0),
            abi.encode(mockLoan)
        );

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory badLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        assertEq(badLoans.v1_1.cooler, v1_1Cooler);
        assertEq(badLoans.v1_1.loans.length, 0);
    }

    function test_getCoolerLoansFor_unhandledPanic() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        vm.mockCallRevert(
            v1_1Cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 0),
            abi.encodeWithSignature("Panic(uint256)", 0x33)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.UnknownExecuteError.selector, abi.encode(0x33)));
        migrator.getCoolerLoansFor(owner, v1_1Cooler);
    }

    function test_getCoolerLoansFor_v1_coolers() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);

        {
            assertEq(allLoans.v1_1.cooler, OrigamiCoolerMigratorHelperLib.exampleCoolers()[0]);
            checkLoans(allLoans.v1_1.loans, 0, 4_005_926.849041095888123900e18, 1_384.734748641889816562e18);
            assertEq(allLoans.v1_2.cooler, 0x803D2A6a07b2C21Be139cade478B391360180a40);
            checkLoans(
                allLoans.v1_2.loans, 
                3, 310_718.465899892561847471e18, 107.228783258101312741e18,
                6, 207_846.451890498375927077e18, 71.727703972097071581e18,
                8, 220_560.995409629063567992e18, 76.115486421041740634e18
            );
            assertEq(allLoans.v1_3.cooler, 0x566bf17ED32f523da1E5a9fdbb2f1758cc07e807);
            checkLoans(allLoans.v1_3.loans, 1, 208_211.721491567057993364e18, 71.853758324130290679e18);
            checkMonoCoolerLoan(allLoans.monoCooler, 0, 0);
        }       
    }

    function test_getCoolerLoansFor_only_monocooler() public {
        uint128 collateral = 10e18;
        uint128 borrowAmount = 25_000e18;
        _addToMonoCooler(signer, collateral, borrowAmount);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        assertEq(allLoans.v1_1.loans.length, 0);
        assertEq(allLoans.v1_2.loans.length, 0);
        assertEq(allLoans.v1_3.loans.length, 0);

        uint128 latestDebt = monoCooler.accountDebt(signer);
        assertEq(latestDebt, borrowAmount + 0.0142338553963e18);
        checkMonoCoolerLoan(allLoans.monoCooler, latestDebt, collateral);
    }

    function test_getCoolerLoansFor_v1_and_mono_coolers() public {
        uint128 collateral = 10e18;
        uint128 borrowAmount = 25_000e18;
        (address cooler1_3, uint256 cPrincipal, uint256 cInterest) = _createCoolerV3AndBorrow(signer, collateral);
        _addToMonoCooler(signer, collateral, borrowAmount);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        assertEq(allLoans.v1_1.loans.length, 0);
        assertEq(allLoans.v1_2.loans.length, 0);
        assertEq(allLoans.v1_3.cooler, cooler1_3);

        assertEq(cPrincipal, 28_929.2e18);
        assertEq(cInterest, 47.951139726027383786e18);
        checkLoans(allLoans.v1_3.loans, 0, uint128(cPrincipal + cInterest), collateral);

        uint128 latestDebt = monoCooler.accountDebt(signer);
        assertEq(latestDebt, borrowAmount + 0.0142338553963e18);
        checkMonoCoolerLoan(allLoans.monoCooler, latestDebt, collateral);
    }

    function test_previewMigration_v1_cooler_multiple_loans() public view {
        // cooler with 2 loans in v1.2. No other positions in other v1 coolers and monocooler
        address cooler = OrigamiCoolerMigratorHelperLib.exampleCoolers()[1];
        address owner = ICooler(cooler).owner();

        (uint256 debt, uint256 collateral) = _getCoolerDebtAndCollateral(cooler);
        (uint256 shares,, uint256[] memory liabilities) = vault.previewJoinWithToken(address(gOHM), collateral);

        // get preview for all loans
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, address(0));
        checkPreview(allLoans, debt, 0, collateral, shares, liabilities[0]);

        // get preview for 1 loan
        IOrigamiCoolerMigrator.CoolerLoanPreviewInfo memory singleLoan1 = allLoans.v1_2.loans[0];
        IOrigamiCoolerMigrator.CoolerLoanPreviewInfo memory singleLoan2 = allLoans.v1_2.loans[1];

        allLoans.v1_2.loans = new IOrigamiCoolerMigrator.CoolerLoanPreviewInfo[](1);
        allLoans.v1_2.loans[0] = singleLoan1;
        (shares,, liabilities) = vault.previewJoinWithToken(address(gOHM), singleLoan1.collateral);
        checkPreview(allLoans, singleLoan1.debt, 0, singleLoan1.collateral, shares, liabilities[0]);

        allLoans.v1_2.loans[0] = singleLoan2;
        (shares,, liabilities) = vault.previewJoinWithToken(address(gOHM), singleLoan2.collateral);
        checkPreview(allLoans, singleLoan2.debt, 0, singleLoan2.collateral, shares, liabilities[0]);
    }

    function test_previewMigration_all_coolers() public {
        (
            address owner,
            address v1_1Cooler,
            uint256 expectedShares,
            uint256 expectedUsds,
            uint256 totalDaiDebt,
            uint256 totalUsdsDebt,
            uint256 totalCollateral
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);

        {
            assertEq(allLoans.v1_1.cooler, OrigamiCoolerMigratorHelperLib.exampleCoolers()[0]);
            checkLoans(allLoans.v1_1.loans, 0, 4_005_926.849041095888123900e18, 1_384.734748641889816562e18);
            assertEq(allLoans.v1_2.cooler, 0x803D2A6a07b2C21Be139cade478B391360180a40);
            checkLoans(
                allLoans.v1_2.loans, 
                3, 310_718.465899892561847471e18, 107.228783258101312741e18,
                6, 207_846.451890498375927077e18, 71.727703972097071581e18,
                8, 220_560.995409629063567992e18, 76.115486421041740634e18
            );
            assertEq(allLoans.v1_3.cooler, 0x566bf17ED32f523da1E5a9fdbb2f1758cc07e807);
            checkLoans(allLoans.v1_3.loans, 1, 208_211.721491567057993364e18, 71.853758324130290679e18);
            checkMonoCoolerLoan(allLoans.monoCooler, 25_000.0142338553963e18, 10e18);
        }

        checkPreview(allLoans, totalDaiDebt, totalUsdsDebt, totalCollateral, expectedShares, expectedUsds);
    }
}

contract OrigamiCoolerMigratorTest is OrigamiCoolerMigratorTestBase {
    function test_migrate_fail_monocooler_paused() public {
        vm.prank(origamiMultisig);
        migrator.setMaxLoans(0);

        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory allLoans;
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        migrator.migrate(allLoans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_monocooler_invalidOwner() public {
        uint128 collateral = 10e18;
        uint128 borrow = 25_000e18;
        _addToMonoCooler(signer, collateral, borrow);

        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory allLoans;
        allLoans.migrateMonoCooler = true;
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        mcParams.authorization.account = unauthorizedUser;
        vm.startPrank(signer);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidOwner.selector));
        migrator.migrate(allLoans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_monocooler_wrongCaller() public {
        uint128 collateral = 10e18;
        uint128 borrow = 25_000e18;
        _addToMonoCooler(unauthorizedUser, collateral, borrow);

        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory allLoans;
        allLoans.migrateMonoCooler = true;
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(signer), noDelegations());

        vm.startPrank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidOwner.selector));
        migrator.migrate(allLoans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_monocooler_wrongAuthorized() public {
        uint128 collateral = 10e18;
        uint128 borrow = 25_000e18;
        _addToMonoCooler(signer, collateral, borrow);

        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory allLoans;
        allLoans.migrateMonoCooler = true;

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(unauthorizedUser), noDelegations());

        vm.startPrank(signer);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidAuth.selector));
        migrator.migrate(allLoans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_nothingToMigrate() public {
        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory allLoans;
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        mcParams.authorization.account = signer;

        vm.startPrank(signer);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        migrator.migrate(allLoans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_monocooler_receiveSurplus() public {
        uint128 collateral = 10e18;
        uint128 borrow = 25_000e18;
        _addToMonoCooler(signer, collateral, borrow);

        uint256 startingUsdsBalance = USDS.balanceOf(signer);
        assertEq(startingUsdsBalance, borrow);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);

        uint256 expectedSurplus = mPreview.hOhmLiabilities - mPreview.totalUsdsDebt;
        assertEq(expectedSurplus, 4_616.402628366802059173e18);

        vm.startPrank(signer);
        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(signer, mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
        
        assertEq(monoCooler.accountDebt(signer), 0);
        assertEq(monoCooler.accountCollateral(signer), 0);
        assertEq(vault.balanceOf(signer), mPreview.hOhmShares);
        assertEq(USDS.balanceOf(signer), startingUsdsBalance + expectedSurplus);
    }

    function test_migrate_monocooler_exact() public {
        uint128 collateral = 10e18;
        uint128 borrow = 29_616.4e18; // max - same as hOHM
        _addToMonoCooler(signer, collateral, borrow);

        uint256 startingUsdsBalance = USDS.balanceOf(signer);
        assertEq(startingUsdsBalance, borrow);

        skip(365 days);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);

        uint256 expectedSurplus = mPreview.totalUsdsDebt - mPreview.hOhmLiabilities;
        assertEq(expectedSurplus, 0);

        vm.startPrank(signer);
        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(signer, mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
        
        assertEq(monoCooler.accountDebt(signer), 0);
        assertEq(monoCooler.accountCollateral(signer), 0);
        assertEq(vault.balanceOf(signer), mPreview.hOhmShares);
        assertEq(USDS.balanceOf(signer), startingUsdsBalance + expectedSurplus);
    }

    function test_migrate_monocooler_shortfall() public {
        uint128 collateral = 10e18;
        uint128 borrow = 29_616.4e18; // max
        _addToMonoCooler(signer, collateral, borrow);

        uint256 startingUsdsBalance = USDS.balanceOf(signer);
        assertEq(startingUsdsBalance, borrow);

        skip(365 days);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        
        // Need to DECREASE the USDS/hOHM in order to reduce the amount of liabilities received in join
        // To do that - a large donation can be made.
        uint128 repaymentDonation = 1_000e18;
        {
            (, uint256[] memory liabilities) = vault.convertFromShares(1_000e18);
            assertEq(liabilities[0], 11.055006294210855097e18);
            deal(address(USDS), alice, repaymentDonation);
            vm.startPrank(alice);
            USDS.approve(address(monoCooler), repaymentDonation);
            monoCooler.repay(repaymentDonation, address(manager));

            (, liabilities) = vault.convertFromShares(1_000e18);
            assertEq(liabilities[0], 10.683590457039558112e18);
        }

        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);
        uint256 expectedShortfall = mPreview.totalUsdsDebt - mPreview.hOhmLiabilities;
        assertEq(expectedShortfall, repaymentDonation);

        // Signer needs to give approval for the shortfall
        vm.startPrank(signer);
        USDS.approve(address(migrator), expectedShortfall);

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(signer, mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
        
        assertEq(monoCooler.accountDebt(signer), 0);
        assertEq(monoCooler.accountCollateral(signer), 0);
        assertEq(vault.balanceOf(signer), mPreview.hOhmShares); // Signer receives the shares
        assertEq(USDS.balanceOf(signer), startingUsdsBalance - expectedShortfall); // Caller has to pay for the shortfall
    }

    function test_migrate_v1_coolers_noPositions() public {
        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory loans;
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        migrator.migrate(loans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_v1_coolers_fail_notFromFactory() public {
        IOrigamiCoolerMigrator.AllCoolerLoansMigration memory loans;
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        loans.v1_2.cooler = alice;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidCooler.selector, alice));
        migrator.migrate(loans, mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_coolerv1_notExpectedLender() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        ICooler.Loan memory mockLoan = ICooler(allLoans.v1_2.cooler).getLoan(6);
        mockLoan.lender = alice;
        vm.mockCall(
            allLoans.v1_2.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 6),
            abi.encode(mockLoan)
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidLoanId.selector, allLoans.v1_2.cooler, 6));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_coolerv1_fullyRepaid() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        ICooler.Loan memory mockLoan = ICooler(allLoans.v1_2.cooler).getLoan(6);
        mockLoan.principal = 0;
        vm.mockCall(
            allLoans.v1_2.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 6),
            abi.encode(mockLoan)
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidLoanId.selector, allLoans.v1_2.cooler, 6));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_coolerv1_expired() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        ICooler.Loan memory mockLoan = ICooler(allLoans.v1_2.cooler).getLoan(6);
        mockLoan.expiry = vm.getBlockTimestamp() - 1;
        vm.mockCall(
            allLoans.v1_2.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 6),
            abi.encode(mockLoan)
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidLoanId.selector, allLoans.v1_2.cooler, 6));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_coolerv1_outOfBounds() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        vm.mockCallRevert(
            allLoans.v1_2.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 6),
            abi.encodeWithSignature("Panic(uint256)", 0x32)
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidLoanId.selector, allLoans.v1_2.cooler, 6));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_coolerv1_unhandledPanic() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        vm.mockCallRevert(
            allLoans.v1_2.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 6),
            abi.encodeWithSignature("Panic(uint256)", 0x33)
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.UnknownExecuteError.selector, abi.encode(0x33)));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_coolerv1_otherRevert() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        vm.mockCallRevert(
            allLoans.v1_2.cooler,
            abi.encodeWithSelector(ICooler.getLoan.selector, 6),
            abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice)
        );

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_v1_coolers_fail_notCoolerOwner() public {
        address v1_1Cooler = OrigamiCoolerMigratorHelperLib.exampleCoolers()[0];
        address owner = ICooler(v1_1Cooler).owner();

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, address(0));
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        // Fails on the v1 owner not matching
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.InvalidOwner.selector));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_coolers_all() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = checkPreview({
            allLoans: allLoans, 
            totalDaiDebt: 4_745_052.762241115889466440e18, 
            totalUsdsDebt: 233_211.735725422454293364e18, 
            totalCollateral: 1_721.660480617260232197e18, 
            hOhmShares: 463_539_867.801391144916720280e18, 
            hOhmLiabilities: 5_098_941.448917460024292741e18
        });
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 42_550.200548249380111327e18);

        vm.startPrank(owner);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_711.660480617260232197e18 + 10e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(owner, mPreview.totalDaiDebt + mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());

        _checkAllMigrated(owner, allLoans);
        assertEq(vault.balanceOf(owner), mPreview.hOhmShares);
        assertEq(USDS.balanceOf(owner), startingBalance + mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt));
    }

    function test_migrate_coolers_filtered() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);

        // Skip v1_1, only use the first,third from v1_2 (loanId=3, 8), use v1_3, skip monoCooler
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory filteredLoans;
        {
            // Leave v1_1 empty

            filteredLoans.v1_2.cooler = allLoans.v1_2.cooler;
            filteredLoans.v1_2.loans = new IOrigamiCoolerMigrator.CoolerLoanPreviewInfo[](2);
            filteredLoans.v1_2.loans[0] = allLoans.v1_2.loans[0]; // first
            filteredLoans.v1_2.loans[1] = allLoans.v1_2.loans[2]; // third

            filteredLoans.v1_3.cooler = allLoans.v1_3.cooler;
            filteredLoans.v1_2.loans = new IOrigamiCoolerMigrator.CoolerLoanPreviewInfo[](1);
            filteredLoans.v1_2.loans[0] = allLoans.v1_2.loans[0]; // first

            // Leave monoCooler empty
        }

        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = checkPreview({
            allLoans: filteredLoans, 
            totalDaiDebt: 310_718.465899892561847471e18, 
            totalUsdsDebt: 0, 
            totalCollateral: 107.228783258101312741e18, 
            hOhmShares: 28_870_277.604411197442386840e18, 
            hOhmLiabilities: 317_573.234460080107646295e18
        });
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 42_550.200548249380111327e18);

        vm.startPrank(owner);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 107.228783258101312741e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(owner, mPreview.totalDaiDebt + mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(filteredLoans), mcParams, uncheckedSlippageParams());

        _checkAllMigrated(owner, filteredLoans);
        assertEq(vault.balanceOf(owner), mPreview.hOhmShares);
        assertEq(USDS.balanceOf(owner), startingBalance + mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt));
    }

    function test_migrate_coolers_monocooler_fail_delegations() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        // owner applies some delegations
        {
            vm.startPrank(owner);
            IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](2);
            delegationRequests[0] = IDLGTEv1.DelegationRequest(alice, 3.3e18);
            delegationRequests[1] = IDLGTEv1.DelegationRequest(alice, 5e18);
            monoCooler.applyDelegations(delegationRequests, owner);
        }

        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_711.660480617260232197e18 + 10e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        // Fails since no undelegations are added to the mcParams
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_ExceededUndelegatedBalance.selector, 10e18-3.3e18-5e18, 10e18));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_coolers_monocooler_success_delegations_and_removed() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        // owner applies some delegations
        {
            vm.startPrank(owner);
            IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](2);
            delegationRequests[0] = IDLGTEv1.DelegationRequest(alice, 3.3e18);
            delegationRequests[1] = IDLGTEv1.DelegationRequest(bob, 5e18);
            monoCooler.applyDelegations(delegationRequests, owner);
        }

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 42_550.200548249380111327e18);

        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_711.660480617260232197e18 + 10e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        // Create the undelegation requests
        {
            mcParams.delegationRequests = new IDLGTEv1.DelegationRequest[](2);
            mcParams.delegationRequests[0] = IDLGTEv1.DelegationRequest(bob, -5e18);
            mcParams.delegationRequests[1] = IDLGTEv1.DelegationRequest(alice, -3.3e18);
        }

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(owner, mPreview.totalDaiDebt + mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());

        _checkAllMigrated(owner, allLoans);
        assertEq(vault.balanceOf(owner), mPreview.hOhmShares);
        assertEq(USDS.balanceOf(owner), startingBalance + mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt));
    }

    function test_migrate_fail_monocooler_zeroDebt() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(false);

        uint128 collateral = 10e18;
        uint128 borrow = 0;
        _addToMonoCooler(owner, collateral, borrow);

        uint256 startingUsdsBalance = USDS.balanceOf(signer);
        assertEq(startingUsdsBalance, 0);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, v1_1Cooler);
        allLoans.v1_2.cooler = address(0);
        allLoans.v1_3.cooler = address(0);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 17_550.200548249380111327e18);

        vm.startPrank(owner);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_384.734748641889816562e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(owner, mPreview.totalDaiDebt + mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());

        _checkAllMigrated(owner, allLoans);
        assertEq(vault.balanceOf(owner), mPreview.hOhmShares);
        assertEq(USDS.balanceOf(owner), startingBalance + mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt));
    }

    function test_migrate_fail_monocooler_misMatchedDebtRepayment() public {
        uint128 collateral = 10e18;
        uint128 borrow = 25_000e18;
        _addToMonoCooler(signer, collateral, borrow);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));

        vm.mockCall(
            address(monoCooler),
            abi.encodeWithSelector(IMonoCooler.repay.selector),
            abi.encode(123)
        );

        vm.startPrank(signer);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.MismatchingDebt.selector));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_fail_monocooler_misMatchedCollateralWithdrawal() public {
        uint128 collateral = 10e18;
        uint128 borrow = 25_000e18;
        _addToMonoCooler(signer, collateral, borrow);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));

        vm.mockCall(
            address(monoCooler),
            abi.encodeWithSelector(IMonoCooler.withdrawCollateral.selector),
            abi.encode(123)
        );

        vm.startPrank(signer);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCoolerMigrator.MismatchingCollateral.selector));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, uncheckedSlippageParams());
    }

    function test_migrate_coolers_success_slippage_surplus() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = checkPreview({
            allLoans: allLoans, 
            totalDaiDebt: 4_745_052.762241115889466440e18, 
            totalUsdsDebt: 233_211.735725422454293364e18, 
            totalCollateral: 1_721.660480617260232197e18, 
            hOhmShares: 463_539_867.801391144916720280e18, 
            hOhmLiabilities: 5_098_941.448917460024292741e18
        });
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 42_550.200548249380111327e18);

        vm.startPrank(owner);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_711.660480617260232197e18 + 10e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        uint256 expectedSurplus = mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt);
        IOrigamiCoolerMigrator.SlippageParams memory slippageParams = IOrigamiCoolerMigrator.SlippageParams({
            minHohmShares: mPreview.hOhmShares,
            minUsdsSurplus: expectedSurplus,
            maxUsdsShortfall: 0
        });

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(owner, mPreview.totalDaiDebt + mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, slippageParams);
    }

    function test_migrate_coolers_fail_slippage_shares_surplus() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = checkPreview({
            allLoans: allLoans, 
            totalDaiDebt: 4_745_052.762241115889466440e18, 
            totalUsdsDebt: 233_211.735725422454293364e18, 
            totalCollateral: 1_721.660480617260232197e18, 
            hOhmShares: 463_539_867.801391144916720280e18, 
            hOhmLiabilities: 5_098_941.448917460024292741e18
        });
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 42_550.200548249380111327e18);

        vm.startPrank(owner);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_711.660480617260232197e18 + 10e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        uint256 expectedSurplus = mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt);
        IOrigamiCoolerMigrator.SlippageParams memory slippageParams = IOrigamiCoolerMigrator.SlippageParams({
            minHohmShares: mPreview.hOhmShares+1,
            minUsdsSurplus: expectedSurplus,
            maxUsdsShortfall: 0
        });

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, mPreview.hOhmShares+1, mPreview.hOhmShares));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, slippageParams);
    }

    function test_migrate_coolers_fail_slippage_usds_surplus() public {
        (
            address owner,
            address v1_1Cooler,
            ,,,,
        ) = setupAllCoolers(true);

        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(owner, v1_1Cooler);
        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = checkPreview({
            allLoans: allLoans, 
            totalDaiDebt: 4_745_052.762241115889466440e18, 
            totalUsdsDebt: 233_211.735725422454293364e18, 
            totalCollateral: 1_721.660480617260232197e18, 
            hOhmShares: 463_539_867.801391144916720280e18, 
            hOhmLiabilities: 5_098_941.448917460024292741e18
        });
        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams;

        uint256 startingBalance = USDS.balanceOf(owner);
        assertEq(startingBalance, 42_550.200548249380111327e18);

        vm.startPrank(owner);
        monoCooler.setAuthorization(address(migrator), uint96(vm.getBlockTimestamp() + 1 days));
        assertEq(mPreview.totalCollateral, 1_711.660480617260232197e18 + 10e18);
        gOHM.approve(address(migrator), mPreview.totalCollateral);

        uint256 expectedSurplus = mPreview.hOhmLiabilities - (mPreview.totalDaiDebt + mPreview.totalUsdsDebt);
        IOrigamiCoolerMigrator.SlippageParams memory slippageParams = IOrigamiCoolerMigrator.SlippageParams({
            minHohmShares: mPreview.hOhmShares,
            minUsdsSurplus: expectedSurplus + 1,
            maxUsdsShortfall: 0
        });

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, expectedSurplus+1, expectedSurplus));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, slippageParams);
    }

    function test_migrate_coolers_success_slippage_shortfall() public {
        uint128 collateral = 10e18;
        uint128 borrow = 29_616.4e18; // max
        _addToMonoCooler(signer, collateral, borrow);

        uint256 startingUsdsBalance = USDS.balanceOf(signer);
        assertEq(startingUsdsBalance, borrow);

        skip(365 days);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        
        // Need to DECREASE the USDS/hOHM in order to reduce the amount of liabilities received in join
        // To do that - a large donation can be made.
        uint128 repaymentDonation = 1_000e18;
        {
            (, uint256[] memory liabilities) = vault.convertFromShares(1_000e18);
            assertEq(liabilities[0], 11.055006294210855097e18);
            deal(address(USDS), alice, repaymentDonation);
            vm.startPrank(alice);
            USDS.approve(address(monoCooler), repaymentDonation);
            monoCooler.repay(repaymentDonation, address(manager));

            (, liabilities) = vault.convertFromShares(1_000e18);
            assertEq(liabilities[0], 10.683590457039558112e18);
        }

        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);
        uint256 expectedShortfall = mPreview.totalUsdsDebt - mPreview.hOhmLiabilities;
        assertEq(expectedShortfall, repaymentDonation);

        IOrigamiCoolerMigrator.SlippageParams memory slippageParams = IOrigamiCoolerMigrator.SlippageParams({
            minHohmShares: mPreview.hOhmShares,
            minUsdsSurplus: 0,
            maxUsdsShortfall: expectedShortfall
        });

        // Signer needs to give approval for the shortfall
        vm.startPrank(signer);
        USDS.approve(address(migrator), expectedShortfall);

        vm.expectEmit(address(migrator));
        emit CoolerLoansMigrated(signer, mPreview.totalUsdsDebt, mPreview.totalCollateral, mPreview.hOhmShares, mPreview.hOhmLiabilities);
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, slippageParams);
        
        assertEq(monoCooler.accountDebt(signer), 0);
        assertEq(monoCooler.accountCollateral(signer), 0);
        assertEq(vault.balanceOf(signer), mPreview.hOhmShares); // Signer receives the shares
        assertEq(USDS.balanceOf(signer), startingUsdsBalance - expectedShortfall); // Caller has to pay for the shortfall
    }

    function test_migrate_coolers_fail_slippage_usds_shortfall() public {
        uint128 collateral = 10e18;
        uint128 borrow = 29_616.4e18; // max
        _addToMonoCooler(signer, collateral, borrow);

        uint256 startingUsdsBalance = USDS.balanceOf(signer);
        assertEq(startingUsdsBalance, borrow);

        skip(365 days);

        IOrigamiCoolerMigrator.MonoCoolerMigration memory mcParams = _createMonoCoolerMigrationParams(address(migrator), noDelegations());
        IOrigamiCoolerMigrator.AllCoolerLoansPreview memory allLoans = migrator.getCoolerLoansFor(signer, address(0));
        
        // Need to DECREASE the USDS/hOHM in order to reduce the amount of liabilities received in join
        // To do that - a large donation can be made.
        uint128 repaymentDonation = 1_000e18;
        {
            (, uint256[] memory liabilities) = vault.convertFromShares(1_000e18);
            assertEq(liabilities[0], 11.055006294210855097e18);
            deal(address(USDS), alice, repaymentDonation);
            vm.startPrank(alice);
            USDS.approve(address(monoCooler), repaymentDonation);
            monoCooler.repay(repaymentDonation, address(manager));

            (, liabilities) = vault.convertFromShares(1_000e18);
            assertEq(liabilities[0], 10.683590457039558112e18);
        }

        IOrigamiCoolerMigrator.MigrationPreview memory mPreview = migrator.previewMigration(allLoans);
        uint256 expectedShortfall = mPreview.totalUsdsDebt - mPreview.hOhmLiabilities;
        assertEq(expectedShortfall, repaymentDonation);

        IOrigamiCoolerMigrator.SlippageParams memory slippageParams = IOrigamiCoolerMigrator.SlippageParams({
            minHohmShares: mPreview.hOhmShares,
            minUsdsSurplus: 0,
            maxUsdsShortfall: expectedShortfall-1
        });

        // Signer needs to give approval for the shortfall
        vm.startPrank(signer);
        USDS.approve(address(migrator), expectedShortfall);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, expectedShortfall-1, expectedShortfall));
        migrator.migrate(_convertLoansForMigration(allLoans), mcParams, slippageParams);
    }
}