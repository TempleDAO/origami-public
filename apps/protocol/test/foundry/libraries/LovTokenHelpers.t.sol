pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/Chainlink.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";

library LovTokenHelpers {
    using OrigamiMath for uint256;

    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    function solveRebalanceDownAmount(IOrigamiLovTokenManager manager, uint256 targetAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceDownParam();
        uint256 currentAL = manager.assetToLiabilityRatio();
        if (targetAL >= currentAL) revert InvalidRebalanceDownParam();

        /*
          targetAL == (assets+X) / (liabilities+X);
          targetAL*(liabilities+X) == (assets+X)
          targetAL*liabilities + targetAL*X == assets+X
          targetAL*liabilities + targetAL*X - X == assets
          targetAL*X - X == assets - targetAL*liabilities
          X * (targetAL - 1) == assets - targetAL*liabilities
          X == (assets - targetAL*liabilities) / (targetAL - 1)
        */
        uint256 _assets = manager.reservesBalance();
        uint256 _liabilities = manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;

        uint256 _netAssets = _assets - targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP);

        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function solveRebalanceDownAmountWithOracle(
        IOrigamiLovTokenManager manager, 
        uint256 targetAL,
        uint256 dexPrice,
        uint256 oraclePrice
    ) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceDownParam();
        uint256 currentAL = manager.assetToLiabilityRatio();
        if (targetAL >= currentAL) revert InvalidRebalanceDownParam();

        // Note there may be a difference between the DEX executed price
        // vs the observed oracle price.
        // To account for this, the amount added to the liabilities needs to be scaled
        /*
            targetAL == (assets+X) / (liabilities+X*dexPrice/oraclePrice);
            targetAL*(liabilities+X*dexPrice/oraclePrice) == (assets+X)
            targetAL*liabilities + targetAL*X*dexPrice/oraclePrice == assets+X
            targetAL*liabilities + targetAL*X*dexPrice/oraclePrice - X == assets
            X*targetAL*dexPrice/oraclePrice - X == assets - targetAL*liabilities
            X * (targetAL*dexPrice/oraclePrice - 1) == assets - targetAL*liabilities
            X == (assets - targetAL*liabilities) / (targetAL*dexPrice/oraclePrice - 1)
        */
        uint256 _assets = manager.reservesBalance();
        uint256 _liabilities = manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;

        uint256 _netAssets = _assets - targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP);
        uint256 _priceScaledTargetAL = targetAL.mulDiv(dexPrice, oraclePrice, OrigamiMath.Rounding.ROUND_DOWN);
        reservesAmount = _netAssets.mulDiv(
            _precision,
            _priceScaledTargetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function solveRebalanceUpAmount(IOrigamiLovTokenManager manager, uint256 targetAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceUpParam();
        uint256 currentAL = manager.assetToLiabilityRatio();
        if (targetAL <= currentAL) revert InvalidRebalanceUpParam();

        /*
          targetAL == (assets-X) / (liabilities-X);
          targetAL*(liabilities-X) == (assets-X)
          targetAL*liabilities - targetAL*X == assets-X
          targetAL*X - X == targetAL*liabilities - assets
          X - targetAL*X == targetAL*liabilities - assets
          X * (targetAL - 1) == targetAL*liabilities - assets
          X = (targetAL*liabilities - assets) / (targetAL - 1)
        */
        uint256 _assets = manager.reservesBalance();
        uint256 _liabilities = manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;
        
        uint256 _netAssets = targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP) - _assets;
        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

}