pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/OrigamiDebtToken.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { CompoundedInterest } from "contracts/libraries/CompoundedInterest.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";

/* solhint-disable not-rely-on-time */

/**
 * @title Origami Debt Token
 * @notice A rebasing ERC20 representing debt accruing at continuously compounding interest rate.
 * 
 * On a repayment, any accrued interest is repaid. When there is no more outstanding interest,
 * then the principal portion is paid down.
 * 
 * Only approved minters can mint/burn/transfer the debt on behalf of a user.
 */
contract OrigamiDebtToken is IOrigamiDebtToken, OrigamiElevatedAccess {
    using CompoundedInterest for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /**
     * @notice Per address status of debt
     */
    mapping(address account => Debtor debtor) public override debtors;

    /**
     * @notice A set of addresses which are approved to mint/burn
     */
    mapping(address account => bool canMint) public override minters;

    /**
     * @notice The net amount of principal debt minted across all users.
     */
    uint128 public override totalPrincipal;

    /**
     * @notice The latest estimate of the interest (no principal) owed by all debtors as of now.
     * @dev Indicative only. This total is only updated on a per debtor basis when that debtor gets 
     * checkpointed
     * So it is generally slightly out of date as each debtor will accrue interest independently 
     * on different rates.
     */
    uint128 public override estimatedTotalInterest;

    /**
     * @notice The amount of interest which has been repaid to date across all debtors
     */
    uint256 public override repaidTotalInterest;

    /**
     * @dev Returns the decimals places of the token.
     */
    // solhint-disable-next-line const-name-snakecase
    uint8 public constant override decimals = 18;

    /**
     * @dev The max interest rate which can be set for a debtor
     */
    uint96 private constant MAX_INTEREST_RATE = 10e18; // 1_000%

    /**
     * @dev Returns the name of the token.
     */
    string public override name;

    /**
     * @dev Returns the symbol of the token.
     */
    string public override symbol;

    constructor(
        string memory _name,
        string memory _symbol,
        address _initialOwner
    ) OrigamiElevatedAccess(_initialOwner)
    {
        name = _name;
        symbol = _symbol;
    }

    /**
     * @notice Elevated access can add/remove an address which is able to mint/burn/transfer debt
     */
    function setMinter(address account, bool value) external override onlyElevatedAccess {
        minters[account] = value;
        emit MinterSet(account, value);
    }

    /**
     * @notice Update the continuously compounding interest rate for a debtor, from this block onwards.
     */
    function setInterestRate(address _debtor, uint96 _rate) external override {
        if (_rate > MAX_INTEREST_RATE) revert CommonEventsAndErrors.InvalidParam();

        // Can be set by either a debt minter or elevated access
        if (!minters[msg.sender]) {
            if (!isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        }

        // First checkpoint the debtor interest, then update
        Debtor storage debtor = debtors[_debtor];
        _getDebtorPosition(debtor);
        debtor.rate = _rate;
        emit InterestRateSet(_debtor, _rate);
    }

    /**
     * @notice Approved minters can add a new debt position on behalf of a user.
     * @param _debtor The address of the debtor who is issued new debt
     * @param _mintAmount The notional amount of debt tokens to issue.
     */
    function mint(address _debtor, uint256 _mintAmount) external override onlyMinters {
        if (_debtor == address(0)) revert CommonEventsAndErrors.InvalidAddress(_debtor);
        if (_mintAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        emit Transfer(address(0), _debtor, _mintAmount);
        _mintToDebtor(_debtor, _mintAmount.encodeUInt128());
    }

    /**
     * @notice Approved minters can burn debt on behalf of a user.
     * @dev Interest is repaid prior to the principal.
     * @param _debtor The address of the debtor
     * @param _burnAmount The notional amount of debt tokens to repay.
     */
    function burn(
        address _debtor, 
        uint256 _burnAmount
    ) external override onlyMinters {
        if (_debtor == address(0)) revert CommonEventsAndErrors.InvalidAddress(_debtor);
        if (_burnAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        
        _burnFromDebtor(_debtor, _burnAmount.encodeUInt128());
        emit Transfer(_debtor, address(0), _burnAmount);
    }

    /**
     * @notice Approved minters can burn the entire debt on behalf of a user.
     * @param _debtor The address of the debtor
     */
    function burnAll(address _debtor) external override onlyMinters returns (uint256 burnedAmount) {
        if (_debtor == address(0)) revert CommonEventsAndErrors.InvalidAddress(_debtor);

        // First checkpoint the interest of the debtor.
        // Use RO (read only) for the debtor position to delay the updating of 
        // storage to the end since it needs updating anyway.
        Debtor storage debtor = debtors[_debtor];
        DebtorPosition memory _debtorPosition = _getDebtorPositionRO(debtor);

        burnedAmount = _totalBalance(_debtorPosition);
        if (burnedAmount != 0) {
            emit Transfer(_debtor, address(0), burnedAmount);
            _doBurn(debtor, _debtorPosition, burnedAmount.encodeUInt128());
        }
        emit DebtorBalance(_debtor, _debtorPosition.principal, _debtorPosition.interest);
    }

    /**
     * @notice Debt tokens are only transferrable by minters (which doesn't need approvals)
     * Allowance always returns 0
     */
    function allowance(
        address /*owner*/,
        address /*spender*/
    ) external pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Debt tokens are only transferrable by minters (which doesn't need approvals)
     */
    function approve(
        address /*spender*/,
        uint256 /*amount*/
    ) external pure override returns (bool) {
        revert CommonEventsAndErrors.InvalidAccess();
    }

    /**
     * @notice Debt tokens are only transferrable by minters (which doesn't need approvals)
     */
    function transfer(
        address to, 
        uint256 amount
    ) external override onlyMinters returns (bool) {
        _transfer(msg.sender, to, amount.encodeUInt128());
        return true;
    }

    /**
     * @notice Debt tokens are only transferrable by minters (which doesn't need approvals)
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override onlyMinters returns (bool) {
        _transfer(from, to, amount.encodeUInt128());
        return true;
    }

    /**
     * @notice Returns the amount of tokens owed by the debtor as of this block.
     * It includes the principal + interest
     */
    function balanceOf(address _debtor) external override view returns (uint256) {
        return _totalBalance(_getDebtorPositionRO(debtors[_debtor]));
    }

    /**
     * @notice Checkpoint multiple accounts interest (no principal) owed up to this block.
     */
    function checkpointDebtorsInterest(address[] calldata _debtors) external override {
        DebtorPosition memory _debtorPosition;
        address _debtorAddr;
        Debtor storage _debtor;
        uint128 _interestDelta;

        // Use the RO (read-only) version in order to tally the total interestDelta
        // to save multiple sload/sstore of estimatedTotalInterest
        for (uint256 i; i < _debtors.length;) {
            _debtorAddr = _debtors[i];
            if (_debtorAddr == address(0)) revert CommonEventsAndErrors.InvalidAddress(_debtorAddr);
            _debtor = debtors[_debtorAddr];
            _debtorPosition = _getDebtorPositionRO(_debtor);
            _interestDelta = _interestDelta + _debtorPosition.interestDelta;
            _debtor.interestCheckpoint = _debtorPosition.interest;
            _debtor.timeCheckpoint = uint32(block.timestamp);
            emit Checkpoint(_debtorAddr, _debtor.principal, _debtorPosition.interest);

            unchecked {
                ++i;
            }
        }
        estimatedTotalInterest = estimatedTotalInterest + _interestDelta;
    }

    /**
     * @notice The current debt for a given set of users split out by principal and interest
     */
    function currentDebtsOf(address[] calldata _debtors) external override view returns (
        DebtOwed[] memory debtsOwed
    ) {
        debtsOwed = new DebtOwed[](_debtors.length);
        DebtorPosition memory _debtorPosition;
        
        for (uint256 i; i < _debtors.length; ++i) {
            _debtorPosition = _getDebtorPositionRO(debtors[_debtors[i]]);
            debtsOwed[i] = DebtOwed(
                _debtorPosition.principal, 
                _debtorPosition.interest
            );
        }
    }

    /**
      * @notice The current total principal + total (estimate) interest owed by all debtors.
      * @dev Note the principal is up to date as of this block, however the interest portion is likely stale.
      * The `estimatedTotalInterest` is only updated when each debtor checkpoints, so it's going to be out of date.
      * For more up to date current totals, off-chain aggregation of balanceOf() will be required - eg via subgraph.
      */
    function currentTotalDebt() external override view returns (
        DebtOwed memory debtOwed
    ) {
        debtOwed = DebtOwed(
            totalPrincipal,
            estimatedTotalInterest
        );
    }

    /**
      * @notice The current total principal + total base interest, total (estimate) debtor specific risk premium interest owed by all debtors.
      * @dev Note the principal is up to date as of this block, however the interest portion is likely stale.
      * The `estimatedTotalInterest` is only updated when each debtor checkpoints, so it's going to be out of date.
      * For more up to date current totals, off-chain aggregation of balanceOf() will be required - eg via subgraph.
      */
    function totalSupply() external override view returns (uint256) {
        unchecked {
            return uint256(totalPrincipal) + estimatedTotalInterest;
        }
    }

    /**
     * @notice The estimated amount of interest which has been repaid to date 
     * plus the (estimated) outstanding as of now
     */
    function estimatedCumulativeInterest() external override view returns (uint256) {
        return repaidTotalInterest + estimatedTotalInterest;
    }

    /**
     * @notice The total supply as of the latest checkpoint, excluding a given debtor
     */
    function totalSupplyExcluding(address[] calldata debtorList) external override view returns (uint256) {
        Debtor storage _debtor;
        uint256 _excludeSum;
        for (uint256 i; i < debtorList.length;) {
            _debtor = debtors[debtorList[i]];
            unchecked {
                _excludeSum = _excludeSum + _debtor.principal + _debtor.interestCheckpoint;
                ++i;
            }
        }
        
        unchecked {
            uint256 total = uint256(totalPrincipal) + estimatedTotalInterest;
            return total > _excludeSum ? total - _excludeSum : 0;
        }
    }

    /**
     * @notice A view of the derived position data.
     */
    function getDebtorPosition(address debtor) external override view returns (DebtorPosition memory) {
        return _getDebtorPositionRO(debtors[debtor]);
    }

    function _totalBalance(DebtorPosition memory debtorPosition) internal pure returns (uint128) {
        return debtorPosition.principal + debtorPosition.interest;
    }

    function _transfer(
        address fromDebtor,
        address toDebtor,
        uint128 amount
    ) internal {
        if (fromDebtor == address(0)) revert CommonEventsAndErrors.InvalidAddress(fromDebtor);
        if (toDebtor == address(0)) revert CommonEventsAndErrors.InvalidAddress(toDebtor);
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();       

        emit Transfer(fromDebtor, toDebtor, amount);

        // Burn from the debtor.
        _burnFromDebtor(fromDebtor, amount);
        
        // Checkpoint and mint for `to` debtor
        _mintToDebtor(toDebtor, amount);
    }

    function _mintToDebtor(address _debtor, uint128 _amount) internal {
        Debtor storage toDebtor = debtors[_debtor];
        DebtorPosition memory _debtorPosition = _getDebtorPosition(toDebtor);

        totalPrincipal = totalPrincipal + _amount;
        unchecked {
            // If the totalPrincipal doesn't overflow above, then the individual debtorPosition cannot
            toDebtor.principal = _debtorPosition.principal = _debtorPosition.principal + _amount;
        }

        emit DebtorBalance(_debtor, _debtorPosition.principal, _debtorPosition.interest);
    }

    function _burnFromDebtor(
        address _debtor, 
        uint128 _burnAmount
    ) internal {
        // First checkpoint the interest of the debtor.
        // Use RO (read only) for the debtor position to delay the updating of 
        // storage to the end since it needs updating anyway.
        Debtor storage debtor = debtors[_debtor];
        DebtorPosition memory _debtorPosition = _getDebtorPositionRO(debtor);

        // The user can't pay off more debt than they have.
        uint128 _debtorTotal = _totalBalance(_debtorPosition);
        if (_burnAmount > _debtorTotal) {
            revert CommonEventsAndErrors.InsufficientBalance(address(this), _burnAmount, _debtorTotal);
        }

        if (_burnAmount != 0) {
            _doBurn(debtor, _debtorPosition, _burnAmount);
        }

        emit DebtorBalance(_debtor, _debtorPosition.principal, _debtorPosition.interest);
    }

    function _doBurn(
        Debtor storage _debtor, 
        DebtorPosition memory _debtorPosition, 
        uint128 _burnAmount
    ) internal {
        // Calculate what can be repaid out of interest vs principal
        // Interest repaid is the minimum of what risk premium interest is still outstanding, and the requested amount to be burned
        uint128 _interestDebtRepaid = _debtorPosition.interest < _burnAmount 
            ? _debtorPosition.interest 
            : _burnAmount;

        unchecked {
            // Any remaining `_burnAmount` is principal which is repaid.
            _burnAmount = _burnAmount - _interestDebtRepaid;
        }

        // Update the contract state.
        {
            _debtor.principal = _debtorPosition.principal = _debtorPosition.principal - _burnAmount;
            _debtor.interestCheckpoint = _debtorPosition.interest = _debtorPosition.interest - _interestDebtRepaid;
            _debtor.timeCheckpoint = uint32(block.timestamp);

            totalPrincipal = totalPrincipal - _burnAmount;

            // Update the cumulative estimate of total debtor interest owing.
            unchecked {
                // Floor at zero in case the estimate is off
                uint128 totalInterest = estimatedTotalInterest + _debtorPosition.interestDelta;
                estimatedTotalInterest = totalInterest > _interestDebtRepaid ? totalInterest - _interestDebtRepaid : 0;
            }

            repaidTotalInterest = repaidTotalInterest + _interestDebtRepaid;
        }
    }

    /**
     * @dev Initialize the DebtorPosition from storage to this block.
     */
    function _initDebtorPosition( 
        Debtor storage _debtor, 
        DebtorPosition memory _debtorPosition
    ) private view returns (
        bool dirty
    ) {
        _debtorPosition.principal = _debtor.principal;
        _debtorPosition.interest = _debtor.interestCheckpoint;
        _debtorPosition.rate = _debtor.rate;
        uint32 _timeElapsed;
        unchecked {
            _timeElapsed = uint32(block.timestamp) - _debtor.timeCheckpoint;
        }

        if (_timeElapsed != 0) {
            dirty = true;

            if (_debtorPosition.rate != 0) {
                // Calculate the new amount of interest by compounding the total debt
                // and then subtracting just the principal.
                uint256 _debtorTotalDue;
                unchecked {
                    _debtorTotalDue = uint256(_debtorPosition.principal) + _debtorPosition.interest;
                }
                _debtorTotalDue = _debtorTotalDue.continuouslyCompounded(
                    _timeElapsed, 
                    _debtorPosition.rate
                );

                unchecked {
                    uint128 _newInterest = _debtorTotalDue.encodeUInt128() - _debtorPosition.principal;
                    _debtorPosition.interestDelta = _newInterest - _debtorPosition.interest;
                    _debtorPosition.interest = _newInterest;
                }
            }
        }
    }

    /**
     * @dev Setup the DebtorPosition, which is used as a cache of storage data and calcs
     * Update storage if and only if the timestamp has changed since last time.
     */
    function _getDebtorPosition(Debtor storage _debtor) internal returns (
        DebtorPosition memory debtorPosition
    ) {
        if (_initDebtorPosition(_debtor, debtorPosition)) {
            unchecked {
               estimatedTotalInterest = estimatedTotalInterest + debtorPosition.interestDelta;
            }

            _debtor.interestCheckpoint = debtorPosition.interest;
            _debtor.timeCheckpoint = uint32(block.timestamp);
        }
    }

    /**
     * @dev Setup the DebtorPosition without writing state.
     */
    function _getDebtorPositionRO(Debtor storage _debtor) internal view returns (
        DebtorPosition memory debtorPosition
    ) {
        _initDebtorPosition(_debtor, debtorPosition);
    }

    /**
     * @notice Recover any token from the debt token
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    modifier onlyMinters() {
        if (!minters[msg.sender]) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
