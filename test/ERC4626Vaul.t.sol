// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC4626Vault} from "../src/ERC4626Vault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ERC4626VaultTest is Test {
    ERC4626Vault public vault;
    MockERC20 public asset;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    
    uint256 constant INITIAL_BALANCE = 10000e18;

    // Events - declared here to match the vault events
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function setUp() public {
        asset = new MockERC20();
        vault = new ERC4626Vault(
            IERC20(address(asset)),
            "Vault Token",
            "vTOKEN"
        );
        
        // Setup test accounts
        asset.mint(alice, INITIAL_BALANCE);
        asset.mint(bob, INITIAL_BALANCE);
        
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function testMetadata() public view {
        assertEq(vault.name(), "Vault Token");
        assertEq(vault.symbol(), "vTOKEN");
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(asset));
    }

    function testSingleDepositWithdraw() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(alice);
        
        // Deposit
        uint256 shares = vault.deposit(depositAmount, alice);
        
        assertEq(shares, depositAmount, "shares should equal assets on first deposit");
        assertEq(vault.balanceOf(alice), shares, "alice should have shares");
        assertEq(vault.totalAssets(), depositAmount, "vault should have assets");
        assertEq(vault.totalSupply(), shares, "total supply should match shares");
        
        // Withdraw
        uint256 assets = vault.redeem(shares, alice, alice);
        
        assertEq(assets, depositAmount, "should withdraw same amount deposited");
        assertEq(vault.balanceOf(alice), 0, "alice should have no shares");
        assertEq(vault.totalAssets(), 0, "vault should be empty");
        
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        uint256 aliceDeposit = 1000e18;
        uint256 bobDeposit = 2000e18;
        
        // Alice deposits first
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);
        
        // Bob deposits
        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);
        
        assertEq(aliceShares, aliceDeposit, "alice 1:1 on first deposit");
        assertEq(bobShares, bobDeposit, "bob 1:1 on second deposit");
        assertEq(vault.totalAssets(), aliceDeposit + bobDeposit);
        assertEq(vault.totalSupply(), aliceShares + bobShares);
    }

    function testMintAndRedeem() public {
        uint256 sharesToMint = 500e18;
        
        vm.startPrank(alice);
        
        // Mint shares
        uint256 assetsUsed = vault.mint(sharesToMint, alice);
        
        assertEq(vault.balanceOf(alice), sharesToMint);
        assertEq(assetsUsed, sharesToMint, "1:1 on first mint");
        
        // Redeem shares
        uint256 assetsReceived = vault.redeem(sharesToMint, alice, alice);
        
        assertEq(assetsReceived, assetsUsed);
        assertEq(vault.balanceOf(alice), 0);
        
        vm.stopPrank();
    }

    function testWithdrawWithApproval() public {
        uint256 depositAmount = 1000e18;
        
        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        
        // Alice approves Bob to withdraw
        vm.prank(alice);
        vault.approve(bob, shares);
        
        // Bob withdraws on behalf of Alice
        vm.prank(bob);
        uint256 assets = vault.redeem(shares, bob, alice);
        
        assertEq(assets, depositAmount);
        assertEq(asset.balanceOf(bob), INITIAL_BALANCE + depositAmount);
        assertEq(vault.balanceOf(alice), 0);
    }

    function testPreviewFunctions() public {
        uint256 depositAmount = 1000e18;
        
        // Preview before any deposits
        assertEq(vault.previewDeposit(depositAmount), depositAmount);
        assertEq(vault.previewMint(depositAmount), depositAmount);
        
        // Make a deposit
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Preview should still be 1:1 with no profit
        assertEq(vault.previewDeposit(depositAmount), depositAmount);
        assertEq(vault.previewRedeem(depositAmount), depositAmount);
    }

    function testProfitAccrual() public {
        uint256 depositAmount = 1000e18;
        
        // Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);
        
        // Simulate profit by directly transferring assets to vault
        asset.transfer(address(vault), 500e18);
        
        // Bob should get fewer shares for same deposit due to increased asset value
        vm.prank(bob);
        uint256 bobShares = vault.deposit(depositAmount, bob);
        
        assertLt(bobShares, aliceShares, "bob should get fewer shares due to profit");
        
        // Alice should be able to withdraw more than she deposited
        vm.prank(alice);
        uint256 aliceAssets = vault.redeem(aliceShares, alice, alice);
        
        assertGt(aliceAssets, depositAmount, "alice should profit");
    }

    function testMaxFunctions() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxWithdraw(alice), vault.convertToAssets(vault.balanceOf(alice)));
        assertEq(vault.maxRedeem(alice), vault.balanceOf(alice));
        
        vm.stopPrank();
    }

    function testConversionFunctions() public {
        uint256 depositAmount = 1000e18;
        
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        uint256 shares = vault.convertToShares(depositAmount);
        uint256 assets = vault.convertToAssets(shares);
        
        assertEq(assets, depositAmount, "round trip conversion should match");
    }

    function testDepositZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(0, alice);
    }

    function test_RevertWhen_DepositWithoutApproval() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 0); // Remove approval
        
        vm.expectRevert();
        vault.deposit(1000e18, alice);
        vm.stopPrank();
    }

    function testWithdrawEvent() public {
        uint256 depositAmount = 1000e18;
        
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, alice, alice, depositAmount, shares);
        vault.redeem(shares, alice, alice);
    }

    function testDepositEvent() public {
        uint256 depositAmount = 1000e18;
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, alice, depositAmount, depositAmount);
        vault.deposit(depositAmount, alice);
    }

    function testFuzzDeposit(uint96 amount) public {
        vm.assume(amount > 0);
        
        asset.mint(alice, amount);
        
        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        
        uint256 shares = vault.deposit(amount, alice);
        assertEq(shares, amount);
        assertEq(vault.balanceOf(alice), shares);
        
        vm.stopPrank();
    }

    // Additional edge case tests
    function testFirstDepositInflationAttack() public {
        // Attacker makes first deposit
        vm.startPrank(alice);
        vault.deposit(1, alice);
        
        // Attacker donates large amount
        asset.transfer(address(vault), 1e18);
        
        // Victim deposits
        vm.startPrank(bob);
        uint256 bobShares = vault.deposit(2e18, bob);
        
        // Bob should still get reasonable shares (rounding protects vault)
        assertGt(bobShares, 0, "bob should receive shares");
        vm.stopPrank();
    }

    function testMultipleWithdrawals() public {
        uint256 depositAmount = 1000e18;
        
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Withdraw in multiple steps
        vm.startPrank(alice);
        vault.withdraw(300e18, alice, alice);
        vault.withdraw(300e18, alice, alice);
        vault.withdraw(400e18, alice, alice);
        
        // Should have minimal dust left due to rounding
        assertLt(vault.balanceOf(alice), 1e18, "should have minimal shares left");
        vm.stopPrank();
    }

    function testRoundingFavorsVault() public {
        uint256 depositAmount = 1000e18;
        
        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Add 1 wei profit
        asset.transfer(address(vault), 1);
        
        // Bob deposits same amount
        vm.prank(bob);
        uint256 bobShares = vault.deposit(depositAmount, bob);
        
        // Bob should get slightly fewer shares due to rounding down
        assertLe(bobShares, depositAmount, "rounding should favor vault");
    }

    function testConversionConsistency() public {
        uint256 depositAmount = 1000e18;
        
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        
        // Add profit
        asset.transfer(address(vault), 500e18);
        
        uint256 shares = vault.balanceOf(alice);
        uint256 assetsFromShares = vault.convertToAssets(shares);
        uint256 sharesFromAssets = vault.convertToShares(assetsFromShares);
        
        // Should be close due to rounding
        assertApproxEqAbs(shares, sharesFromAssets, 1, "conversion should be consistent");
    }

    function testZeroSharesCase() public view {
        // Ensure vault handles zero shares gracefully
        assertEq(vault.convertToAssets(0), 0);
        assertEq(vault.previewRedeem(0), 0);
    }

    function testZeroAssetsCase() public view {
        // Ensure vault handles zero assets gracefully  
        assertEq(vault.convertToShares(0), 0);
        assertEq(vault.previewDeposit(0), 0);
    }
}