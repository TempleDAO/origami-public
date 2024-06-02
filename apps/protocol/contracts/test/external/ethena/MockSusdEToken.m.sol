pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

// Removed the OZ ERC-4626 offset for testing purposes
// as it changes the formulas ever so slightly
// Also limits redeem and withdraw to elevated access
contract MockSUsdEToken is ERC4626, OrigamiElevatedAccess {
    using Math for uint256;

    uint96 public interestRate;
    uint256 public checkpointValue;
    uint256 public checkpointTime;

    event Checkpoint(uint256 checkpointValue, uint256 checkpointTime);
    event InterestRateSet(uint96 rate);

    constructor(address _initialOwner, IERC20 _asset) 
        ERC4626(_asset)
        ERC20("Staked USDe", "sUSDe") 
        OrigamiElevatedAccess(_initialOwner)
    {}

    function setInterestRate(uint96 rate) external {
        checkpoint();
        interestRate = rate;
        emit InterestRateSet(rate);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        return calcCheckpoint();
    }

    function redeem(uint256 shares, address receiver, address _owner) public virtual override onlyElevatedAccess returns (uint256) {
        require(shares <= maxRedeem(_owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, _owner, assets, shares);

        return assets;
    }

    function withdraw(uint256 assets, address receiver, address _owner) public virtual override onlyElevatedAccess returns (uint256) {
        require(assets <= maxWithdraw(_owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, _owner, assets, shares);

        return shares;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return _totalAssets == 0
            ? assets
            : assets.mulDiv(totalSupply(), _totalAssets, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        return totalSupply() == 0
            ? shares
            : shares.mulDiv(totalAssets(), totalSupply(), rounding);
    }

    function calcCheckpoint() internal view returns (uint256 newCheckpoint) {
        uint256 timeDelta = block.timestamp - checkpointTime;
        newCheckpoint = checkpointValue;
        if (timeDelta > 0) {
            // Simple interest
            newCheckpoint += Math.mulDiv(
                newCheckpoint * interestRate,
                timeDelta,
                365 days * 1e18
            );
        }
    }

    function checkpoint() internal {
        checkpointValue = calcCheckpoint();
        checkpointTime = block.timestamp;
        emit Checkpoint(checkpointValue, checkpointTime);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        checkpoint();

        ERC4626._deposit(caller, receiver, assets, shares);

        checkpointValue += assets;
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        checkpoint();

        ERC4626._withdraw(caller,
            receiver,
            _owner,
            assets,
            shares);

        checkpointValue -= assets;
    }
}
