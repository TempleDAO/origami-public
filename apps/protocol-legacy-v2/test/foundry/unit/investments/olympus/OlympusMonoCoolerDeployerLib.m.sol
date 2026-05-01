pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {MockERC20} from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import {MonoCooler} from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import {CoolerLtvOracle} from "contracts/test/external/olympus/src/policies/cooler/CoolerLtvOracle.sol";
import {CoolerTreasuryBorrower} from "contracts/test/external/olympus/src/policies/cooler/CoolerTreasuryBorrower.sol";
import {MockOhm} from "contracts/test/external/olympus/test/mocks/MockOhm.sol";
import {MockStaking} from "contracts/test/external/olympus/test/mocks/MockStaking.sol";
import {MockGohm} from "contracts/test/external/olympus/test/mocks/MockGohm.sol";
import {RolesAdmin, Kernel, Actions} from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";
import {OlympusRoles} from "contracts/test/external/olympus/src/modules/ROLES/OlympusRoles.sol";
import {OlympusMinter} from "contracts/test/external/olympus/src/modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "contracts/test/external/olympus/src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusGovDelegation} from "contracts/test/external/olympus/src/modules/DLGTE/OlympusGovDelegation.sol";
import {DelegateEscrowFactory} from "contracts/test/external/olympus/src/external/cooler/DelegateEscrowFactory.sol";
import {MockSUsdsToken} from "contracts/test/external/maker/MockSUsdsToken.m.sol";

library OlympusMonoCoolerDeployerLib {
    uint96 internal constant DEFAULT_OLTV = 2_961.64e18; // [USDS/gOHM] == ~11 [USDS/OHM]
    uint96 internal constant DEFAULT_OLTV_MAX_DELTA = 1000e18; // 1000 USDS
    uint32 internal constant DEFAULT_OLTV_MIN_TARGET_TIME_DELTA = 1 weeks;
    uint96 internal constant DEFAULT_OLTV_MAX_RATE_OF_CHANGE = uint96(10e18) / 1 days; // 10 USDS / day
    uint16 internal constant DEFAULT_LLTV_MAX_PREMIUM_BPS = 333;
    uint16 internal constant DEFAULT_LLTV_PREMIUM_BPS = 100; // LLTV is 1% above OLTV

    uint96 internal constant DEFAULT_INTEREST_RATE_BPS = 0.00498754151103897e18; // 0.5% APY
    uint256 internal constant DEFAULT_MIN_DEBT_REQUIRED = 1_000e18;
    uint256 internal constant INITIAL_TRSRY_MINT = 33_000_000e18;
    uint96 public constant SUSDS_INTEREST_RATE = 0.10e18;

    struct Contracts {
        MockOhm OHM;
        MockGohm gOHM;
        MockERC20 USDS;
        MockSUsdsToken sUSDS;

        Kernel kernel;
        MockStaking staking;
        OlympusRoles ROLES;
        OlympusMinter MINTR;
        OlympusTreasury TRSRY;
        OlympusGovDelegation DLGTE;
        RolesAdmin rolesAdmin;

        DelegateEscrowFactory escrowFactory;
        CoolerLtvOracle ltvOracle;
        CoolerTreasuryBorrower treasuryBorrower;
        MonoCooler monoCooler;
    }

    function fillContractsFromTestnet(
        Contracts memory contracts
    ) internal pure {
        contracts.OHM = MockOhm(0x1d63D0599f22bd87431AB9873cC2Bb63FC7883cE);
        contracts.gOHM = MockGohm(0xAfa204D01E67AF2BFFE590781eB6cBB91c22c627);
        contracts.USDS = MockERC20(0x06350025b8e078731ECef60584275d524C7b2Ff0);
        contracts.sUSDS = MockSUsdsToken(0xa516A972Cd500Ef233431467C80Bf2C7F58239Cf);

        contracts.kernel = Kernel(0x8dE1e79ffE6CCF359fA160f71f2439EB05F9Bf29);
        contracts.staking = MockStaking(0x2A0fbc3941043A5417655e779159166D988486F8);
        contracts.ROLES = OlympusRoles(0xF3E44049787DF91995BfA9315E52fD9600545ac0);
        contracts.MINTR = OlympusMinter(0xb0d7B3785C4bDAbF32c0e60130C170b507a2005B);
        contracts.TRSRY = OlympusTreasury(0x6D80EfB5f224CEcE384A705B41Cf4352ca593c35);
        contracts.DLGTE = OlympusGovDelegation(0xc42d5cc0738ce4943ef9570031FEa9b67C4DB6FA);
        contracts.rolesAdmin = RolesAdmin(0xb903fe62554fa810Df83B5C815457ff7949cc49F);

        contracts.escrowFactory = DelegateEscrowFactory(0xC97a3364Eb57F039ca106CAA5428C9D005Dd9D97);
        contracts.ltvOracle = CoolerLtvOracle(0x722100Cdb71CF1da003616E17D7bB12b71e1b763);
        contracts.treasuryBorrower = CoolerTreasuryBorrower(0x9Ba1662480350f464888AC5C7CdD73274D2a04D4);
        contracts.monoCooler = MonoCooler(0x38Ec1cd649DB8aE87fcaE33304aB1504BaE38255);
    }

    function deactivateOldMonoCooler(Contracts memory contracts) internal {
        fillContractsFromTestnet(contracts);
        contracts.kernel.executeAction(Actions.DeactivatePolicy, address(contracts.monoCooler));
        contracts.kernel.executeAction(Actions.DeactivatePolicy, address(contracts.ltvOracle));
        contracts.kernel.executeAction(Actions.DeactivatePolicy, address(contracts.treasuryBorrower));
    }

    function deploy(
        Contracts memory contracts,
        bytes32 salt,
        address admin,
        address others
    ) internal {
        fillContractsFromTestnet(contracts);

        deployExternalMocks(contracts, salt);

        deployOlympusCore(contracts, salt);
        installModulesAndPoliciesOlympusCore(contracts);

        deployMonoCooler(contracts, salt);
        installModulesAndPoliciesMonoCooler(contracts);
        setAccessMonoCooler(contracts, admin);
        enablePolicies(contracts);

        seedTreasury(contracts, others);

        // Do this at the end so we have access to do all that we need first
        setAccessOlympusCore(contracts, admin);
    }

    function updateMonoCooler(
        Contracts memory contracts,
        bytes32 salt
    ) internal {
        // Remove from old
        contracts.kernel.executeAction(Actions.DeactivatePolicy, address(contracts.monoCooler));
        contracts.rolesAdmin.revokeRole("treasuryborrower_cooler", address(contracts.monoCooler));

        // Add to new
        contracts.monoCooler = new MonoCooler{salt: salt}(
            address(contracts.OHM),
            address(contracts.gOHM),
            address(contracts.staking),
            address(contracts.kernel),
            address(contracts.ltvOracle),
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );
        contracts.monoCooler.setTreasuryBorrower(address(contracts.treasuryBorrower));
        contracts.kernel.executeAction(Actions.ActivatePolicy, address(contracts.monoCooler));
        contracts.rolesAdmin.grantRole("treasuryborrower_cooler", address(contracts.monoCooler));
    }

    function deployExternalMocks(
        Contracts memory contracts,
        bytes32 salt
    ) private {
        contracts.USDS = new MockERC20{salt: salt}("USDS", "USDS", 18);
        contracts.sUSDS = new MockSUsdsToken{salt: salt}(contracts.USDS);
        contracts.sUSDS.setInterestRate(SUSDS_INTEREST_RATE);
    }

    function deployOlympusCore(
        Contracts memory contracts,
        bytes32 salt
    ) private {
        contracts.OHM = new MockOhm{salt: salt}("OHM", "OHM", 9);
        contracts.gOHM = new MockGohm{salt: salt}("gOHM", "gOHM", 18);
        contracts.staking = new MockStaking{salt: salt}(address(contracts.OHM), address(contracts.gOHM));

        // Can't use the forge create2 factory here as msg.sender is assumed as the executor
        contracts.kernel = new Kernel/*{salt: salt}*/(); // this contract will be the executor

        contracts.TRSRY = new OlympusTreasury{salt: salt}(contracts.kernel);
        contracts.MINTR = new OlympusMinter{salt: salt}(contracts.kernel, address(contracts.OHM));
        contracts.ROLES = new OlympusRoles{salt: salt}(contracts.kernel);

        // Can't use the forge create2 factory here as msg.sender is assumed as the admin
        contracts.rolesAdmin = new RolesAdmin/*{salt: salt}*/(contracts.kernel);
    }

    function installModulesAndPoliciesOlympusCore(
        Contracts memory contracts
    ) private {
        contracts.kernel.executeAction(Actions.InstallModule, address(contracts.TRSRY));
        contracts.kernel.executeAction(Actions.InstallModule, address(contracts.MINTR));
        contracts.kernel.executeAction(Actions.InstallModule, address(contracts.ROLES));
        contracts.kernel.executeAction(Actions.ActivatePolicy, address(contracts.rolesAdmin));
    }

    function setAccessOlympusCore(
        Contracts memory contracts,
        address admin
    ) private {
        // Set roles admin (was this calling contract)
        // @todo admin needs to 2 phase accept this role with
        // contracts.rolesAdmin.pullNewAdmin();
        contracts.rolesAdmin.pushNewAdmin(admin);

        // Set Kernel executor (was this calling contract)
        contracts.kernel.executeAction(Actions.ChangeExecutor, admin);
    }

    function deployMonoCooler(
        Contracts memory contracts,
        bytes32 salt
    ) internal {
        contracts.escrowFactory = new DelegateEscrowFactory{salt: salt}(address(contracts.gOHM));
        contracts.DLGTE = new OlympusGovDelegation{salt: salt}(contracts.kernel, address(contracts.gOHM), contracts.escrowFactory);

        contracts.ltvOracle = new CoolerLtvOracle{salt: salt}(
            address(contracts.kernel),
            address(contracts.gOHM),
            address(contracts.USDS),
            DEFAULT_OLTV, 
            DEFAULT_OLTV_MAX_DELTA, 
            DEFAULT_OLTV_MIN_TARGET_TIME_DELTA, 
            DEFAULT_OLTV_MAX_RATE_OF_CHANGE,
            DEFAULT_LLTV_MAX_PREMIUM_BPS,
            DEFAULT_LLTV_PREMIUM_BPS
        );

        contracts.monoCooler = new MonoCooler{salt: salt}(
            address(contracts.OHM),
            address(contracts.gOHM),
            address(contracts.staking),
            address(contracts.kernel),
            address(contracts.ltvOracle),
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );

        contracts.treasuryBorrower = new CoolerTreasuryBorrower{salt: salt}(
            address(contracts.kernel),
            address(contracts.sUSDS)
        );

        contracts.monoCooler.setTreasuryBorrower(address(contracts.treasuryBorrower));
    }

    function installModulesAndPoliciesMonoCooler(
        Contracts memory contracts
    ) internal {
        // If it's an upgrade from an existing MonoCooler, then use: 
        // contracts.kernel.executeAction(Actions.UpgradeModule, address(contracts.DLGTE));
        contracts.kernel.executeAction(Actions.InstallModule, address(contracts.DLGTE));
        contracts.kernel.executeAction(Actions.ActivatePolicy, address(contracts.monoCooler));
        contracts.kernel.executeAction(Actions.ActivatePolicy, address(contracts.ltvOracle));
        contracts.kernel.executeAction(Actions.ActivatePolicy, address(contracts.treasuryBorrower));
    }

    function setAccessMonoCooler(
        Contracts memory contracts,
        address admin
    ) internal {
        // Configure cooler access control
        contracts.rolesAdmin.grantRole("treasuryborrower_cooler", address(contracts.monoCooler));
        contracts.rolesAdmin.grantRole("admin", admin);
        contracts.rolesAdmin.grantRole("admin", address(this)); // This deployer added as admin such that it can enable policies below
    }

    function enablePolicies(
        Contracts memory contracts
    ) internal {
        contracts.treasuryBorrower.enable(bytes(""));
    }

    function seedTreasury(
        Contracts memory contracts,
        address others
    ) private {
        // Setup Treasury
        contracts.USDS.mint(address(this), INITIAL_TRSRY_MINT);
        contracts.USDS.approve(address(contracts.sUSDS), INITIAL_TRSRY_MINT);
        contracts.sUSDS.deposit(INITIAL_TRSRY_MINT, address(contracts.TRSRY));

        // Fund others so that TRSRY is not the only account with sDAI shares
        contracts.USDS.mint(address(this), INITIAL_TRSRY_MINT * 3);
        contracts.USDS.approve(address(contracts.sUSDS), INITIAL_TRSRY_MINT * 3);
        contracts.sUSDS.deposit(INITIAL_TRSRY_MINT * 3, others);

        // Mint some OHM into staking for gOHM liquidations
        contracts.OHM.mint(address(contracts.staking), 100_000_000_000e9);
    }
}
