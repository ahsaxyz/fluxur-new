// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPonsFeeEscrow {
    function claim() external;
    function claimToken(address token) external;
}

/// @notice One instance per Fluxur commitment (deployed as a minimal-proxy clone by
/// FluxurVaultFactory). Becomes the sole `creatorFeeRecipient` on pons for that one
/// launch, so every fee it ever claims unambiguously belongs to `creator`. Holds them
/// until `unlockAt`, then releases the full balance to `creator` only.
contract FluxurVault {
    using SafeERC20 for IERC20;

    address public creator;
    uint256 public unlockAt;
    bool private initialized;

    event Initialized(address indexed creator, uint256 unlockAt);
    event Claimed(address indexed feeEscrow, address indexed token, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    error AlreadyInitialized();
    error NotCreator();
    error StillLocked();
    error ZeroCreator();

    function initialize(address _creator, uint256 _unlockAt) external {
        if (initialized) revert AlreadyInitialized();
        if (_creator == address(0)) revert ZeroCreator();
        initialized = true;
        creator = _creator;
        unlockAt = _unlockAt;
        emit Initialized(_creator, _unlockAt);
    }

    receive() external payable {}

    /// @notice Pulls this vault's pending balance out of pons's Fee Escrow.
    /// Permissionless on purpose: funds can only ever leave this contract via
    /// `withdraw`, which is gated to `creator` after `unlockAt`, so anyone
    /// (a keeper bot, Fluxur's backend, the creator) can trigger the claim step.
    function claimFromEscrow(address feeEscrow, address token) external {
        uint256 balBefore;
        if (token == address(0)) {
            IPonsFeeEscrow(feeEscrow).claim();
        } else {
            balBefore = IERC20(token).balanceOf(address(this));
            IPonsFeeEscrow(feeEscrow).claimToken(token);
        }
        uint256 bal = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        emit Claimed(feeEscrow, token, token == address(0) ? bal : bal - balBefore);
    }

    function isUnlocked() public view returns (bool) {
        return block.timestamp >= unlockAt;
    }

    /// @notice Sends this vault's full balance of `token` (address(0) = native ETH) to
    /// `creator`. Only `creator` can call it, and only once `unlockAt` has passed.
    function withdraw(address token) external {
        if (msg.sender != creator) revert NotCreator();
        if (!isUnlocked()) revert StillLocked();

        if (token == address(0)) {
            uint256 bal = address(this).balance;
            (bool ok, ) = creator.call{value: bal}("");
            require(ok, "native transfer failed");
            emit Withdrawn(token, creator, bal);
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(creator, bal);
            emit Withdrawn(token, creator, bal);
        }
    }
}
