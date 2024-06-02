pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol)

import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IFlashLoanReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";
import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title OrigamiAaveV3FlashLoanProvider
 * @notice A permisionless flashloan wrapper over an Aave/Spark flashloan pool
 * @dev The caller needs to implement the IOrigamiFlashLoanReceiver interface to receive the callback
 */ 
contract OrigamiAaveV3FlashLoanProvider is IOrigamiFlashLoanProvider, IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    /**
     * @dev Aave/Spark pool addresses provider, required for IFlashLoanReceiver
     */
    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;

    /**
     * @dev The Aave/Spark pool, required for IFlashLoanReceiver
     * In the very unlikely event that Aave/Spark changes the pool address
     * this contract can easily be redeployed since it's stateless
     */
    IPool public immutable override POOL;

    /**
     * @notice Aave/spark referral code
     * @dev Unused, but if required in future then deploy a new FL provider
     */
    uint16 public constant REFERRAL_CODE = 0;

    constructor(address _aavePoolAddressProvider) {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_aavePoolAddressProvider);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());        
    }

    /**
     * @notice Initiate a flashloan for a single token
     * The caller must implement the `IOrigamiFlashLoanReceiver()` interface
     * and must repay the loaned tokens to this contract within that function call. 
     * The loaned amount is always repaid to Aave/Spark within the same transaction.
     * @dev Upon FL success, Aave/Spark will call the `executeOperation()` callback
     */
    function flashLoan(IERC20 token, uint256 amount, bytes calldata params) external override {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(token);
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = amount;
        uint256[] memory _modes = new uint256[](1);
        // Never opens a borrow position immediately after the FL, always repay it immediately
        _modes[0] = uint256(DataTypes.InterestRateMode.NONE);

        // Encode the msg.sender, which also doubles as the IOrigamiFlashLoanReceiver.
        bytes memory _params = abi.encode(msg.sender, params);

        POOL.flashLoan(
            address(this),
            _tokens,
            _amounts,
            _modes,
            address(this),
            _params,
            REFERRAL_CODE
        );
    }

    /**
    * @notice Callback from Aave/Spark after receiving the flash-borrowed assets
    * @dev After validation, flashLoanCallback() is called on the caller of flashLoan().
    * @param assets The addresses of the flash-borrowed assets
    * @param amounts The amounts of the flash-borrowed assets
    * @param fees The fee of each flash-borrowed asset
    * @param initiator The address of the flashloan initiator
    * @param params The byte-encoded params passed when initiating the flashloan
    */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Can only be called by the Aave/Spark pool, and the FL can only ever be initiated by this contract.
        if (msg.sender != address(POOL)) revert CommonEventsAndErrors.InvalidAccess();
        if (initiator != address(this)) revert CommonEventsAndErrors.InvalidAddress(initiator);
        if (assets.length != 1 || amounts.length != 1 || fees.length != 1) revert CommonEventsAndErrors.InvalidParam();

        (IOrigamiFlashLoanReceiver flReceiver, bytes memory _params) = abi.decode(params, (IOrigamiFlashLoanReceiver, bytes));
        IERC20 _asset = IERC20(assets[0]);
        uint256 _flAmount = amounts[0];
        uint256 _flFees = fees[0];

        // Transfer the asset to the Origami FL receiver, and approve the repayment to Aave/Spark in full
        {
            _asset.safeTransfer(address(flReceiver), _flAmount);
            _asset.forceApprove(address(POOL), _flAmount + _flFees);
        }

        // Finally have the receiver handle the callback
        return flReceiver.flashLoanCallback(_asset, _flAmount, _flFees, _params);
    }
}
