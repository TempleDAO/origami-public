// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script } from "forge-std/Script.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { console } from "forge-std/console.sol";

import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { DLGTEv1 } from "contracts/test/external/olympus/src/modules/DLGTE/DLGTE.v1.sol";
import { IMonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";

contract TestnetMonoCoolerDeployer is Script, StdAssertions {
    address internal immutable ALICE = makeAddr("ALICE");

    function delegationRequest(
        address to,
        uint256 amount
    ) internal pure returns (DLGTEv1.DelegationRequest[] memory delegationRequests) {
        delegationRequests = new DLGTEv1.DelegationRequest[](1);
        delegationRequests[0] = DLGTEv1.DelegationRequest({delegate: to, amount: int256(amount)});
    }

    function checkAccountPosition(
        IMonoCooler cooler,
        address account,
        IMonoCooler.AccountPosition memory expectedPosition
    ) internal view {
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(account);
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
        
        assertEq(cooler.accountDebt(account), expectedPosition.currentDebt, "accountDebt()");
        assertEq(cooler.accountCollateral(account), expectedPosition.collateral, "accountCollateral()");
    }

    function localBorrowTest(
        OlympusMonoCoolerDeployerLib.Contracts memory deployedContracts
    ) private {
        vm.startPrank(ALICE);
        uint128 collateralAmount = 10e18; // [gOHM]
        uint128 borrowAmount = 25_000e18; // [USDS]
        deployedContracts.gOHM.mint(ALICE, collateralAmount);

        console.log("ALICE gOHM BALANCE:", deployedContracts.gOHM.balanceOf(ALICE));
        deployedContracts.gOHM.approve(address(deployedContracts.monoCooler), collateralAmount);
        deployedContracts.monoCooler.addCollateral(collateralAmount, ALICE, delegationRequest(ALICE, 3.3e18));
        deployedContracts.monoCooler.borrow(borrowAmount, ALICE, ALICE);

        checkAccountPosition(
            deployedContracts.monoCooler,
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: borrowAmount,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.196502560000000000e18,
                currentLtv: 2_500e18,
                totalDelegated: 3.3e18,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );
    }

    function doBorrow(
        OlympusMonoCoolerDeployerLib.Contracts memory deployedContracts,
        address caller
    ) private {
        uint128 collateralAmount = 10e18; // [gOHM]
        uint128 borrowAmount = 25_000e18; // [USDS]

        vm.startBroadcast();
        deployedContracts.gOHM.mint(caller, collateralAmount);
        deployedContracts.gOHM.approve(address(deployedContracts.monoCooler), collateralAmount);
        deployedContracts.monoCooler.addCollateral(collateralAmount, caller, delegationRequest(caller, 3.3e18));
        deployedContracts.monoCooler.borrow(borrowAmount, caller, caller);
        vm.stopBroadcast();

        checkAccountPosition(
            deployedContracts.monoCooler,
            caller,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: borrowAmount,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.196502560000000000e18,
                currentLtv: 2_500e18,
                totalDelegated: 3.3e18,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );
    }

    function deploy(OlympusMonoCoolerDeployerLib.Contracts memory deployedContracts) internal {
        bytes32 dummySalt = bytes32(0);

        address origamiMultisig = 0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526;
        console.log("msg.sender:", msg.sender);

        vm.startBroadcast();
        OlympusMonoCoolerDeployerLib.deploy(deployedContracts, dummySalt, origamiMultisig, origamiMultisig);
        // OlympusMonoCoolerDeployerLib.updateMonoCooler(deployedContracts, dummySalt);
        vm.stopBroadcast();
    }

    function run() external {
        OlympusMonoCoolerDeployerLib.Contracts memory deployedContracts;
        OlympusMonoCoolerDeployerLib.fillContractsFromTestnet(deployedContracts);

        deploy(deployedContracts);

        console.log("Contract addy's:");
        console.log("OHM:", address(deployedContracts.OHM));
        console.log("gOHM:", address(deployedContracts.gOHM));
        console.log("USDS:", address(deployedContracts.USDS));
        console.log("sUSDS:", address(deployedContracts.sUSDS));

        console.log("kernel:", address(deployedContracts.kernel));
        console.log("staking:", address(deployedContracts.staking));
        console.log("ROLES:", address(deployedContracts.ROLES));
        console.log("MINTR:", address(deployedContracts.MINTR));
        console.log("TRSRY:", address(deployedContracts.TRSRY));
        console.log("DLGTE:", address(deployedContracts.DLGTE));
        console.log("rolesAdmin:", address(deployedContracts.rolesAdmin));

        console.log("escrowFactory:", address(deployedContracts.escrowFactory));
        console.log("ltvOracle:", address(deployedContracts.ltvOracle));
        console.log("treasuryBorrower:", address(deployedContracts.treasuryBorrower));

        console.log("monoCooler:", address(deployedContracts.monoCooler));

        // localBorrowTest();
        doBorrow(deployedContracts, msg.sender);
    }
}
