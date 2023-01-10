pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/gmx/IOrigamiGmxManager.sol)

import {IOrigamiGmxEarnAccount} from "./IOrigamiGmxEarnAccount.sol";

interface IOrigamiGmxManager {
    function harvestableRewards(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts);
    function projectedRewardRates(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts);
    function harvestRewards() external;
    function harvestSecondaryRewards() external;
    function rewardTokensList() external view returns (address[] memory tokens);
    function wrappedNativeToken() external view returns (address);
    function primaryEarnAccount() external view returns (IOrigamiGmxEarnAccount);
    function secondaryEarnAccount() external view returns (IOrigamiGmxEarnAccount);
    function sellOGmxQuote(uint256 _oGmxAmount) external view returns (uint256 origamiFeeBasisPoints, uint256 gmxAmountOut);
    function sellOGmx(
        uint256 _sellAmount,
        address _recipient
    ) external returns (uint256 amountOut);
    function acceptedGlpTokens(address[] calldata extraTokens) external view returns (address[] memory);
    function buyOGlpQuote(uint256 _amount, address _token) external view returns (
        uint256 oGlpAmountOut, uint256[] memory investFeeBps, uint256 expectedUsdg
    );
    function sellOGlpQuote(uint256 _oGlpAmount, address _toToken) external view returns (
        uint256 toTokenAmount, uint256[] memory exitFeeBps
    );
    function sellOGlp(
        uint256 _sellAmount,
        address _toToken,
        uint256 _minAmountOut,
        uint256 _slippageBps,
        address _recipient
    ) external returns (uint256 amountOut);
    function sellOGlpToStakedGlp(
        uint256 _sellAmount,
        address _recipient
    ) external returns (uint256 amountOut);
}