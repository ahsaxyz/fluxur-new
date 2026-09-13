// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {FluxurVault} from "./FluxurVault.sol";

/// @notice Deploys one minimal-proxy FluxurVault clone per launch via CREATE2, so its
/// address is predictable off-chain before deployment -- needed because that address
/// must be passed into pons's launchToken/launchAndBuy as `creatorFeeRecipient` before
/// or alongside the vault's own deployment transaction.
contract FluxurVaultFactory {
    address public immutable implementation;

    event VaultCreated(address indexed creator, address indexed vault, uint256 unlockAt, bytes32 salt);

    constructor() {
        implementation = address(new FluxurVault());
    }

    function _salt(address deployer, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, salt));
    }

    /// @notice Deploys a new vault for msg.sender. `creator` is never a parameter --
    /// it's always msg.sender -- so no frontend or relayer can point a vault at the
    /// wrong wallet.
    function createVault(uint256 unlockAt, bytes32 salt) external returns (address vault) {
        vault = Clones.cloneDeterministic(implementation, _salt(msg.sender, salt));
        FluxurVault(payable(vault)).initialize(msg.sender, unlockAt);
        emit VaultCreated(msg.sender, vault, unlockAt, salt);
    }

    /// @notice Computes the vault address for (deployer, salt) before it's deployed,
    /// so the caller can pass it as pons's `creatorFeeRecipient` ahead of time.
    function predictVault(address deployer, bytes32 salt) external view returns (address) {
        return Clones.predictDeterministicAddress(implementation, _salt(deployer, salt), address(this));
    }
}
