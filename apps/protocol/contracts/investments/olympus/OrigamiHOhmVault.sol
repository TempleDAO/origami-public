pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/olympus/OrigamiHOhmVault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { IOrigamiHOhmManager } from "contracts/interfaces/investments/olympus/IOrigamiHOhmManager.sol";
import { IOrigamiHOhmVault } from "contracts/interfaces/investments/olympus/IOrigamiHOhmVault.sol";
import { OrigamiTokenizedBalanceSheetVault } from "contracts/common/OrigamiTokenizedBalanceSheetVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { TBSState } from "contracts/libraries/OrigamiTBSLib.sol";

/**
 * @title Origami lovOHM Tokenized Balance Sheet Vault
 * @notice The logic to add/remove collateral and max borrow/repay from Cooler is delegated to a manager.
 */
contract OrigamiHOhmVault is OrigamiTokenizedBalanceSheetVault, IOrigamiHOhmVault {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiHOhmVault
    IERC20 public immutable override collateralToken;

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
    ) OrigamiTokenizedBalanceSheetVault(initialOwner_, name_, symbol_, tokenPrices_) {
        collateralToken = IERC20(collateralToken_);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function setManager(address newManager) external override onlyElevatedAccess {
        if (newManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));

        if (newManager != address(_manager)) {
            _manager = IOrigamiHOhmManager(newManager);
            emit ManagerSet(newManager);
        }

        // Update the tokens hash in case it's changed
        updateCurrentTokensHash();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function updateCurrentTokensHash()
        public
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
    {
        // Manager may not be set yet (on construction) - skip for now.
        if (address(_manager) == address(0)) return;

        // Update the debtToken in case it's changed.
        IERC20 newDebtToken = _manager.debtToken();
        if (address(newDebtToken) != address(debtToken)) {
            debtToken = newDebtToken;
            emit DebtTokenSet(address(newDebtToken));
        }

        bytes32 newHash = keccak256(abi.encode(assetTokens(), liabilityTokens()));
        if (currentTokensHash != newHash) {
            currentTokensHash = newHash;
            emit CurrentTokensHashSet(newHash);
        }
    }

    /// @inheritdoc IOrigamiHOhmVault
    function delegateVotingPower(address delegate) external override {
        // test for 0 supply
        _manager.updateDelegateAndAmount(msg.sender, balanceOf(msg.sender), totalSupply(), delegate);
    }

    /// @inheritdoc IOrigamiHOhmVault
    function syncDelegation(address account) public override {
        _manager.setDelegationAmount1(account, balanceOf(account), totalSupply());
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
    function burn(uint256 amount)
        external
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
    {
        _burn(msg.sender, amount);

        // Ensure the delegation is synchronized for this caller with the latest gOHM balance and the
        // updated share balance & totalSupply
        _manager.setDelegationAmount1(msg.sender, balanceOf(msg.sender), totalSupply());
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areJoinsPaused()
        public
        view
        virtual
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (bool)
    {
        return _manager.areJoinsPaused();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areExitsPaused()
        public
        view
        virtual
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (bool)
    {
        return _manager.areExitsPaused();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function manager() external view override returns (address) {
        return address(_manager);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function exitFeeBps()
        public
        view
        virtual
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (uint256)
    {
        return _manager.exitFeeBps();
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function assetTokens()
        public
        view
        virtual
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (address[] memory assets)
    {
        assets = new address[](1);
        assets[0] = address(collateralToken);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function liabilityTokens()
        public
        view
        virtual
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (address[] memory liabilities)
    {
        liabilities = new address[](1);
        liabilities[0] = address(debtToken);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function matchToken(address tokenAddress)
        public
        view
        override(IOrigamiTokenizedBalanceSheetVault, OrigamiTokenizedBalanceSheetVault)
        returns (AssetOrLiability kind, uint256 index)
    {
        if (tokenAddress == address(collateralToken)) return (AssetOrLiability.ASSET, 0);
        if (tokenAddress == address(debtToken)) return (AssetOrLiability.LIABILITY, 0);

        // Leave uninitialized as AssetOrLiability.INVALID
    }

    /// @inheritdoc IOrigamiHOhmVault
    function accountDelegationBalances(address account)
        external
        view
        override
        returns (uint256 totalCollateral, address delegateAddress, uint256 delegatedCollateral)
    {
        return _manager.accountDelegationBalances(account, balanceOf(account), totalSupply());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiTokenizedBalanceSheetVault)
        returns (bool)
    {
        return OrigamiTokenizedBalanceSheetVault.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiHOhmVault).interfaceId;
    }

    /// @dev A hook for joins - it must pull assets from caller and send liabilities to receiver,
    /// along with any other interactions required.
    function _joinPreMintHook(
        TBSState memory,
        /*$*/
        address caller,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual override {
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
        TBSState memory,
        /*$*/
        address caller,
        address sharesOwner,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual override {
        uint256 collateralAmount = assets[0];
        uint256 debtAmount = liabilities[0];

        // Transfer liabilities to the manager then exit
        debtToken.safeTransferFrom(caller, address(_manager), debtAmount);

        uint256 ownerSharesPostBurn = balanceOf(sharesOwner) - shares;
        uint256 totalSupplyPostBurn = totalSupply() - shares;
        _manager.exit(collateralAmount, debtAmount, sharesOwner, receiver, ownerSharesPostBurn, totalSupplyPostBurn);
    }

    /// @inheritdoc OrigamiTokenizedBalanceSheetVault
    function _balanceSheet()
        internal
        view
        override
        returns (uint256[] memory totalAssets, uint256[] memory totalLiabilities, bytes memory balanceSheetData)
    {
        totalAssets = new uint256[](1);
        totalAssets[0] = _manager.collateralTokenBalance();
        totalLiabilities = new uint256[](1);
        totalLiabilities[0] = _manager.debtTokenBalance();

        // note: balanceSheetData is not required for hOHM
        balanceSheetData = "";
    }

    /// @dev Use the Openzeppelin ERC20 post hook to update delegations on a transfer.
    ///  - The gOHM delegation for the `from` and `to` account is synchronized using the latest
    ///    gOHM balances and the account's share proportion.
    ///  - If either (or both) of the accounts has not set a delegate then this will be a no-op
    ///    for that account
    ///  - Delegations are already synchronized for join/exit/burn, so only need to handle transfers
    ///  - Transfer to self is ignored (the account can use `syncDelegation()` for that)
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 /* shares */
    )
        internal
        override
    {
        if (from != to && from != address(0) && to != address(0)) {
            // This sync's the latest proportional gOHM balance for each account, even if
            // the share balance remains the same, as the gOHM per share will increase over time.
            _manager.setDelegationAmount2(from, balanceOf(from), to, balanceOf(to), totalSupply());
        }
    }
}
