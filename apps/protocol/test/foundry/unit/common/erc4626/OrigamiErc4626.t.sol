pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { MockErc4626VaultWithFees } from "test/foundry/mocks/common/erc4626/MockErc4626VaultWithFees.m.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiErc4626 } from "contracts/common/OrigamiErc4626.sol";

contract OrigamiErc4626TestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public asset;
    MockErc4626VaultWithFees public vault;

    uint224 public constant MAX_TOTAL_SUPPLY = 100_000_000e18;
    uint16 public constant DEPOSIT_FEE = 50;
    uint16 public constant WITHDRAWAL_FEE = 200;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 18);
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            DEPOSIT_FEE,
            WITHDRAWAL_FEE,
            MAX_TOTAL_SUPPLY
        );
        vm.warp(100000000);
    }

    function deposit(address user, uint256 amount) internal {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
            DEPOSIT_FEE, 
            expectedShares.inverseSubtractBps(DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP) - expectedShares
        );
        vm.expectEmit(address(vault));
        emit Deposit(user, user, amount, expectedShares);
        uint256 actualShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function mint(address user, uint256 shares) internal {
        uint256 expectedAssets = vault.previewMint(shares);
        deal(address(asset), user, expectedAssets);
        vm.startPrank(user);
        asset.approve(address(vault), expectedAssets);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
            DEPOSIT_FEE, 
            shares.inverseSubtractBps(DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP) - shares
        );
        vm.expectEmit(address(vault));
        emit Deposit(user, user, expectedAssets, shares);
        uint256 actualAssets = vault.mint(shares, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    function withdraw(address user, uint256 assets) internal {
        vm.startPrank(user);
        uint256 expectedShares = vault.previewWithdraw(assets);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            expectedShares - expectedShares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(user, user, user, assets, expectedShares);
        uint256 actualShares = vault.withdraw(assets, user, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function redeem(address user, uint256 shares) internal {
        vm.startPrank(user);
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            shares - shares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(user, user, user, expectedAssets, shares);
        uint256 actualAssets = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    function addToSharePrice(uint256 amount) internal {
        deal(address(asset), address(vault), asset.balanceOf(address(vault)) + amount);
    }
}

contract OrigamiErc4626TestAdmin is OrigamiErc4626TestBase {
    function test_default_nofees() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 18);
        vault = MockErc4626VaultWithFees(address(
            new OrigamiErc4626(
                origamiMultisig, 
                "VAULT",
                "VLT",
                asset
            )
        ));

        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "VAULT");
        assertEq(vault.symbol(), "VLT");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.convertToShares(1e18), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e18), 1e18);
        assertEq(vault.previewMint(1e18), 1e18);
        assertEq(vault.previewWithdraw(1e18), 1e18);
        assertEq(vault.previewRedeem(1e18), 1e18);
        // Dependent on the address, so changes
        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0xd2e843a44a91122d6c30863b00ef4f6cef005ce2bdfbe801e527b67fd3cc222c));
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
    }

    function test_initialization() public {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "VAULT");
        assertEq(vault.symbol(), "VLT");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.convertToShares(1e18), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);

        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxDeposit(alice), 100_502_512.562814070351758794e18);
        assertEq(vault.maxMint(alice), MAX_TOTAL_SUPPLY);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e18), 0.995e18); // 50bps fee
        // 50 bps fee -- need to deposit more assets in order to get 1e18 shares
        assertEq(vault.previewMint(1e18), 1.005025125628140704e18);
        // 200 bps fee -- need to redeem more shares in order to get 1e18 assets
        assertEq(vault.previewWithdraw(1e18), 1.020408163265306123e18);
        assertEq(vault.previewRedeem(1e18), 0.98e18); // 200bps fee

        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0xf07a1e21026e15847c4f454c9eb8f87a35787510bc37aee10796c2c8aa85ff16));
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
    }

    function test_supportsInterface() public {
        assertEq(vault.supportsInterface(type(IERC4626).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(vault.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(vault.supportsInterface(type(IOrigamiInvestment).interfaceId), false);
    }

    function test_recoverToken_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(asset)));
        vault.recoverToken(address(asset), alice, 100e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(vault));
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        vault.recoverToken(alice, alice, 100e18);
    }
}


contract OrigamiErc4626TestDeposit is OrigamiErc4626TestBase {
    function test_deposit_basic() public {
        deposit(alice, 123e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 123e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 123e18);
    }

    function test_deposit_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0,
            MAX_TOTAL_SUPPLY
        );

        {
            address user = alice;
            uint256 amount = 123e18;
            deal(address(asset), user, amount);
            vm.startPrank(user);
            asset.approve(address(vault), amount);
            uint256 expectedShares = vault.previewDeposit(amount);

            vm.expectEmit(address(vault));
            emit Deposit(user, user, amount, expectedShares);
            uint256 actualShares = vault.deposit(amount, user);
            vm.stopPrank();

            assertEq(actualShares, expectedShares);
        }

        {
            uint256 expectedShares = 123e18;

            assertEq(asset.balanceOf(alice), 0);
            assertEq(asset.balanceOf(address(vault)), 123e18);
            assertEq(vault.balanceOf(alice), expectedShares);
            assertEq(vault.totalSupply(), expectedShares);
            assertEq(vault.totalAssets(), 123e18);
        }
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 223e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 223e18);
        assertEq(vault.convertToShares(1e18), uint256(1e18)*expectedShares/223e18);
        assertEq(vault.convertToAssets(1e18), uint256(1e18)*223e18/expectedShares);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904545454545454545e18);
        assertEq(vault.convertToAssets(1e18), 1.105527638190954773e18);

        assertEq(vault.maxDeposit(alice), 111_108_194.793060781293295092e18);
        assertEq(vault.maxMint(alice), 99_999_900.5e18);
        deposit(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 233e18);
        assertEq(vault.balanceOf(alice), 110.702795454545454545e18);
        assertEq(vault.totalSupply(), 210.202795454545454545e18);
        assertEq(vault.totalAssets(), 233e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.902157920405774483e18);
        assertEq(vault.convertToAssets(1e18), 1.108453384248090291e18);

        deposit(alice, vault.maxDeposit(alice));
        assertEq(vault.maxDeposit(alice), 0);
    }
}

contract OrigamiErc4626TestMint is OrigamiErc4626TestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    function test_mint_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0,
            MAX_TOTAL_SUPPLY
        );

        {
            address user = alice;
            uint256 shares = 123e18;
            uint256 expectedAssets = vault.previewMint(shares);
            deal(address(asset), user, expectedAssets);
            vm.startPrank(user);
            asset.approve(address(vault), expectedAssets);

            vm.expectEmit(address(vault));
            emit Deposit(user, user, expectedAssets, shares);
            uint256 actualAssets = vault.mint(shares, user);
            vm.stopPrank();

            assertEq(actualAssets, expectedAssets);
        }

        {
            uint256 expectedShares = 123e18;

            assertEq(asset.balanceOf(alice), 0);
            assertEq(asset.balanceOf(address(vault)), 123e18);
            assertEq(vault.balanceOf(alice), expectedShares);
            assertEq(vault.totalSupply(), expectedShares);
            assertEq(vault.totalAssets(), 123e18);
        }
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedAssets = 100e18 + OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18);
        assertEq(vault.totalAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), uint256(1e18)*123e18/expectedAssets);
        assertEq(vault.convertToAssets(1e18), uint256(1e18)*expectedAssets/123e18);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904956798544793087e18);
        assertEq(vault.convertToAssets(1e18), 1.105025125628140703e18);

        assertEq(vault.maxDeposit(alice), 111_057_690.512865836721431783e18);
        assertEq(vault.maxMint(alice), 99_999_900e18);
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 247.103608494734981441e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.902455457281399614e18);
        assertEq(vault.convertToAssets(1e18), 1.108087930469663593e18);
    }
}

contract OrigamiErc4626TestWithdraw is OrigamiErc4626TestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        uint256 expectedShares = 71.619693877551020407e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 73e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 73e18);
    }

    function test_withdraw_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0,
            MAX_TOTAL_SUPPLY
        );

        {
            address user = alice;
            uint256 shares = 123e18;
            uint256 expectedAssets = vault.previewMint(shares);
            deal(address(asset), user, expectedAssets);
            vm.startPrank(user);
            asset.approve(address(vault), expectedAssets);
            vault.mint(shares, user);
            vm.stopPrank();
        }

        {
            address user = alice;
            uint256 assets = 50e18;

            vm.startPrank(user);
            uint256 expectedShares = vault.previewWithdraw(assets);

            vm.expectEmit(address(vault));
            emit Withdraw(user, user, user, assets, expectedShares);
            uint256 actualShares = vault.withdraw(assets, user, user);
            vm.stopPrank();

            assertEq(actualShares, expectedShares);
        }

        {
            uint256 expectedShares = 73e18;

            assertEq(asset.balanceOf(alice), 50e18);
            assertEq(asset.balanceOf(address(vault)), 73e18);
            assertEq(vault.balanceOf(alice), expectedShares);
            assertEq(vault.totalSupply(), expectedShares);
            assertEq(vault.totalAssets(), 73e18);
        }
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = 71.619693877551020407e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 173e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 173e18);
        assertEq(vault.convertToShares(1e18), 0.413986669812433643e18);
        assertEq(vault.convertToAssets(1e18), 2.415536713906931880e18);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904545454545454545e18);
        assertEq(vault.convertToAssets(1e18), 1.105527638190954773e18);

        assertEq(vault.maxWithdraw(alice), 107.799999999999999999e18);
        assertEq(vault.maxRedeem(alice), 99.5e18);
        withdraw(alice, 50e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 60e18);
        assertEq(vault.balanceOf(alice), 53.349721706864564007e18);
        assertEq(vault.totalSupply(), 53.349721706864564007e18);
        assertEq(vault.totalAssets(), 60e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.889162028447742733e18);
        assertEq(vault.convertToAssets(1e18), 1.124654413938203126e18);
    }
}

contract OrigamiErc4626TestRedeem is OrigamiErc4626TestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 123e18 - 49.246231155778894472e18;

        assertEq(asset.balanceOf(alice), 49.246231155778894472e18);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    function test_redeem_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0,
            MAX_TOTAL_SUPPLY
        );

        {
            address user = alice;
            uint256 shares = 123e18;
            uint256 expectedAssets = vault.previewMint(shares);
            deal(address(asset), user, expectedAssets);
            vm.startPrank(user);
            asset.approve(address(vault), expectedAssets);
            vault.mint(shares, user);
            vm.stopPrank();
        }

        {
            address user = alice;
            uint256 shares = 50e18;
            vm.startPrank(user);
            uint256 expectedAssets = vault.previewRedeem(shares);

            vm.expectEmit(address(vault));
            emit Withdraw(user, user, user, expectedAssets, shares);
            uint256 actualAssets = vault.redeem(shares, user, user);
            vm.stopPrank();

            assertEq(actualAssets, expectedAssets);
        }

        {
            uint256 expectedShares = 73e18;

            assertEq(asset.balanceOf(alice), 50e18);
            assertEq(asset.balanceOf(address(vault)), 73e18);
            assertEq(vault.balanceOf(alice), expectedShares);
            assertEq(vault.totalSupply(), expectedShares);
            assertEq(vault.totalAssets(), 73e18);
        }
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 100e18 + 123e18 - 49.246231155778894472e18;

        assertEq(asset.balanceOf(alice), 49.246231155778894472e18);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), 0.416595280099488099e18);
        assertEq(vault.convertToAssets(1e18), 2.400411257086704504e18);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904545454545454545e18);
        assertEq(vault.convertToAssets(1e18), 1.105527638190954773e18);

        assertEq(vault.maxWithdraw(alice), 107.799999999999999999e18);
        assertEq(vault.maxRedeem(alice), 99.5e18);
        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(100e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 10e18 + 100e18 - 54.170854271356783919e18;

        assertEq(asset.balanceOf(alice), 54.170854271356783919e18);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), expectedAssets);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.886633663366336633e18);
        assertEq(vault.convertToAssets(1e18), 1.127861529871580122e18);
    }
}

contract OrigamiErc4626TestPermit is OrigamiErc4626TestBase {
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function buildDomainSeparator() internal view returns (bytes32) {
        bytes32 _hashedName = keccak256(bytes(vault.name()));
        bytes32 _hashedVersion = keccak256(bytes("1"));
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(vault)));
    }

    function signedPermit(
        address signer, 
        uint256 signerPk, 
        address spender, 
        uint256 amount, 
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = buildDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, signer, spender, amount, vault.nonces(signer), deadline));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        return vm.sign(signerPk, typedDataHash);
    }

    function test_permit() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");
        address spender = makeAddr("spender");
        uint256 amount = 123;

        assertEq(vault.nonces(signer), 0);
        uint256 allowanceBefore = vault.allowance(signer, spender);

        // Check for expired deadlines
        uint256 deadline = block.timestamp-1;
        (uint8 v, bytes32 r, bytes32 s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC2612ExpiredSignature.selector, 99999999));

        vault.permit(signer, spender, amount, deadline, v, r, s);

        // Permit successfully increments the allowance
        deadline = block.timestamp + 3600;
        (v, r, s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vault.permit(signer, spender, amount, deadline, v, r, s);
        assertEq(vault.allowance(signer, spender), allowanceBefore+amount);
        assertEq(vault.nonces(signer), 1);

        // Can't re-use the same signature for another permit (the nonce was incremented)
        address wrongRecoveryAddr = 0x600f8fed65c3a29D7854CB8366bA22a0e09Bdaba;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC2612InvalidSigner.selector, wrongRecoveryAddr, signer));

        vault.permit(signer, spender, amount, deadline, v, r, s);
    }
}