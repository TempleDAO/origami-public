pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// Removed the OZ ERC-4626 offset for testing purposes
// as it changes the formulas ever so slightly
contract MockSUsdsToken is ERC4626 {
    using Math for uint256;

    uint96 public ssr;
    uint256 public checkpointValue;
    uint256 public checkpointTime;

    event Checkpoint(uint256 checkpointValue, uint256 checkpointTime);
    event InterestRateSet(uint96 rate);
    event Referral(uint16 indexed referral, address indexed owner, uint256 assets, uint256 shares);

    constructor(IERC20 _asset) ERC4626(_asset) ERC20("SDAI", "SDAI") {}

    function setInterestRate(uint96 rate) external {
        checkpoint();
        ssr = rate;
        emit InterestRateSet(rate);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        return calcCheckpoint();
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
                newCheckpoint * ssr,
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

    function deposit(uint256 assets, address receiver, uint16 referral) external returns (uint256 shares) {
        shares = deposit(assets, receiver);
        emit Referral(referral, receiver, assets, shares);
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
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        checkpoint();

        ERC4626._withdraw(caller,
            receiver,
            owner,
            assets,
            shares);

        checkpointValue -= assets;
    }
}
