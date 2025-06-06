// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20Metadata as ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeTransferLib} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IStaking} from "../interfaces/IStaking.sol";

import {OrigamiMath} from "contracts/libraries/OrigamiMath.sol";

import {Kernel, Policy, Keycode, Permissions, toKeycode} from "../../Kernel.sol";
import {MINTRv1} from "../../modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "../../modules/ROLES/OlympusRoles.sol";
import {PolicyAdmin} from "../utils/PolicyAdmin.sol";
import {ADMIN_ROLE} from "../utils/RoleDefinitions.sol";
import {IDLGTEv1} from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";
import {DLGTEv1} from "../../modules/DLGTE/DLGTE.v1.sol";

import {IMonoCooler} from "../interfaces/cooler/IMonoCooler.sol";
import {ICoolerLtvOracle} from "contracts/interfaces/external/olympus/ICoolerLtvOracle.sol";
import {ICoolerTreasuryBorrower} from "../interfaces/cooler/ICoolerTreasuryBorrower.sol";
import {SafeCast} from "contracts/libraries/SafeCast.sol";
import {CompoundedInterest} from "contracts/libraries/CompoundedInterest.sol";

library FixedPointMathLib {
    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return OrigamiMath.mulDiv(x, y, 1e18, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function divWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return OrigamiMath.mulDiv(x, 1e18, y, OrigamiMath.Rounding.ROUND_UP);
    }

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        return OrigamiMath.mulDiv(x, y, denominator, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        return OrigamiMath.mulDiv(x, y, denominator, OrigamiMath.Rounding.ROUND_UP);
    }
}
/**
 * @title Mono Cooler
 * @notice A borrow/lend market where users can deposit their gOHM as collateral and then
 * borrow a stablecoin debt token up to a certain LTV
 *  - The debt token may change over time - eg DAI to USDS (or USDC), determined by the
 *    `CoolerTreasuryBorrower`
 *  - The collateral and debt amounts tracked on this contract are always reported in wad,
 *    ie 18 decimal places
 *  - gOHM collateral can be delegated to accounts for voting, via the DLGTE module
 *  - Positions can be liquidated if the LTV breaches the 'liquidation LTV' as determined by the
 *    `LTV Oracle`
 *  - Users may set an authorization for one other address to act on its behalf.
 */
contract MonoCooler is IMonoCooler, Policy, PolicyAdmin {
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;
    using CompoundedInterest for uint256;
    using SafeTransferLib for ERC20;

    //============================================================================================//
    //                                         IMMUTABLES                                         //
    //============================================================================================//

    /// @dev The collateral token, eg gOHM
    ERC20 private immutable _COLLATERAL_TOKEN;

    /// @dev The OHM token
    ERC20 private immutable _OHM;

    /// @dev The OHM staking contract
    IStaking private immutable _STAKING;

    /// @dev The minimum debt a user needs to maintain
    uint256 private immutable _MIN_DEBT_REQUIRED;

    /// @inheritdoc IMonoCooler
    bytes32 public immutable override DOMAIN_SEPARATOR;

    //============================================================================================//
    //                                          MODULES                                           //
    //============================================================================================//

    MINTRv1 public MINTR; // Olympus V3 Minter Module
    DLGTEv1 public DLGTE; // Olympus V3 Delegation Module

    //============================================================================================//
    //                                         MUTABLES                                           //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    uint128 public override totalCollateral;

    /// @inheritdoc IMonoCooler
    uint128 public override totalDebt;

    /// @inheritdoc IMonoCooler
    uint256 public override interestAccumulatorRay;

    /// @inheritdoc IMonoCooler
    uint96 public override interestRateWad;

    /// @inheritdoc IMonoCooler
    ICoolerLtvOracle public override ltvOracle;

    /// @inheritdoc IMonoCooler
    bool public override liquidationsPaused;

    /// @inheritdoc IMonoCooler
    bool public override borrowsPaused;

    /// @inheritdoc IMonoCooler
    uint40 public override interestAccumulatorUpdatedAt;

    /// @inheritdoc IMonoCooler
    ICoolerTreasuryBorrower public override treasuryBorrower;

    /// @dev A per account store, tracking collateral/debt as of their latest checkpoint.
    mapping(address /* account */ => AccountState) private allAccountState;

    /// @inheritdoc IMonoCooler
    mapping(address /* account */ => mapping(address /* authorized */ => uint96 /* authorizationDeadline */))
        public
        override authorizations;

    /// @inheritdoc IMonoCooler
    mapping(address /* account */ => uint256) public override authorizationNonces;

    //============================================================================================//
    //                                         CONSTANTS                                          //
    //============================================================================================//

    /// @notice Extra precision scalar
    uint256 private constant _RAY = 1e27;

    /// @dev The EIP-712 typeHash for EIP712Domain.
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typeHash for Authorization.
    bytes32 private constant _AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint96 authorizationDeadline,uint256 nonce,uint256 signatureDeadline)"
        );

    /// @dev expected decimals for the `_COLLATERAL_TOKEN` and `treasuryBorrower`
    uint8 private constant _EXPECTED_DECIMALS = 18;

    /// @dev Cannot set an interest rate higher than 10%
    uint96 private constant MAX_INTEREST_RATE = 0.1e18;

    //============================================================================================//
    //                                      INITIALIZATION                                        //
    //============================================================================================//

    constructor(
        address ohm_,
        address gohm_,
        address staking_,
        address kernel_,
        address ltvOracle_,
        uint96 interestRateWad_,
        uint256 minDebtRequired_
    ) Policy(Kernel(kernel_)) {
        _COLLATERAL_TOKEN = ERC20(gohm_);

        // Only handle 18dp collateral
        if (_COLLATERAL_TOKEN.decimals() != _EXPECTED_DECIMALS) revert InvalidParam();

        _OHM = ERC20(ohm_);
        _STAKING = IStaking(staking_);
        _MIN_DEBT_REQUIRED = minDebtRequired_;

        ltvOracle = ICoolerLtvOracle(ltvOracle_);
        (uint96 newOLTV, uint96 newLLTV) = ltvOracle.currentLtvs();
        if (newOLTV > newLLTV) revert InvalidParam();

        interestRateWad = interestRateWad_;
        interestAccumulatorUpdatedAt = uint40(block.timestamp);
        interestAccumulatorRay = _RAY;

        DOMAIN_SEPARATOR = keccak256(abi.encode(_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("DLGTE");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        DLGTEv1 newDLGTE = DLGTEv1(getModuleAddress(dependencies[0]));
        MINTRv1 newMINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));

        (uint8 DLGTE_MAJOR, ) = newDLGTE.VERSION();
        (uint8 MINTR_MAJOR, ) = newMINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1]);
        if (DLGTE_MAJOR != 1 || MINTR_MAJOR != 1 || ROLES_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // If MINTR has changed, then update approval to burn OHM from the old
        address oldAddress = address(MINTR);
        if (address(newMINTR) != oldAddress) {
            if (oldAddress != address(0)) _OHM.approve(oldAddress, 0);

            _OHM.approve(address(newMINTR), type(uint256).max);
            MINTR = newMINTR;
        }

        // If DLGTE has changed, then update approval to pull gOHM for delegation
        oldAddress = address(DLGTE);
        if (address(newDLGTE) != oldAddress) {
            if (oldAddress != address(0)) _COLLATERAL_TOKEN.approve(address(oldAddress), 0);

            _COLLATERAL_TOKEN.approve(address(newDLGTE), type(uint256).max);
            DLGTE = newDLGTE;
        }
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode DLGTE_KEYCODE = toKeycode("DLGTE");

        requests = new Permissions[](6);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[1] = Permissions(DLGTE_KEYCODE, DLGTE.depositUndelegatedGohm.selector);
        requests[2] = Permissions(DLGTE_KEYCODE, DLGTE.withdrawUndelegatedGohm.selector);
        requests[3] = Permissions(DLGTE_KEYCODE, DLGTE.applyDelegations.selector);
        requests[4] = Permissions(DLGTE_KEYCODE, DLGTE.setMaxDelegateAddresses.selector);
        requests[5] = Permissions(DLGTE_KEYCODE, DLGTE.rescindDelegations.selector);
    }

    //============================================================================================//
    //                                     AUTHORIZATION                                          //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function setAuthorization(address authorized, uint96 authorizationDeadline) external override {
        emit AuthorizationSet(msg.sender, msg.sender, authorized, authorizationDeadline);
        authorizations[msg.sender][authorized] = authorizationDeadline;
    }

    /// @inheritdoc IMonoCooler
    function setAuthorizationWithSig(
        Authorization memory authorization,
        Signature calldata signature
    ) external override {
        /// Do not check whether authorization is already set because the nonce increment is a desired side effect.
        if (block.timestamp > authorization.signatureDeadline)
            revert ExpiredSignature(authorization.signatureDeadline);
        if (authorization.nonce != authorizationNonces[authorization.account]++)
            revert InvalidNonce(authorization.nonce);

        bytes32 structHash = keccak256(abi.encode(_AUTHORIZATION_TYPEHASH, authorization));
        address signer = ECDSA.recover(
            ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash),
            signature.v,
            signature.r,
            signature.s
        );
        if (signer != authorization.account) revert InvalidSigner(signer, authorization.account);

        emit AuthorizationSet(
            msg.sender,
            authorization.account,
            authorization.authorized,
            authorization.authorizationDeadline
        );
        authorizations[authorization.account][authorization.authorized] = authorization
            .authorizationDeadline;
    }

    /// @inheritdoc IMonoCooler
    function isSenderAuthorized(
        address sender,
        address onBehalfOf
    ) public view override returns (bool) {
        return sender == onBehalfOf || block.timestamp <= authorizations[onBehalfOf][sender];
    }

    function _requireSenderAuthorized(address sender, address onBehalfOf) internal view {
        if (!isSenderAuthorized(sender, onBehalfOf)) revert UnauthorizedOnBehalfOf();
    }

    //============================================================================================//
    //                                       COLLATERAL                                           //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function addCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override {
        _requireAmountNonZero(collateralAmount);
        _requireAddressNonZero(onBehalfOf);

        // Add collateral on behalf of another account
        AccountState storage aState = allAccountState[onBehalfOf];
        _COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), collateralAmount);

        aState.collateral += collateralAmount;
        totalCollateral += collateralAmount;

        // Deposit the gOHM into DLGTE (undelegated)
        DLGTE.depositUndelegatedGohm(onBehalfOf, collateralAmount);

        // Apply any delegation requests on the undelegated gOHM
        if (delegationRequests.length > 0) {
            // While adding collateral on another user's behalf is ok,
            // delegating on behalf of someone else is not allowed unless authorized
            _requireSenderAuthorized(msg.sender, onBehalfOf);

            // Not allowed to undelegate, and not allowed to delegate more than this collateral amount
            (uint256 totalDelegated, uint256 totalUndelegated, ) = DLGTE.applyDelegations(
                onBehalfOf,
                delegationRequests
            );
            if (totalUndelegated > 0 || totalDelegated > collateralAmount) {
                revert IDLGTEv1.DLGTE_InvalidDelegationRequests();
            }
        }

        // NB: No need to check if the position is healthy when adding collateral as this
        // only decreases the LTV.
        emit CollateralAdded(msg.sender, onBehalfOf, collateralAmount);
    }

    /// @inheritdoc IMonoCooler
    function withdrawCollateral(
        uint128 collateralAmount,
        address onBehalfOf,
        address recipient,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests
    ) external override returns (uint128 collateralWithdrawn) {
        _requireAmountNonZero(collateralAmount);
        _requireAddressNonZero(recipient);
        _requireSenderAuthorized(msg.sender, onBehalfOf);

        // No need to sync global debt state when withdrawing collateral
        GlobalStateCache memory gStateCache = _globalStateRO();
        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 _accountCollateral = aState.collateral;

        if (delegationRequests.length > 0) {
            // Apply the delegation requests in order to pull the required collateral back into this contract.
            // Not allowed to delegate, and not allowed to undelegate more than this collateral amount
            (uint256 totalDelegated, uint256 totalUndelegated, ) = DLGTE.applyDelegations(
                onBehalfOf,
                delegationRequests
            );
            if (totalDelegated > 0 || totalUndelegated > collateralAmount) {
                revert IDLGTEv1.DLGTE_InvalidDelegationRequests();
            }
        }

        uint128 currentDebt = _currentAccountDebt(
            aState.debtCheckpoint,
            aState.interestAccumulatorRay,
            gStateCache.interestAccumulatorRay
        );

        if (collateralAmount == type(uint128).max) {
            uint128 minRequiredCollateral = _minCollateral(
                currentDebt,
                gStateCache.maxOriginationLtv
            );
            if (_accountCollateral > minRequiredCollateral) {
                unchecked {
                    collateralWithdrawn = _accountCollateral - minRequiredCollateral;
                }
            } else {
                // Already at/above the origination LTV
                revert ExceededMaxOriginationLtv(
                    _calculateCurrentLtv(currentDebt, _accountCollateral),
                    gStateCache.maxOriginationLtv
                );
            }
            _accountCollateral = minRequiredCollateral;
        } else {
            collateralWithdrawn = collateralAmount;
            if (_accountCollateral < collateralWithdrawn) revert ExceededCollateralBalance();
            unchecked {
                _accountCollateral -= collateralWithdrawn;
            }
        }

        DLGTE.withdrawUndelegatedGohm(onBehalfOf, collateralWithdrawn, 0);

        // Update the collateral balance, and then verify that it doesn't make the debt unsafe.
        aState.collateral = _accountCollateral;
        totalCollateral -= collateralWithdrawn;

        // Calculate the new LTV and verify it's less than or equal to the maxOriginationLtv
        if (currentDebt > 0) {
            uint128 newLtv = _calculateCurrentLtv(currentDebt, _accountCollateral);
            _validateOriginationLtv(newLtv, gStateCache.maxOriginationLtv);
        }

        // Finally transfer the collateral to the recipient
        emit CollateralWithdrawn(msg.sender, onBehalfOf, recipient, collateralWithdrawn);
        _COLLATERAL_TOKEN.safeTransfer(recipient, collateralWithdrawn);
    }

    //============================================================================================//
    //                                       BORROW/REPAY                                         //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function borrow(
        uint128 borrowAmount,
        address onBehalfOf,
        address recipient
    ) external override returns (uint128 amountBorrowed) {
        if (borrowsPaused) revert Paused();
        _requireAmountNonZero(borrowAmount);
        _requireAddressNonZero(recipient);
        _requireSenderAuthorized(msg.sender, onBehalfOf);

        // Sync global debt state when borrowing
        GlobalStateCache memory gStateCache = _globalStateRW();
        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 _accountCollateral = aState.collateral;
        uint128 _accountDebtCheckpoint = aState.debtCheckpoint;

        uint128 currentDebt = _currentAccountDebt(
            _accountDebtCheckpoint,
            aState.interestAccumulatorRay,
            gStateCache.interestAccumulatorRay
        );

        // Apply the new borrow. If type(uint128).max was specified
        // then borrow up to the maxOriginationLtv
        if (borrowAmount == type(uint128).max) {
            uint128 accountTotalDebt = _maxDebt(_accountCollateral, gStateCache.maxOriginationLtv);
            if (accountTotalDebt > currentDebt) {
                unchecked {
                    amountBorrowed = accountTotalDebt - currentDebt;
                }
            } else {
                // Already at/above the origination LTV
                revert ExceededMaxOriginationLtv(
                    _calculateCurrentLtv(currentDebt, _accountCollateral),
                    gStateCache.maxOriginationLtv
                );
            }
            _accountDebtCheckpoint = accountTotalDebt;
        } else {
            amountBorrowed = borrowAmount;
            _accountDebtCheckpoint = currentDebt + amountBorrowed;
        }

        if (_accountDebtCheckpoint < _MIN_DEBT_REQUIRED)
            revert MinDebtNotMet(_MIN_DEBT_REQUIRED, _accountDebtCheckpoint);

        // Update the state
        aState.debtCheckpoint = _accountDebtCheckpoint;
        aState.interestAccumulatorRay = gStateCache.interestAccumulatorRay;
        totalDebt = gStateCache.totalDebt = gStateCache.totalDebt + amountBorrowed;

        // Calculate the new LTV and verify it's less than or equal to the maxOriginationLtv
        {
            uint128 newLtv = _calculateCurrentLtv(_accountDebtCheckpoint, _accountCollateral);
            _validateOriginationLtv(newLtv, gStateCache.maxOriginationLtv);
        }

        // Finally, borrow the funds from the Treasury and send the tokens to the recipient.
        emit Borrow(msg.sender, onBehalfOf, recipient, amountBorrowed);
        treasuryBorrower.borrow(amountBorrowed, recipient);
    }

    /// @inheritdoc IMonoCooler
    function repay(
        uint128 repayAmount,
        address onBehalfOf
    ) external override returns (uint128 amountRepaid) {
        _requireAmountNonZero(repayAmount);
        _requireAddressNonZero(onBehalfOf);

        // Sync global debt state when repaying
        GlobalStateCache memory gStateCache = _globalStateRW();
        AccountState storage aState = allAccountState[onBehalfOf];
        uint128 _accountDebtCheckpoint = aState.debtCheckpoint;

        // Update the account's latest debt
        // round up for repay balance
        uint128 latestDebt = _currentAccountDebt(
            _accountDebtCheckpoint,
            aState.interestAccumulatorRay,
            gStateCache.interestAccumulatorRay
        );
        if (latestDebt == 0) revert ExpectedNonZero();

        // Cap the amount to be repaid to the current debt as of this block
        if (repayAmount < latestDebt) {
            amountRepaid = repayAmount;

            // Ensure the minimum debt amounts are still maintained
            unchecked {
                aState.debtCheckpoint = _accountDebtCheckpoint = latestDebt - amountRepaid;
            }
            if (_accountDebtCheckpoint < _MIN_DEBT_REQUIRED) {
                revert MinDebtNotMet(_MIN_DEBT_REQUIRED, _accountDebtCheckpoint);
            }
        } else {
            amountRepaid = latestDebt;
            aState.debtCheckpoint = 0;
        }

        aState.interestAccumulatorRay = gStateCache.interestAccumulatorRay;
        _reduceTotalDebt(gStateCache, amountRepaid);

        // NB: No need to check if the position is healthy after a repayment as this
        // only decreases the LTV.
        emit Repay(msg.sender, onBehalfOf, amountRepaid);

        // Convert the `amountRepaid` (in wad) into the actual debt token precision
        // and pull from the caller and into the Treasury Borrower for repayment to Treasury
        (IERC20 dToken, uint256 dTokenAmount) = treasuryBorrower.convertToDebtTokenAmount(
            amountRepaid
        );
        ERC20(address(dToken)).safeTransferFrom(
            msg.sender,
            address(treasuryBorrower),
            dTokenAmount
        );
        treasuryBorrower.repay();
    }

    //============================================================================================//
    //                                        DELEGATION                                          //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function applyDelegations(
        IDLGTEv1.DelegationRequest[] calldata delegationRequests,
        address onBehalfOf
    )
        external
        override
        returns (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance)
    {
        _requireSenderAuthorized(msg.sender, onBehalfOf);
        (totalDelegated, totalUndelegated, undelegatedBalance) = DLGTE.applyDelegations(
            onBehalfOf,
            delegationRequests
        );
    }

    /// @inheritdoc IMonoCooler
    function applyUnhealthyDelegations(
        address account,
        uint256 autoRescindMaxNumDelegates
    ) external override returns (uint256 totalUndelegated, uint256 undelegatedBalance) {
        if (liquidationsPaused) revert Paused();
        GlobalStateCache memory gState = _globalStateRW();
        LiquidationStatus memory status = _computeLiquidity(allAccountState[account], gState);
        if (!status.exceededLiquidationLtv) revert CannotLiquidate();

        return DLGTE.rescindDelegations(account, status.collateral, autoRescindMaxNumDelegates);
    }

    //============================================================================================//
    //                                       LIQUIDATIONS                                         //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function batchLiquidate(
        address[] calldata accounts
    )
        external
        override
        returns (
            uint128 totalCollateralClaimed,
            uint128 totalDebtWiped,
            uint128 totalLiquidationIncentive
        )
    {
        if (liquidationsPaused) revert Paused();

        LiquidationStatus memory status;
        GlobalStateCache memory gState = _globalStateRW();
        address account;
        uint256 numAccounts = accounts.length;
        for (uint256 i; i < numAccounts; ++i) {
            account = accounts[i];
            status = _computeLiquidity(allAccountState[account], gState);

            // Skip if this account is still under the maxLTV
            if (status.exceededLiquidationLtv) {
                emit Liquidated(
                    msg.sender,
                    account,
                    status.collateral,
                    status.currentDebt,
                    status.currentIncentive
                );

                // Withdraw the undelegated gOHM, auto-rescinding delegations if required
                DLGTE.withdrawUndelegatedGohm(account, status.collateral, type(uint256).max);

                totalCollateralClaimed += status.collateral;
                totalDebtWiped += status.currentDebt;
                totalLiquidationIncentive += status.currentIncentive;

                // Clear the account data
                delete allAccountState[account];
            }
        }

        // burn the gOHM collateral and update the total state.
        if (totalCollateralClaimed > 0) {
            // Unstake and burn gOHM holdings.
            uint128 gOhmToBurn = totalCollateralClaimed - totalLiquidationIncentive;
            if (gOhmToBurn > 0) {
                uint256 ohmAmount = _STAKING.unstake(address(this), gOhmToBurn, false, false);
                if (ohmAmount > 0) {
                    MINTR.burnOhm(address(this), ohmAmount);
                }
            }

            totalCollateral -= totalCollateralClaimed;
        }

        // Remove debt from the totals and from TRSRY
        if (totalDebtWiped > 0) {
            _reduceTotalDebt(gState, totalDebtWiped);
            treasuryBorrower.writeOffDebt(totalDebtWiped);
        }

        // The liquidator receives the total incentives across all accounts
        if (totalLiquidationIncentive > 0) {
            _COLLATERAL_TOKEN.safeTransfer(msg.sender, totalLiquidationIncentive);
        }
    }

    //============================================================================================//
    //                                           ADMIN                                            //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function setLtvOracle(address newOracle) external override onlyAdminRole {
        (uint96 newOLTV, uint96 newLLTV) = ICoolerLtvOracle(newOracle).currentLtvs();
        if (newOLTV > newLLTV) revert InvalidParam();

        (uint96 existingOLTV, uint96 existingLLTV) = ICoolerLtvOracle(ltvOracle).currentLtvs();
        if (newOLTV < existingOLTV || newLLTV < existingLLTV) revert InvalidParam();

        emit LtvOracleSet(newOracle);
        ltvOracle = ICoolerLtvOracle(newOracle);
    }

    /// @inheritdoc IMonoCooler
    function setTreasuryBorrower(address newTreasuryBorrower) external override {
        // Permisionless if `treasuryBorrower` is uninitialized
        if (address(treasuryBorrower) != address(0) && !_isAdmin(msg.sender))
            revert ROLESv1.ROLES_RequireRole(ADMIN_ROLE);

        emit TreasuryBorrowerSet(newTreasuryBorrower);
        treasuryBorrower = ICoolerTreasuryBorrower(newTreasuryBorrower);
        if (treasuryBorrower.DECIMALS() != _EXPECTED_DECIMALS) revert InvalidParam();
    }

    /// @inheritdoc IMonoCooler
    function setLiquidationsPaused(bool isPaused) external override onlyEmergencyOrAdminRole {
        liquidationsPaused = isPaused;
        emit LiquidationsPausedSet(isPaused);
    }

    /// @inheritdoc IMonoCooler
    function setBorrowPaused(bool isPaused) external override onlyEmergencyOrAdminRole {
        emit BorrowPausedSet(isPaused);
        borrowsPaused = isPaused;
    }

    /// @inheritdoc IMonoCooler
    function setInterestRateWad(uint96 newInterestRate) external override onlyAdminRole {
        if (newInterestRate > MAX_INTEREST_RATE) revert InvalidParam();

        // Force an update of state on the old rate first.
        _globalStateRW();

        emit InterestRateSet(newInterestRate);
        interestRateWad = newInterestRate;
    }

    /// @inheritdoc IMonoCooler
    function setMaxDelegateAddresses(
        address account,
        uint32 maxDelegateAddresses
    ) external override onlyAdminRole {
        DLGTE.setMaxDelegateAddresses(account, maxDelegateAddresses);
    }

    /// @inheritdoc IMonoCooler
    function checkpointDebt()
        external
        override
        returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/)
    {
        GlobalStateCache memory gState = _globalStateRW();
        return (gState.totalDebt, gState.interestAccumulatorRay);
    }

    //============================================================================================//
    //                                      VIEW FUNCTIONS                                        //
    //============================================================================================//

    /// @inheritdoc IMonoCooler
    function collateralToken() external view override returns (IERC20) {
        return IERC20(address(_COLLATERAL_TOKEN));
    }

    /// @inheritdoc IMonoCooler
    function ohm() external view override returns (IERC20) {
        return IERC20(address(_OHM));
    }

    /// @inheritdoc IMonoCooler
    function debtToken() external view override returns (IERC20) {
        return treasuryBorrower.debtToken();
    }

    /// @inheritdoc IMonoCooler
    function staking() external view override returns (IStaking) {
        return _STAKING;
    }

    /// @inheritdoc IMonoCooler
    function minDebtRequired() external view override returns (uint256) {
        return _MIN_DEBT_REQUIRED;
    }

    /// @inheritdoc IMonoCooler
    function loanToValues()
        external
        view
        override
        returns (uint96 maxOriginationLtv, uint96 liquidationLtv)
    {
        return ltvOracle.currentLtvs();
    }

    /// @inheritdoc IMonoCooler
    function debtDeltaForMaxOriginationLtv(
        address account,
        int128 collateralDelta
    ) external view override returns (int128 debtDelta) {
        AccountState storage aState = allAccountState[account];
        GlobalStateCache memory gStateCache = _globalStateRO();

        int128 newCollateral = collateralDelta + int128(aState.collateral);
        if (newCollateral < 0) revert InvalidCollateralDelta();

        uint128 maxDebt = _maxDebt(uint128(newCollateral), gStateCache.maxOriginationLtv);
        uint128 currentDebt = _currentAccountDebt(
            aState.debtCheckpoint,
            aState.interestAccumulatorRay,
            gStateCache.interestAccumulatorRay
        );
        debtDelta = int128(maxDebt) - int128(currentDebt);
    }

    /// @inheritdoc IMonoCooler
    function accountPosition(
        address account
    ) external view override returns (AccountPosition memory position) {
        AccountState memory aStateCache = allAccountState[account];
        GlobalStateCache memory gStateCache = _globalStateRO();
        LiquidationStatus memory status = _computeLiquidity(aStateCache, gStateCache);

        position.collateral = aStateCache.collateral;
        position.currentDebt = status.currentDebt;
        position.currentLtv = status.currentLtv;
        position.maxOriginationDebtAmount = _maxDebt(
            aStateCache.collateral,
            gStateCache.maxOriginationLtv
        );

        // liquidationLtv [USDS/gOHM] * collateral [gOHM]
        // Round down to get the conservative max debt allowed
        position.liquidationDebtAmount = uint256(gStateCache.liquidationLtv).mulWadDown(
            position.collateral
        );

        // healthFactor = liquidationLtv [USDS/gOHM] * collateral [gOHM] / debt [USDS]
        position.healthFactor = position.currentDebt == 0
            ? type(uint256).max
            : uint256(gStateCache.liquidationLtv).mulDivDown(
                position.collateral,
                position.currentDebt
            );

        (
            ,
            /*totalGOhm*/ position.totalDelegated,
            position.numDelegateAddresses,
            position.maxDelegateAddresses
        ) = DLGTE.accountDelegationSummary(account);
    }

    /// @inheritdoc IMonoCooler
    function computeLiquidity(
        address[] calldata accounts
    ) external view override returns (LiquidationStatus[] memory status) {
        uint256 numAccounts = accounts.length;
        status = new LiquidationStatus[](numAccounts);
        GlobalStateCache memory gStateCache = _globalStateRO();
        for (uint256 i; i < numAccounts; ++i) {
            status[i] = _computeLiquidity(allAccountState[accounts[i]], gStateCache);
        }
    }

    /// @inheritdoc IMonoCooler
    function accountDelegationsList(
        address account,
        uint256 startIndex,
        uint256 maxItems
    ) external view override returns (IDLGTEv1.AccountDelegation[] memory delegations) {
        return DLGTE.accountDelegationsList(account, startIndex, maxItems);
    }

    /// @inheritdoc IMonoCooler
    function accountState(address account) external view override returns (AccountState memory) {
        return allAccountState[account];
    }

    /// @inheritdoc IMonoCooler
    function accountCollateral(address account) external view override returns (uint128) {
        return allAccountState[account].collateral;
    }

    /// @inheritdoc IMonoCooler
    function accountDebt(address account) external view override returns (uint128) {
        AccountState storage aState = allAccountState[account];
        GlobalStateCache memory gStateCache = _globalStateRO();
        return
            _currentAccountDebt(
                aState.debtCheckpoint,
                aState.interestAccumulatorRay,
                gStateCache.interestAccumulatorRay
            );
    }

    /// @inheritdoc IMonoCooler
    function globalState()
        external
        view
        override
        returns (uint128 /*totalDebt*/, uint256 /*interestAccumulatorRay*/)
    {
        GlobalStateCache memory gStateCache = _globalStateRO();
        return (gStateCache.totalDebt, gStateCache.interestAccumulatorRay);
    }

    //============================================================================================//
    //                                    INTERNAL STATE MGMT                                     //
    //============================================================================================//

    struct GlobalStateCache {
        /**
         * @notice The total amount that has already been borrowed by all accounts.
         * This increases as interest accrues or new borrows.
         * Decreases on repays or liquidations.
         */
        uint128 totalDebt;
        /**
         * @notice Internal tracking of the accumulated interest as an index starting from 1.0e27
         * When this accumulator is compunded by the interest rate, the total debt can be calculated as
         * `updatedTotalDebt = prevTotalDebt * latestInterestAccumulator / prevInterestAccumulator
         */
        uint256 interestAccumulatorRay;
        /**
         * @notice The current Liquidation LTV, served from the `ltvOracle`
         */
        uint96 liquidationLtv;
        /**
         * @notice The current Max Origination LTV, served from the `ltvOracle`
         */
        uint96 maxOriginationLtv;
    }

    /**
     * @dev Setup and refresh the global state
     * Update storage if and only if the timestamp has changed since last updated.
     */
    function _globalStateRW() private returns (GlobalStateCache memory gStateCache) {
        if (_initGlobalStateCache(gStateCache)) {
            // If the cache is dirty (increase in time) then write the
            // updated state
            interestAccumulatorUpdatedAt = uint40(block.timestamp);
            totalDebt = gStateCache.totalDebt;
            interestAccumulatorRay = gStateCache.interestAccumulatorRay;
        }
    }

    /**
     * @dev Setup the GlobalStateCache for a given token
     * read only -- storage isn't updated.
     */
    function _globalStateRO() private view returns (GlobalStateCache memory gStateCache) {
        _initGlobalStateCache(gStateCache);
    }

    /**
     * @dev Initialize the global state cache from storage to this block, for a given token.
     */
    function _initGlobalStateCache(
        GlobalStateCache memory gStateCache
    ) private view returns (bool dirty) {
        // Copies from storage
        gStateCache.interestAccumulatorRay = interestAccumulatorRay;
        gStateCache.totalDebt = totalDebt;
        (gStateCache.maxOriginationLtv, gStateCache.liquidationLtv) = ltvOracle.currentLtvs();

        // Only compound if we're on a new block
        uint40 timeElapsed;
        unchecked {
            timeElapsed = uint40(block.timestamp) - interestAccumulatorUpdatedAt;
        }

        if (timeElapsed > 0) {
            dirty = true;

            // Compound the accumulator
            uint256 newInterestAccumulatorRay = gStateCache
                .interestAccumulatorRay
                .continuouslyCompounded(timeElapsed, interestRateWad);

            // Calculate the latest totalDebt from this
            gStateCache.totalDebt = newInterestAccumulatorRay
                .mulDivUp(gStateCache.totalDebt, gStateCache.interestAccumulatorRay)
                .encodeUInt128();
            gStateCache.interestAccumulatorRay = newInterestAccumulatorRay;
        }
    }

    /**
     * @dev Reduce the total debt in storage by a repayment amount.
     * NB: The sum of all users debt may be slightly more than the recorded total debt
     * because users debt is rounded up for dust.
     * The total debt is floored at 0.
     */
    function _reduceTotalDebt(GlobalStateCache memory gStateCache, uint128 repayAmount) private {
        unchecked {
            totalDebt = gStateCache.totalDebt = repayAmount > gStateCache.totalDebt
                ? 0
                : gStateCache.totalDebt - repayAmount;
        }
    }

    //============================================================================================//
    //                                      INTERNAL HEALTH                                       //
    //============================================================================================//

    /**
     * @dev Calculate the maximum amount which can be borrowed up to the maxOriginationLtv, given
     * a collateral amount
     */
    function _maxDebt(
        uint128 collateral,
        uint256 maxOriginationLtv
    ) private pure returns (uint128) {
        // debt [USDS] = maxOriginationLtv [USDS/gOHM] * collateral [gOHM]
        // Round down to get the conservative max debt allowed
        return maxOriginationLtv.mulWadDown(collateral).encodeUInt128();
    }

    /**
     * @dev Calculate the maximum collateral amount which can be withdrawn up to the maxOriginationLtv, given
     * a current debt amount
     */
    function _minCollateral(
        uint128 debt,
        uint256 maxOriginationLtv
    ) private pure returns (uint128) {
        // collateral [gOHM] = debt [USDS] / maxOriginationLtv [USDS/gOHM]
        // Round up to get the conservative min collateral allowed
        return uint256(debt).divWadUp(maxOriginationLtv).encodeUInt128();
    }

    /**
     * @dev Ensure the LTV isn't higher than the maxOriginationLtv
     */
    function _validateOriginationLtv(uint128 ltv, uint256 maxOriginationLtv) private pure {
        if (ltv > maxOriginationLtv) {
            revert ExceededMaxOriginationLtv(ltv, maxOriginationLtv);
        }
    }

    /**
     * @dev Calculate the current LTV based on the latest debt
     */
    function _calculateCurrentLtv(
        uint128 currentDebt,
        uint128 collateral
    ) private pure returns (uint128) {
        return
            collateral == 0
                ? type(uint128).max // Represent 'undefined' as max uint128
                : uint256(currentDebt).divWadUp(collateral).encodeUInt128();
    }

    /**
     * @dev Generate the LiquidationStatus struct with current details
     * for this account.
     */
    function _computeLiquidity(
        AccountState memory aStateCache,
        GlobalStateCache memory gStateCache
    ) private pure returns (LiquidationStatus memory status) {
        status.collateral = aStateCache.collateral;
        status.currentDebt = _currentAccountDebt(
            aStateCache.debtCheckpoint,
            aStateCache.interestAccumulatorRay,
            gStateCache.interestAccumulatorRay
        );
        status.currentLtv = _calculateCurrentLtv(status.currentDebt, status.collateral);

        status.exceededLiquidationLtv =
            status.collateral > 0 &&
            status.currentLtv > gStateCache.liquidationLtv;
        status.exceededMaxOriginationLtv =
            status.collateral > 0 &&
            status.currentLtv > gStateCache.maxOriginationLtv;

        if (status.exceededLiquidationLtv) {
            // The incentive is calaculated as the excess debt above the LLTV, in collateral terms
            // excessDebt [gOHM] = currentDebt [USDS] / LLTV [USDS/gOHM] - collateral [gOHM]
            uint256 debtInCollateralTerms = uint256(status.currentDebt).divWadUp(
                gStateCache.liquidationLtv
            );
            status.currentIncentive = debtInCollateralTerms.encodeUInt128() - status.collateral;

            // Cap the incentive to the current collateral only (liquidator cannot claim more than the user collateral)
            if (status.currentIncentive > status.collateral)
                status.currentIncentive = status.collateral;
        }
    }

    //============================================================================================//
    //                                       INTERNAL AUX                                         //
    //============================================================================================//

    /**
     * @dev Calculate the latest debt for a given account & token.
     * Derived from the prior debt checkpoint, and the interest accumulator.
     */
    function _currentAccountDebt(
        uint128 accountDebtCheckpoint_,
        uint256 accountInterestAccumulatorRay_,
        uint256 globalInterestAccumulatorRay_
    ) private pure returns (uint128 result) {
        if (accountDebtCheckpoint_ == 0) return 0;

        // Shortcut if no change.
        if (accountInterestAccumulatorRay_ == globalInterestAccumulatorRay_) {
            return accountDebtCheckpoint_;
        }

        uint256 debt = globalInterestAccumulatorRay_.mulDivUp(
            accountDebtCheckpoint_,
            accountInterestAccumulatorRay_
        );
        return debt.encodeUInt128();
    }

    function _requireAmountNonZero(uint256 amount_) internal pure {
        if (amount_ == 0) revert ExpectedNonZero();
    }

    function _requireAddressNonZero(address addr_) internal pure {
        if (addr_ == address(0)) revert InvalidAddress();
    }
}
