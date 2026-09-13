// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FluxurVault} from "../src/FluxurVault.sol";
import {MockFeeEscrow} from "./mocks/MockFeeEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract FluxurVaultTest is Test {
    FluxurVault vault;
    MockFeeEscrow escrow;
    MockERC20 pairToken;
    address creator = address(0xC0FFEE);
    address stranger = address(0xBAD);
    uint256 unlockAt;

    function setUp() public {
        vault = new FluxurVault();
        escrow = new MockFeeEscrow();
        pairToken = new MockERC20();
        unlockAt = block.timestamp + 30 days;
        vault.initialize(creator, unlockAt);
    }

    function test_InitializeSetsCreatorAndUnlockAt() public view {
        assertEq(vault.creator(), creator);
        assertEq(vault.unlockAt(), unlockAt);
    }

    function test_InitializeCannotBeCalledTwice() public {
        vm.expectRevert(FluxurVault.AlreadyInitialized.selector);
        vault.initialize(stranger, unlockAt);
    }

    function test_InitializeRejectsZeroCreator() public {
        FluxurVault fresh = new FluxurVault();
        vm.expectRevert(FluxurVault.ZeroCreator.selector);
        fresh.initialize(address(0), unlockAt);
    }

    function test_IsUnlockedFalseBeforeUnlockAt() public view {
        assertFalse(vault.isUnlocked());
    }

    function test_IsUnlockedTrueAfterUnlockAt() public {
        vm.warp(unlockAt);
        assertTrue(vault.isUnlocked());
    }

    function test_WithdrawRevertsBeforeUnlock() public {
        vm.prank(creator);
        vm.expectRevert(FluxurVault.StillLocked.selector);
        vault.withdraw(address(0));
    }

    function test_WithdrawRevertsForNonCreator() public {
        vm.warp(unlockAt);
        vm.prank(stranger);
        vm.expectRevert(FluxurVault.NotCreator.selector);
        vault.withdraw(address(0));
    }

    function test_ClaimFromEscrowThenWithdrawNative() public {
        vm.deal(address(this), 1 ether);
        escrow.fundNative{value: 1 ether}(address(vault));

        vault.claimFromEscrow(address(escrow), address(0));
        assertEq(address(vault).balance, 1 ether);

        vm.warp(unlockAt);
        uint256 before = creator.balance;
        vm.prank(creator);
        vault.withdraw(address(0));
        assertEq(creator.balance, before + 1 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_ClaimFromEscrowThenWithdrawToken() public {
        pairToken.mint(address(this), 500 ether);
        pairToken.approve(address(escrow), 500 ether);
        escrow.fundToken(address(vault), address(pairToken), 500 ether);

        vault.claimFromEscrow(address(escrow), address(pairToken));
        assertEq(pairToken.balanceOf(address(vault)), 500 ether);

        vm.warp(unlockAt);
        vm.prank(creator);
        vault.withdraw(address(pairToken));
        assertEq(pairToken.balanceOf(creator), 500 ether);
        assertEq(pairToken.balanceOf(address(vault)), 0);
    }
}
