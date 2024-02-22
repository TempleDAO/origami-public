// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/GMX_SafeMath.sol";
import "../libraries/token/GMX_IERC20.sol";

import "../core/interfaces/GMX_IGlpManager.sol";

import "./interfaces/GMX_IRewardTracker.sol";
import "./interfaces/GMX_IRewardTracker.sol";

// provide a way to transfer staked GLP tokens by unstaking from the sender
// and staking for the receiver
// tests in RewardRouterV2.js
contract GMX_StakedGlp {
    using GMX_SafeMath for uint256;

    string public constant name = "StakedGlp";
    string public constant symbol = "sGLP";
    uint8 public constant decimals = 18;

    address public glp;
    GMX_IGlpManager public glpManager;
    address public stakedGlpTracker;
    address public feeGlpTracker;

    mapping (address => mapping (address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _glp,
        GMX_IGlpManager _glpManager,
        address _stakedGlpTracker,
        address _feeGlpTracker
    ) public {
        glp = _glp;
        glpManager = _glpManager;
        stakedGlpTracker = _stakedGlpTracker;
        feeGlpTracker = _feeGlpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedGlp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }
    function balanceOf(address _account) external view returns (uint256) {
        return GMX_IRewardTracker(feeGlpTracker).depositBalances(_account, glp);
    }

    function totalSupply() external view returns (uint256) {
        return GMX_IERC20(stakedGlpTracker).totalSupply();
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "StakedGlp: approve from the zero address");
        require(_spender != address(0), "StakedGlp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "StakedGlp: transfer from the zero address");
        require(_recipient != address(0), "StakedGlp: transfer to the zero address");

        require(
            glpManager.lastAddedAt(_sender).add(glpManager.cooldownDuration()) <= block.timestamp,
            "StakedGlp: cooldown duration not yet passed"
        );

        GMX_IRewardTracker(stakedGlpTracker).unstakeForAccount(_sender, feeGlpTracker, _amount, _sender);
        GMX_IRewardTracker(feeGlpTracker).unstakeForAccount(_sender, glp, _amount, _sender);

        GMX_IRewardTracker(feeGlpTracker).stakeForAccount(_sender, _recipient, glp, _amount);
        GMX_IRewardTracker(stakedGlpTracker).stakeForAccount(_recipient, _recipient, feeGlpTracker, _amount);
    }
}
