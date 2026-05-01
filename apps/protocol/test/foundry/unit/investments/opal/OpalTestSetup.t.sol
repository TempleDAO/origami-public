pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalManager } from "contracts/investments/opal/OpalManager.sol";
import { OpalVault } from "contracts/investments/opal/OpalVault.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";

import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

contract OpalTestSetup is OrigamiTest {
    OpalManager internal manager;
    OpalVault internal vault;
    TokenPrices internal tokenPrices;

    OpalAdapterFactory internal adapterFactory;

    address internal ASSET1;
    address internal ASSET1_6DP;
    address internal ASSET2;
    address internal ASSET3;
    address internal ASSET4;
    address internal ASSET5;
    address internal ASSET6;
    address internal DEBT1;
    address internal DEBT1_6DP;
    address internal DEBT2;
    address internal DEBT3;
    address internal DEBT4;
    address internal DEBT5;
    address internal DEBT6;

    bytes32 internal DEFAULT_GROUP_ID = bytes32("DEFAULT");

    uint16 internal PERFORMANCE_FEE = 330; // 3.3%
    uint256 internal MAX_SAFE_LTV = 0.75e18; // 75%

    function setUp() public virtual {
        tokenPrices = new TokenPrices(30);
        vault = new OpalVault(origamiMultisig, "OPAL", "everLov", PERFORMANCE_FEE, feeCollector, address(tokenPrices));
        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        manager = new OpalManager(origamiMultisig, address(vault), address(adapterFactory));

        ASSET1 = address(new DummyMintableTokenPermissionless("ASSET1", "ASSET1", 18));
        vm.label(ASSET1, "ASSET1");
        ASSET1_6DP = address(new DummyMintableTokenPermissionless("ASSET1_6DP", "ASSET1_6DP", 6));
        vm.label(ASSET1_6DP, "ASSET1_6DP");
        ASSET2 = address(new DummyMintableTokenPermissionless("ASSET2", "ASSET2", 18));
        vm.label(ASSET2, "ASSET2");
        ASSET3 = address(new DummyMintableTokenPermissionless("ASSET3", "ASSET3", 18));
        vm.label(ASSET3, "ASSET3");
        ASSET4 = address(new DummyMintableTokenPermissionless("ASSET4", "ASSET4", 18));
        vm.label(ASSET4, "ASSET4");
        ASSET5 = address(new DummyMintableTokenPermissionless("ASSET5", "ASSET5", 18));
        vm.label(ASSET5, "ASSET5");
        ASSET6 = address(new DummyMintableTokenPermissionless("ASSET6", "ASSET6", 18));
        vm.label(ASSET6, "ASSET6");
        DEBT1 = address(new DummyMintableTokenPermissionless("DEBT1", "DEBT1", 18));
        vm.label(DEBT1, "DEBT1");
        DEBT1_6DP = address(new DummyMintableTokenPermissionless("DEBT1_6DP", "DEBT1_6DP", 6));
        vm.label(DEBT1_6DP, "DEBT1_6DP");
        DEBT2 = address(new DummyMintableTokenPermissionless("DEBT2", "DEBT2", 18));
        vm.label(DEBT2, "DEBT2");
        DEBT3 = address(new DummyMintableTokenPermissionless("DEBT3", "DEBT3", 18));
        vm.label(DEBT3, "DEBT3");
        DEBT4 = address(new DummyMintableTokenPermissionless("DEBT4", "DEBT4", 18));
        vm.label(DEBT4, "DEBT4");
        DEBT5 = address(new DummyMintableTokenPermissionless("DEBT5", "DEBT5", 18));
        vm.label(DEBT5, "DEBT5");
        DEBT6 = address(new DummyMintableTokenPermissionless("DEBT6", "DEBT6", 18));
        vm.label(DEBT6, "DEBT6");

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vm.stopPrank();
    }
}
