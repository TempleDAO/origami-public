pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { MockGohm } from "contracts/test/external/olympus/test/mocks/MockGohm.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";

contract OrigamiHOhmCommon is OrigamiTest {
    uint16 internal constant PERFORMANCE_FEE = 330; // 3.3%
    uint16 internal constant EXIT_FEE_BPS = 100; // 1%

    // Starting share price:
    // 1 hOHM = 0.000003714158 gOHM
    //   1 [OHM] / 269.24 [OHM/gOHM] / 1000
    // 1 hOHM = 0.011 USDS
    //   11 [USDS/OHM] / 1000
    uint256 internal constant OHM_PER_GOHM = 269.24e18;
    uint256 internal constant SEED_GOHM_AMOUNT = 10e18;
    uint256 internal constant SEED_HOHM_SHARES = SEED_GOHM_AMOUNT * OHM_PER_GOHM * 1_000 / OrigamiMath.WAD;

    // Intentionally at the starting cooler origination LTV
    // This means no surplus to start - but as the OLTV increases (per second) hOHM can borrow more from cooler.
    uint256 internal constant SEED_USDS_AMOUNT = SEED_GOHM_AMOUNT * OlympusMonoCoolerDeployerLib.DEFAULT_OLTV / OrigamiMath.WAD;
    uint256 internal constant MAX_TOTAL_SUPPLY = type(uint256).max;

    OrigamiHOhmVault internal vault;
    MockERC20 internal USDS;
    MockGohm internal gOHM;

    event Join(
        address indexed sender,
        address indexed owner,
        uint256[] assets,
        uint256[] liabilities,
        uint256 shares
    );

    event Exit(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256[] assets,
        uint256[] liabilities,
        uint256 shares
    );

    function _checkInputTokenAmount(
        IERC20 token,
        uint256 tokenAmount,
        uint256[] memory assetAmounts,
        uint256[] memory liabilityAmounts
    ) internal view {
        if (address(token) == address(gOHM)) {
            assertEq(assetAmounts[0], tokenAmount, "gOHM input tokenAmount not matching derived output amount");
        } else if (address(token) == address(USDS)) {
            assertEq(liabilityAmounts[0], tokenAmount, "USDS input tokenAmount not matching derived output amount");
        } else {
            assertFalse(true, "unknown token in _checkInputTokenAmount");
        }
    }
}