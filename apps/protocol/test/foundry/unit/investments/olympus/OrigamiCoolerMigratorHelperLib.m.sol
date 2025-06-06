pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {
    ICooler,
    IOlympusCoolerFactoryV1_1,
    IOlympusCoolerFactoryV1_2,
    IOlympusClearinghouseV1_1,
    IOlympusClearinghouseV1_2
} from "contracts/interfaces/external/olympus/IOlympusCoolerV1.sol";
import { IDaiUsds } from "contracts/interfaces/external/makerdao/IDaiUsds.sol";
import { IERC3156FlashLender } from "contracts/interfaces/external/makerdao/IERC3156FlashLender.sol";

import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { MockGohm } from "contracts/test/external/olympus/test/mocks/MockGohm.sol";
import { RolesAdmin, Kernel } from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";
import { OlympusTreasury } from "contracts/test/external/olympus/src/modules/TRSRY/OlympusTreasury.sol";
import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { MockOhm } from "contracts/test/external/olympus/test/mocks/MockOhm.sol";
import { MockSUsdsToken } from "contracts/test/external/maker/MockSUsdsToken.m.sol";
import { MockStaking } from "contracts/test/external/olympus/test/mocks/MockStaking.sol";

library OrigamiCoolerMigratorHelperLib {
    struct MigratorTestContracts {
        IOlympusClearinghouseV1_1 clearinghousev1;
        IOlympusClearinghouseV1_2 clearinghousev2; // interface for both clearing houses the same
        IOlympusClearinghouseV1_2 clearinghousev3;
        IOlympusCoolerFactoryV1_1 factoryv1;
        IOlympusCoolerFactoryV1_2 factoryv2; // same for v3
        IERC20 DAI;
        IERC4626 sDai;
        IDaiUsds daiUsds;
        IERC3156FlashLender flashloanLender;
    }

    struct ContractAddresses {
        address dai;
        address gOHM;
        address ohm;
        address usds;
        address sUsds;
        address sDai;
        address daiUsds;
        address clearinghousev1;
        address clearinghousev2;
        address clearinghousev3;
        address factoryv1;
        address factoryv2;
        address kernel;
        address executor;
        address staking;
        address trsry;
        address rolesAdmin;
        address ltvOracle;
        address escrowFactory;
        address dlgte;
        address monoCooler;
        address flashloanLender;
        address timelock;
    }

    function getMainnetAddresses() internal pure returns (ContractAddresses memory) {
        ContractAddresses memory addresses;
        addresses.dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        addresses.gOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
        addresses.ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
        addresses.usds = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
        addresses.sUsds = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
        addresses.sDai = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
        addresses.daiUsds = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
        addresses.clearinghousev1 = 0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880;
        addresses.clearinghousev2 = 0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c;
        addresses.clearinghousev3 = 0x1e094fE00E13Fd06D64EeA4FB3cD912893606fE0;
        addresses.factoryv1 = 0xDE3e735d37A8498AD2F141F603A6d0F976A6F772;
        addresses.factoryv2 = 0x30Ce56e80aA96EbbA1E1a74bC5c0FEB5B0dB4216;
        addresses.kernel = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
        addresses.executor = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
        addresses.staking = 0xB63cac384247597756545b500253ff8E607a8020; // olympus staking
        addresses.trsry = 0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613;
        addresses.rolesAdmin = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
        addresses.flashloanLender = 0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA;
        addresses.timelock = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39; // Rolesadmin admin
        return addresses;
    }

    function exampleCoolers() internal pure returns (address[3] memory data){
        data[0] = 0x6f40DF8cC60F52125467838D15f9080748c2baea; // chud, 1 loan v1
        data[1] = 0x5bEC4E03B15e07e597702ca461CB6F4DB4DEb72f; // 3milli, 2 loans v2
        data[2] = 0xA7442440fb2627eAAB07f28b3E658D01dE0e5161; // 1 loan v3
    }

    function fillContractsFromMainnet(
        OlympusMonoCoolerDeployerLib.Contracts memory contracts,
        MigratorTestContracts memory mtContracts
    ) internal pure {
        ContractAddresses memory addresses = getMainnetAddresses();
        contracts.OHM = MockOhm(addresses.ohm);
        contracts.gOHM = MockGohm(addresses.gOHM);
        contracts.USDS = MockERC20(addresses.usds);
        contracts.sUSDS = MockSUsdsToken(addresses.sUsds);
        contracts.kernel = Kernel(addresses.kernel);
        contracts.staking = MockStaking(addresses.staking);
        contracts.TRSRY = OlympusTreasury(addresses.trsry);
        contracts.rolesAdmin = RolesAdmin(addresses.rolesAdmin);

        mtContracts.DAI = IERC20(addresses.dai);
        mtContracts.sDai = IERC4626(addresses.sDai);
        mtContracts.daiUsds = IDaiUsds(addresses.daiUsds);
        mtContracts.flashloanLender = IERC3156FlashLender(addresses.flashloanLender);
        mtContracts.clearinghousev1 = IOlympusClearinghouseV1_1(addresses.clearinghousev1);
        mtContracts.clearinghousev2 = IOlympusClearinghouseV1_2(addresses.clearinghousev2);
        mtContracts.clearinghousev3 = IOlympusClearinghouseV1_2(addresses.clearinghousev3);
        mtContracts.factoryv1 = IOlympusCoolerFactoryV1_1(addresses.factoryv1);
        mtContracts.factoryv2 = IOlympusCoolerFactoryV1_2(addresses.factoryv2);
    }

    function deployAndConfigureMonoCooler(
        OlympusMonoCoolerDeployerLib.Contracts memory contracts
    ) internal {
        OlympusMonoCoolerDeployerLib.deployMonoCooler(contracts, bytes32(0));
        OlympusMonoCoolerDeployerLib.installModulesAndPoliciesMonoCooler(contracts);
    }

    function setAccessMonoCooler(
        OlympusMonoCoolerDeployerLib.Contracts memory contracts,
        address admin
    ) internal {
        OlympusMonoCoolerDeployerLib.setAccessMonoCooler(contracts, admin);
    }

    function enableOracleAndTrsryBorrowerPolicies(
        OlympusMonoCoolerDeployerLib.Contracts memory contracts
    ) internal {
        OlympusMonoCoolerDeployerLib.enablePolicies(contracts);
    }
}