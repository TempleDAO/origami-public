pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { ERC4626Test } from "erc4626-tests/ERC4626.test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { MockErc4626VaultWithFees } from "test/foundry/mocks/common/erc4626/MockErc4626VaultWithFees.m.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable decimals_;

    constructor(
        string memory _name, 
        string memory _symbol, 
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        decimals_ = _decimals;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function decimals() public override view returns (uint8) {
        return decimals_;
    }
}

contract ERC4626FuzzTest is ERC4626Test, OrigamiTest {
    MockERC20 private underlying;
    MockErc4626VaultWithFees private vault;

    uint256 public immutable MAX_SUPPLY = 5_000_000e18;
    uint256 public immutable DEPOSIT_FEE = 100;
    uint256 public immutable EXIT_FEE = 200;

    uint256 internal precisionDivisor;

    function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
        vm.startPrank(account);
        deal(address(underlying), account, amount);
        underlying.approve(address(vault), amount);
        vault.seedDeposit(amount, account, maxSupply);
        vm.stopPrank();
    }

    function setUp() public override {
        underlying = new MockERC20("UNDERLYING", "UDLY", 6);
        vault = new MockErc4626VaultWithFees(origamiMultisig, "VAULT", "VLT", underlying, DEPOSIT_FEE, EXIT_FEE);
        seedDeposit(origamiMultisig, 1, MAX_SUPPLY);
        precisionDivisor = (10**(vault.decimals() - underlying.decimals()));
        
        _underlying_ = address(underlying);
        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false; // caps withdraw & redeem to the balance of vault tokens of the user
    }

    // Tweaks to the base function in order
    function setUpVault(Init memory init) public override {
        // setup initial shares and assets for individual users
        for (uint i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));

            // shares
            // @note Updated: bound to the max depositable by the user (would just error otherwise slowing things down)
            uint256 maxDeposit = vault.maxDeposit(user);
            uint256 minDeposit = maxDeposit > 0 ? 1 : 0; // Attempt to deposit at least 1
            uint shares = bound(init.share[i], minDeposit, maxDeposit);

            try underlying.mint(user, shares) {} catch { vm.assume(false); }
            _approve(_underlying_, user, _vault_, shares);

            vm.prank(user); try vault.deposit(shares, user) {} catch { vm.assume(false); }

            // assets
            // @note Updated: bound to 100x the shares such that the share price isn't crazy big            
            uint assets = bound(init.asset[i], 0, shares*100);

            try underlying.mint(user, assets) {} catch { vm.assume(false); }
        }

        // setup initial yield for vault
        // @note Updated: bound to 2x the supply currently in the vault so the share price isn't too imbalanced.
        //   Otherwise there's many cases of minting zero shares (which will revert later) causing 
        //   a lot of unnecessary re-runs.
        uint256 totalAssets = underlying.balanceOf(address(vault));
        init.yield = bound(init.yield, -int256(totalAssets)*11/10, int256(totalAssets)*11/10);
        setUpYield(init);
    }

    // @note Updated: Cap to the max deposit of the vault
    function _max_deposit(address from) internal view override returns (uint) {
        uint256 max = vault.maxDeposit(from);
        uint256 bal = underlying.balanceOf(from);
        return max < bal ? max : bal;
    }

    // @note Updated: Cap to the max mint of the vault
    function _max_mint(address from) internal override returns (uint) {
        uint256 max = vault.maxMint(from);
        uint256 bal = vault_convertToShares(underlying.balanceOf(from));
        return max < bal ? max : bal;
    }
}