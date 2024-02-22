pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/gmx/IGmxRewardRouter.sol)

interface IGmxRewardRouter {
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
    function stakeGmx(uint256 _amount) external;
    function unstakeGmx(uint256 _amount) external;
    function stakeEsGmx(uint256 _amount) external;
    function unstakeEsGmx(uint256 _amount) external;
    function gmx() external view returns (address);
    function glp() external view returns (address);
    function esGmx() external view returns (address);
    function bnGmx() external view returns (address);
    function weth() external view returns (address);
    function stakedGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function feeGlpTracker() external view returns (address);
    function bonusGmxTracker() external view returns (address);
    function gmxVester() external view returns (address);
    function glpVester() external view returns (address);
    function glpManager() external view returns (address);
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
}