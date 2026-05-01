pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/olympus/OrigamiHOhmVault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { IOrigamiHOhmManager } from "contracts/interfaces/investments/olympus/IOrigamiHOhmManager.sol";
import { IOrigamiHOhmVault } from "contracts/interfaces/investments/olympus/IOrigamiHOhmVault.sol";
import { OrigamiTokenizedBalanceSheetVault } from "contracts/common/OrigamiTokenizedBalanceSheetVault.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami lovOHM Tokenized Balance Sheet Vault
 * @notice The logic to add/remove collateral and max borrow/repay from Cooler is delegated to a manager.
 */
contract OrigamiHOhmVault is
    OrigamiTokenizedBalanceSheetVault,
    IOrigamiHOhmVault
{
    using SafeERC20 for IERC20;
    
    /// @inheritdoc IOrigamiHOhmVault
    IERC20 public immutable override collateralToken;

    /// @inheritdoc IOrigamiHOhmVault
    ITokenPrices public override tokenPrices;

    // @inheritdoc IOrigamiHOhmVault
    IERC20 public override debtToken;

    /// @dev The internal manager
    IOrigamiHOhmManager private _manager;

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        address collateralToken_,
        address tokenPrices_
    )
        OrigamiTokenizedBalanceSheetVault(initialOwner_, name_, symbol_)
    {
        collateralToken = IERC20(collateralToken_);
        tokenPrices = ITokenPrices(tokenPrices_);
    }

    /// @inheritdoc IOrigamiHOhmVault
    function setManager(address newManager) external override onlyElevatedAccess {
        if (newManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));

        if (newManager != address(_manager)) {
            _manager = IOrigamiHOhmManager(newManager);
            emit ManagerSet(newManager);
        }

        // And update the debtToken in case it's changed.
        // This can also be used to refresh the cached debtToken storage value in case it has changed in
        // the upstream cooler and manager, even if the manager itself has not changed.
        IERC20 newDebtToken = _manager.debtToken();
        if (address(newDebtToken) != address(debtToken)) {
            debtToken = newDebtToken;
            emit DebtTokenSet(address(newDebtToken));
        }
    }

    /// @inheritdoc IOrigamiHOhmVault
    function setTokenPrices(address _tokenPrices) external override onlyElevatedAccess {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit TokenPricesSet(_tokenPrices);
        tokenPrices = ITokenPrices(_tokenPrices);
    }

    /// @inheritdoc IOrigamiHOhmVault
    function delegateVotingPower(address delegate) external override {
        // test for 0 supply
        _manager.updateDelegateAndAmount(
            msg.sender,
            balanceOf(msg.sender),
            totalSupply(),
            delegate
        );
    }

    /// @inheritdoc IOrigamiHOhmVault
    function syncDelegation(address account) public override {
        _manager.setDelegationAmount1(
            account,
            balanceOf(account),
            totalSupply()
        );
    }

    /// @inheritdoc IOrigamiHOhmVault
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function burn(uint256 amount) external override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) {
        _burn(msg.sender, amount);

        // Ensure the delegation is synchronized for this caller with the latest gOHM balance and the
        // updated share balance & totalSupply
        _manager.setDelegationAmount1(
            msg.sender,
            balanceOf(msg.sender),
            totalSupply()
        );
    }
    
    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areJoinsPaused() public virtual override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) view returns (
        bool
    ) {
        return _manager.areJoinsPaused();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areExitsPaused() public virtual override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) view returns (
        bool
    ) {
        return _manager.areExitsPaused();
    }

    /// @inheritdoc IOrigamiHOhmVault
    function manager() external override view returns (address) {
        return address(_manager);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function exitFeeBps() public virtual override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) view returns (
        uint256
    ) {
        return _manager.exitFeeBps();
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function assetTokens() public virtual override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) view returns (
        address[] memory assets
    ) {
        assets = new address[](1);
        assets[0] = address(collateralToken);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function liabilityTokens() public virtual override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) view returns (
        address[] memory liabilities
    ) {
        liabilities = new address[](1);
        liabilities[0] = address(debtToken);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function isBalanceSheetToken(address tokenAddress) public virtual override(ITokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault) view returns (
        bool isAsset,
        bool isLiability
    ) {
        if (tokenAddress == address(collateralToken)) return (true, false);
        if (tokenAddress == address(debtToken)) return (false, true);
        return (false, false);
    }

    /// @inheritdoc IOrigamiHOhmVault
    function accountDelegationBalances(address account) external override view returns (
        uint256 totalCollateral,
        address delegateAddress,
        uint256 delegatedCollateral
    ) {
        return _manager.accountDelegationBalances(account, balanceOf(account), totalSupply());
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public virtual override(IERC165, OrigamiTokenizedBalanceSheetVault) pure returns (
        bool
    ) {
        return OrigamiTokenizedBalanceSheetVault.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiHOhmVault).interfaceId;
    }

    /// @dev A hook for joins - it must pull assets from caller and send liabilities to receiver,
    /// along with any other interactions required.
    function _joinPreMintHook(
        address caller,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal override virtual {
        uint256 collateralAmount = assets[0];
        uint256 debtAmount = liabilities[0];

        // Transfer gOHM collateral to the manager then join
        collateralToken.safeTransferFrom(caller, address(_manager), collateralAmount);

        uint256 receiverSharesPostMint = balanceOf(receiver) + shares;
        uint256 totalSupplyPostMint = totalSupply() + shares;
        _manager.join(collateralAmount, debtAmount, receiver, receiverSharesPostMint, totalSupplyPostMint);
    }

    /// @dev A hook for exits - it must send assets to receiver and pull liabilities from caller,
    /// along with any other interactions required.
    function _exitPreBurnHook(
        address caller,
        address sharesOwner,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal override virtual {
        uint256 collateralAmount = assets[0];
        uint256 debtAmount = liabilities[0];

        // Transfer liabilities to the manager then exit
        debtToken.safeTransferFrom(caller, address(_manager), debtAmount);

        uint256 ownerSharesPostBurn = balanceOf(sharesOwner) - shares;
        uint256 totalSupplyPostBurn = totalSupply() - shares;
        _manager.exit(collateralAmount, debtAmount, sharesOwner, receiver, ownerSharesPostBurn, totalSupplyPostBurn);
    }

    /// @dev Return the current token balance of one of the assets or liability tokens in the vault
    /// Should not revert - return zero if tokenAddress is not valid.
    function _tokenBalance(address tokenAddress) internal override view returns (uint256) {
        if (tokenAddress == address(debtToken)) {
            return _manager.debtTokenBalance();
        } else if (tokenAddress == address(collateralToken)) {
            return _manager.collateralTokenBalance();
        }

        return 0;
    }

    /// @dev Use the Openzeppelin ERC20 post hook to update delegations on a transfer.
    ///  - The gOHM delegation for the `from` and `to` account is synchronized using the latest
    ///    gOHM balances and the account's share proportion.
    ///  - If either (or both) of the accounts has not set a delegate then this will be a no-op 
    ///    for that account
    ///  - Delegations are already synchronized for join/exit/burn, so only need to handle transfers
    ///  - Transfer to self is ignored (the account can use `syncDelegation()` for that)
    function _afterTokenTransfer(address from, address to, uint256 /* shares */) internal override {
        if (from != to && from != address(0) && to != address(0)) {
            // This sync's the latest proportional gOHM balance for each account, even if 
            // the share balance remains the same, as the gOHM per share will increase over time.
            _manager.setDelegationAmount2(
                from,
                balanceOf(from),
                to,
                balanceOf(to),
                totalSupply()
            );
        }
    }
}
