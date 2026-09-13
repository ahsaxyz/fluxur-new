// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Stands in for pons's real Fee Escrow (0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e).
/// Lets a test pre-load a "pending" balance for a recipient, then pays it out to
/// msg.sender when claim()/claimToken() is called -- matching the real escrow's
/// pull-based claim model described in pons's docs.
contract MockFeeEscrow {
    mapping(address => uint256) public pendingNative;
    mapping(address => mapping(address => uint256)) public pendingToken;

    receive() external payable {}

    function fundNative(address recipient) external payable {
        pendingNative[recipient] += msg.value;
    }

    function fundToken(address recipient, address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        pendingToken[recipient][token] += amount;
    }

    function claim() external {
        uint256 amount = pendingNative[msg.sender];
        pendingNative[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "native payout failed");
    }

    function claimToken(address token) external {
        uint256 amount = pendingToken[msg.sender][token];
        pendingToken[msg.sender][token] = 0;
        IERC20(token).transfer(msg.sender, amount);
    }
}
