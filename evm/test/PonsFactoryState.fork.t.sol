// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

interface IPonsFactoryView {
    function canLaunch(address) external view returns (bool);
    function approvedPairTokens(address) external view returns (bool);
}

interface IERC20Symbol {
    function symbol() external view returns (string memory);
}

/// @notice Run manually with: forge test --match-path test/PonsFactoryState.fork.t.sol --fork-url robinhood -vv
/// Not part of the default `forge test` run (needs live RPC access). Re-run this
/// whenever picking up this plan again -- if it fails, the facts in this plan's
/// Global Constraints section are stale and need re-verifying before writing more
/// code against them.
contract PonsFactoryStateForkTest is Test {
    address constant FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant FEE_ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;

    address constant SPY = 0x117cc2133c37B721F49dE2A7a74833232B3B4C0C;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant TSLA = 0x322F0929c4625eD5bAd873c95208D54E1c003b2d;
    address constant QCOM = 0x0f17206447090e464C277571124dD2688E48AEA9;

    function test_ChainIdIsRobinhoodMainnet() public view {
        assertEq(block.chainid, 4663);
    }

    function test_FactoryAndEscrowHaveCode() public view {
        assertGt(FACTORY.code.length, 0);
        assertGt(FEE_ESCROW.code.length, 0);
    }

    function test_LaunchGateIsCurrentlyOpenForArbitraryAddress() public view {
        // If this ever fails, pons has re-closed public launches -- update Global
        // Constraints and re-check the deployer's own address with canLaunch before
        // relying on this in the pons-integration plan.
        assertTrue(IPonsFactoryView(FACTORY).canLaunch(address(0xBEEF)));
    }

    function test_ApprovedStockPairTokensMatchTicker() public view {
        assertTrue(IPonsFactoryView(FACTORY).approvedPairTokens(SPY));
        assertEq(IERC20Symbol(SPY).symbol(), "SPY");

        assertTrue(IPonsFactoryView(FACTORY).approvedPairTokens(NVDA));
        assertEq(IERC20Symbol(NVDA).symbol(), "NVDA");

        assertTrue(IPonsFactoryView(FACTORY).approvedPairTokens(TSLA));
        assertEq(IERC20Symbol(TSLA).symbol(), "TSLA");
    }

    function test_QcomIsNotAnApprovedPairToken() public view {
        assertFalse(IPonsFactoryView(FACTORY).approvedPairTokens(QCOM));
    }
}
