// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/GMX_SafeMath.sol";
import "../libraries/token/GMX_IERC20.sol";
import "../libraries/token/GMX_SafeERC20.sol";
import "../libraries/utils/GMX_ReentrancyGuard.sol";
import "../libraries/utils/GMX_Address.sol";

import "./interfaces/GMX_IRewardTracker.sol";
import "./interfaces/GMX_IRewardRouterV2.sol";
import "./interfaces/GMX_IVester.sol";
import "../tokens/interfaces/GMX_IMintable.sol";
import "../tokens/interfaces/GMX_IWETH.sol";
import "../core/interfaces/GMX_IGlpManager.sol";
import "../access/GMX_Governable.sol";

contract GMX_RewardRouterV2 is GMX_IRewardRouterV2, GMX_ReentrancyGuard, GMX_Governable {
    using GMX_SafeMath for uint256;
    using GMX_SafeERC20 for GMX_IERC20;
    using GMX_Address for address payable;

    bool public isInitialized;

    address public weth;

    address public gmx;
    address public esGmx;
    address public bnGmx;

    address public glp; // GMX Liquidity Provider token

    address public stakedGmxTracker;
    address public bonusGmxTracker;
    address public feeGmxTracker;

    address public override stakedGlpTracker;
    address public override feeGlpTracker;

    address public glpManager;

    address public gmxVester;
    address public glpVester;

    mapping (address => address) public pendingReceivers;

    event StakeGmx(address account, address token, uint256 amount);
    event UnstakeGmx(address account, address token, uint256 amount);

    event StakeGlp(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _gmx,
        address _esGmx,
        address _bnGmx,
        address _glp,
        address _stakedGmxTracker,
        address _bonusGmxTracker,
        address _feeGmxTracker,
        address _feeGlpTracker,
        address _stakedGlpTracker,
        address _glpManager,
        address _gmxVester,
        address _glpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        gmx = _gmx;
        esGmx = _esGmx;
        bnGmx = _bnGmx;

        glp = _glp;

        stakedGmxTracker = _stakedGmxTracker;
        bonusGmxTracker = _bonusGmxTracker;
        feeGmxTracker = _feeGmxTracker;

        feeGlpTracker = _feeGlpTracker;
        stakedGlpTracker = _stakedGlpTracker;

        glpManager = _glpManager;

        gmxVester = _gmxVester;
        glpVester = _glpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        GMX_IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeGmxForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _gmx = gmx;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeGmx(msg.sender, _accounts[i], _gmx, _amounts[i]);
        }
    }

    function stakeGmxForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeGmx(msg.sender, _account, gmx, _amount);
    }

    function stakeGmx(uint256 _amount) external nonReentrant {
        _stakeGmx(msg.sender, msg.sender, gmx, _amount);
    }

    function stakeEsGmx(uint256 _amount) external nonReentrant {
        _stakeGmx(msg.sender, msg.sender, esGmx, _amount);
    }

    function unstakeGmx(uint256 _amount) external nonReentrant {
        _unstakeGmx(msg.sender, gmx, _amount, true);
    }

    function unstakeEsGmx(uint256 _amount) external nonReentrant {
        _unstakeGmx(msg.sender, esGmx, _amount, true);
    }

    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 glpAmount = GMX_IGlpManager(glpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minGlp);
        GMX_IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        GMX_IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        GMX_IWETH(weth).deposit{value: msg.value}();
        GMX_IERC20(weth).approve(glpManager, msg.value);

        address account = msg.sender;
        uint256 glpAmount = GMX_IGlpManager(glpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsdg, _minGlp);

        GMX_IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        GMX_IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        GMX_IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        GMX_IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        uint256 amountOut = GMX_IGlpManager(glpManager).removeLiquidityForAccount(account, _tokenOut, _glpAmount, _minOut, _receiver);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        GMX_IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        GMX_IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        uint256 amountOut = GMX_IGlpManager(glpManager).removeLiquidityForAccount(account, weth, _glpAmount, _minOut, address(this));

        GMX_IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        GMX_IRewardTracker(feeGmxTracker).claimForAccount(account, account);
        GMX_IRewardTracker(feeGlpTracker).claimForAccount(account, account);

        GMX_IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
        GMX_IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimEsGmx() external nonReentrant {
        address account = msg.sender;

        GMX_IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
        GMX_IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        GMX_IRewardTracker(feeGmxTracker).claimForAccount(account, account);
        GMX_IRewardTracker(feeGlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 gmxAmount = 0;
        if (_shouldClaimGmx) {
            uint256 gmxAmount0 = GMX_IVester(gmxVester).claimForAccount(account, account);
            uint256 gmxAmount1 = GMX_IVester(glpVester).claimForAccount(account, account);
            gmxAmount = gmxAmount0.add(gmxAmount1);
        }

        if (_shouldStakeGmx && gmxAmount > 0) {
            _stakeGmx(account, account, gmx, gmxAmount);
        }

        uint256 esGmxAmount = 0;
        if (_shouldClaimEsGmx) {
            uint256 esGmxAmount0 = GMX_IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
            uint256 esGmxAmount1 = GMX_IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
            esGmxAmount = esGmxAmount0.add(esGmxAmount1);
        }

        if (_shouldStakeEsGmx && esGmxAmount > 0) {
            _stakeGmx(account, account, esGmx, esGmxAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnGmxAmount = GMX_IRewardTracker(bonusGmxTracker).claimForAccount(account, account);
            if (bnGmxAmount > 0) {
                GMX_IRewardTracker(feeGmxTracker).stakeForAccount(account, account, bnGmx, bnGmxAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = GMX_IRewardTracker(feeGmxTracker).claimForAccount(account, address(this));
                uint256 weth1 = GMX_IRewardTracker(feeGlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);
                GMX_IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                GMX_IRewardTracker(feeGmxTracker).claimForAccount(account, account);
                GMX_IRewardTracker(feeGlpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(GMX_IERC20(gmxVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(GMX_IERC20(glpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(GMX_IERC20(gmxVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(GMX_IERC20(glpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedGmx = GMX_IRewardTracker(stakedGmxTracker).depositBalances(_sender, gmx);
        if (stakedGmx > 0) {
            _unstakeGmx(_sender, gmx, stakedGmx, false);
            _stakeGmx(_sender, receiver, gmx, stakedGmx);
        }

        uint256 stakedEsGmx = GMX_IRewardTracker(stakedGmxTracker).depositBalances(_sender, esGmx);
        if (stakedEsGmx > 0) {
            _unstakeGmx(_sender, esGmx, stakedEsGmx, false);
            _stakeGmx(_sender, receiver, esGmx, stakedEsGmx);
        }

        uint256 stakedBnGmx = GMX_IRewardTracker(feeGmxTracker).depositBalances(_sender, bnGmx);
        if (stakedBnGmx > 0) {
            GMX_IRewardTracker(feeGmxTracker).unstakeForAccount(_sender, bnGmx, stakedBnGmx, _sender);
            GMX_IRewardTracker(feeGmxTracker).stakeForAccount(_sender, receiver, bnGmx, stakedBnGmx);
        }

        uint256 esGmxBalance = GMX_IERC20(esGmx).balanceOf(_sender);
        if (esGmxBalance > 0) {
            GMX_IERC20(esGmx).transferFrom(_sender, receiver, esGmxBalance);
        }

        uint256 glpAmount = GMX_IRewardTracker(feeGlpTracker).depositBalances(_sender, glp);
        if (glpAmount > 0) {
            GMX_IRewardTracker(stakedGlpTracker).unstakeForAccount(_sender, feeGlpTracker, glpAmount, _sender);
            GMX_IRewardTracker(feeGlpTracker).unstakeForAccount(_sender, glp, glpAmount, _sender);

            GMX_IRewardTracker(feeGlpTracker).stakeForAccount(_sender, receiver, glp, glpAmount);
            GMX_IRewardTracker(stakedGlpTracker).stakeForAccount(receiver, receiver, feeGlpTracker, glpAmount);
        }

        GMX_IVester(gmxVester).transferStakeValues(_sender, receiver);
        GMX_IVester(glpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(GMX_IRewardTracker(stakedGmxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedGmxTracker.averageStakedAmounts > 0");
        require(GMX_IRewardTracker(stakedGmxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedGmxTracker.cumulativeRewards > 0");

        require(GMX_IRewardTracker(bonusGmxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusGmxTracker.averageStakedAmounts > 0");
        require(GMX_IRewardTracker(bonusGmxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusGmxTracker.cumulativeRewards > 0");

        require(GMX_IRewardTracker(feeGmxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeGmxTracker.averageStakedAmounts > 0");
        require(GMX_IRewardTracker(feeGmxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeGmxTracker.cumulativeRewards > 0");

        require(GMX_IVester(gmxVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: gmxVester.transferredAverageStakedAmounts > 0");
        require(GMX_IVester(gmxVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: gmxVester.transferredCumulativeRewards > 0");

        require(GMX_IRewardTracker(stakedGlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedGlpTracker.averageStakedAmounts > 0");
        require(GMX_IRewardTracker(stakedGlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedGlpTracker.cumulativeRewards > 0");

        require(GMX_IRewardTracker(feeGlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeGlpTracker.averageStakedAmounts > 0");
        require(GMX_IRewardTracker(feeGlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeGlpTracker.cumulativeRewards > 0");

        require(GMX_IVester(glpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: gmxVester.transferredAverageStakedAmounts > 0");
        require(GMX_IVester(glpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: gmxVester.transferredCumulativeRewards > 0");

        require(GMX_IERC20(gmxVester).balanceOf(_receiver) == 0, "RewardRouter: gmxVester.balance > 0");
        require(GMX_IERC20(glpVester).balanceOf(_receiver) == 0, "RewardRouter: glpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundGmx(_account);
        _compoundGlp(_account);
    }

    function _compoundGmx(address _account) private {
        uint256 esGmxAmount = GMX_IRewardTracker(stakedGmxTracker).claimForAccount(_account, _account);
        if (esGmxAmount > 0) {
            _stakeGmx(_account, _account, esGmx, esGmxAmount);
        }

        uint256 bnGmxAmount = GMX_IRewardTracker(bonusGmxTracker).claimForAccount(_account, _account);
        if (bnGmxAmount > 0) {
            GMX_IRewardTracker(feeGmxTracker).stakeForAccount(_account, _account, bnGmx, bnGmxAmount);
        }
    }

    function _compoundGlp(address _account) private {
        uint256 esGmxAmount = GMX_IRewardTracker(stakedGlpTracker).claimForAccount(_account, _account);
        if (esGmxAmount > 0) {
            _stakeGmx(_account, _account, esGmx, esGmxAmount);
        }
    }

    function _stakeGmx(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");
        GMX_IRewardTracker(stakedGmxTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        GMX_IRewardTracker(bonusGmxTracker).stakeForAccount(_account, _account, stakedGmxTracker, _amount);
        GMX_IRewardTracker(feeGmxTracker).stakeForAccount(_account, _account, bonusGmxTracker, _amount);
        emit StakeGmx(_account, _token, _amount);
    }

    function _unstakeGmx(address _account, address _token, uint256 _amount, bool _shouldReduceBnGmx) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = GMX_IRewardTracker(stakedGmxTracker).stakedAmounts(_account);

        GMX_IRewardTracker(feeGmxTracker).unstakeForAccount(_account, bonusGmxTracker, _amount, _account);
        GMX_IRewardTracker(bonusGmxTracker).unstakeForAccount(_account, stakedGmxTracker, _amount, _account);
        GMX_IRewardTracker(stakedGmxTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnGmx) {
            uint256 bnGmxAmount = GMX_IRewardTracker(bonusGmxTracker).claimForAccount(_account, _account);
            if (bnGmxAmount > 0) {
                GMX_IRewardTracker(feeGmxTracker).stakeForAccount(_account, _account, bnGmx, bnGmxAmount);
            }

            uint256 stakedBnGmx = GMX_IRewardTracker(feeGmxTracker).depositBalances(_account, bnGmx);
            if (stakedBnGmx > 0) {
                uint256 reductionAmount = stakedBnGmx.mul(_amount).div(balance);
                GMX_IRewardTracker(feeGmxTracker).unstakeForAccount(_account, bnGmx, reductionAmount, _account);
                GMX_IMintable(bnGmx).burn(_account, reductionAmount);
            }
        }

        emit UnstakeGmx(_account, _token, _amount);
    }
}
