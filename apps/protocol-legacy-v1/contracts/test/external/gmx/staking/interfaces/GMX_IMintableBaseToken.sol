// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../../libraries/token/GMX_IERC20.sol";
interface GMX_IMintableBaseToken is GMX_IERC20 {
    function isMinter(address _account) external view returns (bool);
    function setMinter(address _minter, bool _isActive) external;
    function mint(address _account, uint256 _amount) external;
    function burn(address _account, uint256 _amount) external;
    function gov() external view returns (address);
}
