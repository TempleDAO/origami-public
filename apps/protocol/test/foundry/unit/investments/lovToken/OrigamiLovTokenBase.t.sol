pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { MockSDaiToken } from "contracts/test/external/maker/MockSDaiToken.m.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiMockLovTokenManager } from "test/foundry/mocks/investments/lovToken/OrigamiMockLovTokenManager.m.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";

contract OrigamiLovTokenTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public daiToken;
    MockSDaiToken public sDaiToken;
    OrigamiLovToken public lovToken;
    OrigamiMockLovTokenManager public manager;
    TokenPrices public tokenPrices;

    // When seeded, the vault has an extra 10% of assets
    // So each share is redeemable for 1.1 assets
    uint256 public constant VAULT_PREMIUM = 10;
    uint16 public constant MIN_DEPOSIT_FEE_BPS = 10;
    uint16 public constant MIN_EXIT_FEE_BPS = 50;
    uint16 public constant FEE_LEVERAGE_FACTOR = 15;
    uint256 public constant PERFORMANCE_FEE_BPS = 500;

    // 5% APR = 4.879% APY
    uint96 public constant SDAI_INTEREST_RATE = 0.05e18;
    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    Range.Data public userALRange;
    Range.Data public rebalanceALRange;

    function setUp() public virtual {
        daiToken = new DummyMintableToken(origamiMultisig, "DAI", "DAI", 18);
        sDaiToken = new MockSDaiToken(daiToken);
        sDaiToken.setInterestRate(SDAI_INTEREST_RATE);
        doMint(daiToken, address(sDaiToken), 100_000_000e18);

        tokenPrices = new TokenPrices(30);
        lovToken = new OrigamiLovToken(origamiMultisig, "Origami LOV TOKEN", "lovToken", PERFORMANCE_FEE_BPS, feeCollector, address(tokenPrices));
        manager = new OrigamiMockLovTokenManager(origamiMultisig, address(daiToken), address(sDaiToken), address(lovToken));

        vm.startPrank(origamiMultisig);
        lovToken.setManager(address(manager));
        manager.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);
        manager.setRedeemableReservesBufferBps(0);

        userALRange = Range.Data(1.001e18, type(uint128).max);
        rebalanceALRange = Range.Data(1.05e18, 1.15e18);

        manager.setUserALRange(userALRange.floor, userALRange.ceiling);
        manager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);

        vm.stopPrank();
    }

    function mintSDai(uint256 sDaiAmount, address to) internal {
        uint256 daiAmount = sDaiToken.previewMint(sDaiAmount);
        doMint(daiToken, to, daiAmount);
        vm.startPrank(to);
        daiToken.approve(address(sDaiToken), daiAmount);
        sDaiToken.mint(sDaiAmount, to);
    }

    function bootstrapSDai(uint256 amount) internal returns (uint256 sharePrice) {
        doMint(daiToken, alice, amount);
        vm.startPrank(alice);
        daiToken.approve(address(sDaiToken), amount);
        sDaiToken.deposit(amount, alice);

        // Move forward a year to accrue 5% to share price
        vm.warp(block.timestamp + 365 days);

        sharePrice = sDaiToken.convertToAssets(10 ** sDaiToken.decimals());
    }

    function investWithSDai(uint256 sDaiAmount, address to) internal virtual returns (uint256) {
        mintSDai(sDaiAmount, to);
        vm.startPrank(to);

        sDaiToken.approve(address(lovToken), sDaiAmount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = lovToken.investQuote(
            sDaiAmount,
            address(sDaiToken),
            0,
            0
        );

        vm.startPrank(to);
        return lovToken.investWithToken(quoteData);
    }

    function investWithDai(uint256 daiAmount, address to) internal returns (uint256) {
        doMint(daiToken, to, daiAmount);
        vm.startPrank(to);

        daiToken.approve(address(lovToken), daiAmount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = lovToken.investQuote(
            daiAmount,
            address(daiToken),
            0,
            0
        );

        vm.startPrank(to);
        return lovToken.investWithToken(quoteData);
    }

    function solveRebalanceDownAmount(address _manager, uint256 targetAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert CommonEventsAndErrors.InvalidParam();
        /*
          targetAL == (assets+X) / (liabilities+X);
          targetAL*(liabilities+X) == (assets+X)
          targetAL*liabilities + targetAL*X == assets+X
          targetAL*liabilities + targetAL*X - X == assets
          targetAL*X - X == assets - targetAL*liabilities
          X * (targetAL - 1) == assets - targetAL*liabilities
          X == (assets - targetAL*liabilities) / (targetAL - 1)
        */
        uint256 _assets = IOrigamiLovTokenManager(_manager).reservesBalance();
        uint256 _liabilities = IOrigamiLovTokenManager(_manager).liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = IOrigamiLovTokenManager(_manager).PRECISION();

        uint256 _netAssets = _assets - targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP);
        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function solveRebalanceUpAmount(address _manager, uint256 targetAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert CommonEventsAndErrors.InvalidParam();

        /*
          targetAL == (assets-X) / (liabilities-X);
          targetAL*(liabilities-X) == (assets-X)
          targetAL*liabilities - targetAL*X == assets-X
          targetAL*X - X == targetAL*liabilities - assets
          X - targetAL*X == targetAL*liabilities - assets
          X * (targetAL - 1) == targetAL*liabilities - assets
          X = (targetAL*liabilities - assets) / (targetAL - 1)
        */
        
        uint256 _assets = IOrigamiLovTokenManager(_manager).reservesBalance();
        uint256 _liabilities = IOrigamiLovTokenManager(_manager).liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = IOrigamiLovTokenManager(_manager).PRECISION();
        
        uint256 _netAssets = targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP) - _assets;
        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(uint256 targetAL) internal virtual returns (uint256 amount) {
        amount = solveRebalanceDownAmount(address(manager), targetAL);
        mintSDai(amount, address(this));
        sDaiToken.approve(address(manager), amount);
        manager.rebalanceDown(amount);
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(uint256 targetAL) internal virtual returns (uint256 amount) {
        amount = solveRebalanceUpAmount(address(manager), targetAL);
        manager.rebalanceUp(amount);
    }
}
