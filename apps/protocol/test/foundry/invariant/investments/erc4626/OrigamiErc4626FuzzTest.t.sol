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

    function setUp() public override {
        underlying = new MockERC20("UNDERLYING", "UDLY", 6);
        vault = new MockErc4626VaultWithFees(origamiMultisig, "VAULT", "VLT", underlying, 100, 200, 500e18);
        _underlying_ = address(underlying);

        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = true;
    }

    // NOTE: The following test is relaxed to consider only smaller values (of type uint120),
    // since maxWithdraw() fails with large values (due to overflow).
    function test_maxDeposit(Init memory init) public override {
        init = clamp(init, type(uint248).max);
        super.test_maxWithdraw(init);
    }

    function clamp(Init memory init, uint256 max) internal pure returns (Init memory) {
        for (uint256 i = 0; i < N; i++) {
            init.share[i] = init.share[i] % max;
            init.asset[i] = init.asset[i] % max;
        }
        init.yield = init.yield % int256(max);
        return init;
    }
}