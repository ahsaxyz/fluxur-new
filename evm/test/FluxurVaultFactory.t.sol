// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FluxurVaultFactory} from "../src/FluxurVaultFactory.sol";
import {FluxurVault} from "../src/FluxurVault.sol";

contract FluxurVaultFactoryTest is Test {
    FluxurVaultFactory factory;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        factory = new FluxurVaultFactory();
    }

    function test_PredictVaultMatchesActualDeployment() public {
        bytes32 salt = keccak256("commitment-1");
        address predicted = factory.predictVault(alice, salt);

        vm.prank(alice);
        address actual = factory.createVault(block.timestamp + 1 days, salt);

        assertEq(actual, predicted);
    }

    function test_CreatorIsAlwaysMsgSenderNeverSpoofable() public {
        bytes32 salt = keccak256("commitment-2");
        vm.prank(alice);
        address vault = factory.createVault(block.timestamp + 1 days, salt);

        assertEq(FluxurVault(payable(vault)).creator(), alice);
    }

    function test_SameDeployerDifferentSaltsProduceDifferentVaults() public {
        vm.startPrank(alice);
        address v1 = factory.createVault(block.timestamp + 1 days, keccak256("a"));
        address v2 = factory.createVault(block.timestamp + 1 days, keccak256("b"));
        vm.stopPrank();

        assertTrue(v1 != v2);
    }

    function test_DifferentDeployersSameSaltProduceDifferentVaults() public {
        bytes32 salt = keccak256("shared-salt");
        vm.prank(alice);
        address v1 = factory.createVault(block.timestamp + 1 days, salt);
        vm.prank(bob);
        address v2 = factory.createVault(block.timestamp + 1 days, salt);

        assertTrue(v1 != v2);
    }

    function test_CannotReuseSameDeployerAndSaltTwice() public {
        bytes32 salt = keccak256("commitment-3");
        vm.startPrank(alice);
        factory.createVault(block.timestamp + 1 days, salt);
        vm.expectRevert();
        factory.createVault(block.timestamp + 1 days, salt);
        vm.stopPrank();
    }
}
