pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { RepricingToken } from "contracts/common/RepricingToken.sol";
import { OrigamiInvestmentVault } from "contracts/investments/OrigamiInvestmentVault.sol";
import { OrigamiLendingRewardsMinter } from "contracts/investments/lending/OrigamiLendingRewardsMinter.sol";
import { OrigamiDebtToken } from "contracts/investments/lending/OrigamiDebtToken.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiLendingRewardsMinterTestBase is OrigamiTest {
    DummyMintableToken public oToken;
    OrigamiInvestmentVault public ovToken;
    OrigamiDebtToken public debtToken;
    TokenPrices public tokenPrices;

    OrigamiLendingRewardsMinter public rewardsMinter;

    uint256 public carryOverBps = 1_000; // 10%
    uint256 public performanceFeeBps = 200; // 2%
    uint96 public aliceDebtInterestRate = 0.02e18; // 2%
    uint96 public bobDebtInterestRate = 0.05e18; // 5%

    uint256 public constant TWO_PCT_365DAY = 102020134002675580900;
    uint256 public constant TWO_PCT_730DAY = 104081077419238822439;

    function _setUp() public {
        vm.startPrank(origamiMultisig);

        tokenPrices = new TokenPrices(30);
        oToken = new DummyMintableToken(origamiMultisig, "oToken", "oToken", 18);
        ovToken = new OrigamiInvestmentVault(
            origamiMultisig,
            "ovToken", "ovToken",
            address(oToken),
            address(tokenPrices),
            performanceFeeBps,
            2 days
        );

        debtToken = new OrigamiDebtToken("Origami iToken", "iToken", origamiMultisig);
        debtToken.setMinter(origamiMultisig, true);
        debtToken.setInterestRate(alice, aliceDebtInterestRate);
        debtToken.setInterestRate(bob, bobDebtInterestRate);

        rewardsMinter = new OrigamiLendingRewardsMinter(
            origamiMultisig,
            address(oToken),
            address(ovToken),
            address(debtToken),
            carryOverBps,
            feeCollector
        );

        oToken.addMinter(address(rewardsMinter));
        setExplicitAccess(
            ovToken, 
            address(rewardsMinter), 
            RepricingToken.addPendingReserves.selector,
            true
        );
        vm.stopPrank();
    }
}

contract OrigamiLendingRewardsMinterTestAdmin is OrigamiLendingRewardsMinterTestBase {
    event CarryOverRateSet(uint256 rate);
    event FeeCollectorSet(address indexed feeCollector);

    function setUp() public {
        _setUp();
    }

    function test_initialization() public {
        assertEq(address(rewardsMinter.owner()), origamiMultisig);
        assertEq(address(rewardsMinter.oToken()), address(oToken));
        assertEq(address(rewardsMinter.ovToken()), address(ovToken));
        assertEq(address(rewardsMinter.debtToken()), address(debtToken));
        assertEq(rewardsMinter.carryOverRate(), carryOverBps);
        assertEq(address(rewardsMinter.feeCollector()), feeCollector);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
    }

    function test_constructor_fail() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        rewardsMinter = new OrigamiLendingRewardsMinter(
            origamiMultisig,
            address(oToken),
            address(ovToken),
            address(debtToken),
            10_000+1,
            feeCollector
        );
    }

    function test_setCarryOverRate_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        rewardsMinter.setCarryOverRate(10_000 + 1);
    }

    function test_setCarryOverRate_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(rewardsMinter));
        emit CarryOverRateSet(50);
        rewardsMinter.setCarryOverRate(50);
        assertEq(rewardsMinter.carryOverRate(), 50);
    }

    function test_setFeeCollector_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        rewardsMinter.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(rewardsMinter));
        emit FeeCollectorSet(alice);
        rewardsMinter.setFeeCollector(alice);
        assertEq(address(rewardsMinter.feeCollector()), alice);
    }

    function test_recoverToken() public {
        check_recoverToken(address(rewardsMinter));
    }
}

contract OrigamiLendingRewardsMinterTestAccess is OrigamiLendingRewardsMinterTestBase {
    function setUp() public {
        _setUp();
    }

    function test_access_setCarryOverRate() public {
        expectElevatedAccess();
        rewardsMinter.setCarryOverRate(123);
    }

    function test_access_setFeeCollector() public {
        expectElevatedAccess();
        rewardsMinter.setFeeCollector(alice);
    }

    function test_access_checkpointDebtAndMintRewards() public {
        expectElevatedAccess();
        rewardsMinter.checkpointDebtAndMintRewards(new address[](0));
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        rewardsMinter.recoverToken(alice, alice, 100e18);
    }
}

contract OrigamiLendingRewardsMinterTestMint is OrigamiLendingRewardsMinterTestBase {
    using OrigamiMath for uint256;

    event RewardsMinted(uint256 newReservesAmmount, uint256 feeAmount);
    event PendingReservesAdded(uint256 amount);

    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_checkpointDebtAndMintRewards_noDebt() public {
        rewardsMinter.checkpointDebtAndMintRewards(new address[](0));
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
    }

    function test_checkpointDebtAndMintRewards_noDebt_unknownDebtors() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
    }

    function test_checkpointDebtAndMintRewards_onlyPrincipal() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;
        
        debtToken.mint(alice, amount);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
    }

    function test_checkpointDebtAndMintRewards_noDebtorCheckpoint() public {
        address[] memory debtors = new address[](0);
        uint256 amount = 100e18;
        
        debtToken.mint(alice, amount);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);

        vm.warp(block.timestamp + 365 days);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
    }

    function test_checkpointDebtAndMintRewards_manualCheckpoint() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        uint256 expectedInterest = TWO_PCT_365DAY - amount;
        uint256 expectedMinted = expectedInterest.subtractBps(carryOverBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedReserves = expectedMinted.subtractBps(performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedFees = expectedMinted - expectedReserves;
        
        debtToken.mint(alice, amount);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);

        vm.warp(block.timestamp + 365 days);
        debtToken.checkpointDebtorsInterest(debtors);

        vm.expectEmit(address(rewardsMinter));
        emit RewardsMinted(expectedReserves, expectedFees);
        vm.expectEmit(address(ovToken));
        emit PendingReservesAdded(expectedReserves);
        rewardsMinter.checkpointDebtAndMintRewards(new address[](0));
        assertEq(oToken.totalSupply(), expectedMinted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expectedMinted);
        assertEq(oToken.balanceOf(feeCollector), expectedFees);
        assertEq(oToken.balanceOf(address(ovToken)), expectedReserves);
    }

    function test_checkpointDebtAndMintRewards_autoCheckpoint() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        uint256 expectedInterest = TWO_PCT_365DAY - amount;
        uint256 expectedMinted = expectedInterest.subtractBps(carryOverBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedReserves = expectedMinted.subtractBps(performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedFees = expectedMinted - expectedReserves;
        
        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        vm.expectEmit(address(rewardsMinter));
        emit RewardsMinted(expectedReserves, expectedFees);
        vm.expectEmit(address(ovToken));
        emit PendingReservesAdded(expectedReserves);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expectedMinted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expectedMinted);
        assertEq(oToken.balanceOf(feeCollector), expectedFees);
        assertEq(oToken.balanceOf(address(ovToken)), expectedReserves);
    }

    function test_checkpointDebtAndMintRewards_100pctPerfFees() public {
        ovToken.setPerformanceFee(OrigamiMath.BASIS_POINTS_DIVISOR);

        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        uint256 expectedInterest = TWO_PCT_365DAY - amount;
        uint256 expectedMinted = expectedInterest.subtractBps(carryOverBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedFees = expectedMinted;
        uint256 expectedReserves = 0;
        
        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expectedMinted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expectedMinted);
        assertEq(oToken.balanceOf(feeCollector), expectedFees);
        assertEq(oToken.balanceOf(address(ovToken)), expectedReserves);
    }

    function test_checkpointDebtAndMintRewards_0pctPerfFees() public {
        ovToken.setPerformanceFee(0);

        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        uint256 expectedInterest = TWO_PCT_365DAY - amount;
        uint256 expectedMinted = expectedInterest.subtractBps(carryOverBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedFees = 0;
        uint256 expectedReserves = expectedMinted;
        
        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        vm.expectEmit(address(rewardsMinter));
        emit RewardsMinted(expectedReserves, expectedFees);
        vm.expectEmit(address(ovToken));
        emit PendingReservesAdded(expectedReserves);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expectedMinted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expectedMinted);
        assertEq(oToken.balanceOf(feeCollector), expectedFees);
        assertEq(oToken.balanceOf(address(ovToken)), expectedReserves);
    }

    function test_checkpointDebtAndMintRewards_100pctCarryOver() public {
        rewardsMinter.setCarryOverRate(OrigamiMath.BASIS_POINTS_DIVISOR);

        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
        assertEq(oToken.balanceOf(feeCollector), 0);
        assertEq(oToken.balanceOf(address(ovToken)), 0);
    }

    function test_checkpointDebtAndMintRewards_0pctCarryOver() public {
        rewardsMinter.setCarryOverRate(0);

        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        uint256 expectedInterest = TWO_PCT_365DAY - amount;
        uint256 expectedMinted = expectedInterest;
        uint256 expectedReserves = expectedMinted.subtractBps(performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedFees = expectedMinted - expectedReserves;
        
        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        vm.expectEmit(address(rewardsMinter));
        emit RewardsMinted(expectedReserves, expectedFees);
        vm.expectEmit(address(ovToken));
        emit PendingReservesAdded(expectedReserves);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expectedMinted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expectedMinted);
        assertEq(oToken.balanceOf(feeCollector), expectedFees);
        assertEq(oToken.balanceOf(address(ovToken)), expectedReserves);
    }

    struct Expected {
        uint256 interest;
        uint256 minted;
        uint256 fees;
        uint256 reserves;
    }

    function makeExpected(uint256 expectedInterest) internal view returns (Expected memory) {
        uint256 expectedMinted = expectedInterest.subtractBps(carryOverBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedReserves = expectedMinted.subtractBps(performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 expectedFees = expectedMinted - expectedReserves;
        return Expected(expectedInterest, expectedMinted, expectedFees, expectedReserves);
    }

    function test_checkpointDebtAndMintRewards_successiveMints() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        Expected memory expected1 = makeExpected(TWO_PCT_365DAY - amount);
        
        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expected1.minted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expected1.minted);
        assertEq(oToken.balanceOf(feeCollector), expected1.fees);
        assertEq(oToken.balanceOf(address(ovToken)), expected1.reserves);

        // After another immediate call, another 10% is minted
        Expected memory expected2 = makeExpected(expected1.interest - expected1.minted);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expected1.minted + expected2.minted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expected1.minted + expected2.minted);
        assertEq(oToken.balanceOf(feeCollector), expected1.fees + expected2.fees);
        assertEq(oToken.balanceOf(address(ovToken)), expected1.reserves + expected2.reserves);

        // A change after another year    
        Expected memory expected3 = makeExpected((TWO_PCT_730DAY-TWO_PCT_365DAY) + (expected2.interest-expected2.minted) - 1);

        vm.warp(block.timestamp + 365 days);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expected1.minted + expected2.minted + expected3.minted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expected1.minted + expected2.minted + expected3.minted);
        assertEq(oToken.balanceOf(feeCollector), expected1.fees + expected2.fees + expected3.fees);
        assertEq(oToken.balanceOf(address(ovToken)), expected1.reserves + expected2.reserves + expected3.reserves);
    }

    function test_checkpointDebtAndMintRewards_extraBalance() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        uint256 amount = 100e18;

        Expected memory expected1 = makeExpected(TWO_PCT_365DAY - amount);
        
        debtToken.mint(alice, amount);
        vm.warp(block.timestamp + 365 days);

        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expected1.minted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expected1.minted);
        assertEq(oToken.balanceOf(feeCollector), expected1.fees);
        assertEq(oToken.balanceOf(address(ovToken)), expected1.reserves);

        // Deal extra rewards into the rewardsMinter. This is also added
        // (fee free) to the ovToken
        uint256 extraTokens = 1.23e18;
        deal(address(oToken), address(rewardsMinter), extraTokens, true);

        // After another immediate call, another 10% is minted
        Expected memory expected2 = makeExpected(expected1.interest - expected1.minted);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expected1.minted + expected2.minted + extraTokens);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expected1.minted + expected2.minted);
        assertEq(oToken.balanceOf(feeCollector), expected1.fees + expected2.fees);
        assertEq(oToken.balanceOf(address(ovToken)), expected1.reserves + expected2.reserves + extraTokens);

        // A change after another year    
        Expected memory expected3 = makeExpected((TWO_PCT_730DAY-TWO_PCT_365DAY) + (expected2.interest-expected2.minted) - 1);

        vm.warp(block.timestamp + 365 days);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), expected1.minted + expected2.minted + extraTokens + expected3.minted);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), expected1.minted + expected2.minted + expected3.minted);
        assertEq(oToken.balanceOf(feeCollector), expected1.fees + expected2.fees + expected3.fees);
        assertEq(oToken.balanceOf(address(ovToken)), expected1.reserves + expected2.reserves + extraTokens + expected3.reserves);
    }

    function test_checkpointDebtAndMintRewards_freshExtraBalance() public {
        address[] memory debtors = new address[](1);
        debtors[0] = alice;
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), 0);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
        assertEq(oToken.balanceOf(feeCollector), 0);
        assertEq(oToken.balanceOf(address(ovToken)), 0);

        uint256 extraTokens = 1.23e18;
        deal(address(oToken), address(rewardsMinter), extraTokens, true);
        rewardsMinter.checkpointDebtAndMintRewards(debtors);
        assertEq(oToken.totalSupply(), extraTokens);
        assertEq(rewardsMinter.cumulativeInterestCheckpoint(), 0);
        assertEq(oToken.balanceOf(feeCollector), 0);
        assertEq(oToken.balanceOf(address(ovToken)), extraTokens);
    }
}
