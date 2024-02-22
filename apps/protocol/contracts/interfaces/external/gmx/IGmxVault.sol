pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/gmx/IGmxVault.sol)

interface IGmxVault {
    function getMinPrice(address _token) external view returns (uint256);
    function BASIS_POINTS_DIVISOR() external view returns (uint256);
    function PRICE_PRECISION() external view returns (uint256);
    function usdg() external view returns (address);
    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) external view returns (uint256);
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);
    function mintBurnFeeBasisPoints() external view returns (uint256);
    function taxBasisPoints() external view returns (uint256);
    function priceFeed() external view returns (address);
    function whitelistedTokens(address token) external view returns (bool);
    function getRedemptionAmount(address _token, uint256 _usdgAmount) external view returns (uint256);
    function hasDynamicFees() external view returns (bool);
    function usdgAmounts(address _token) external view returns (uint256);
    function getTargetUsdgAmount(address _token) external view returns (uint256);
    function allWhitelistedTokensLength() external view returns (uint256);
    function allWhitelistedTokens(uint256 index) external view returns (address);
    function totalTokenWeights() external view returns (uint256);
    function tokenWeights(address token) external view returns (uint256);
}
