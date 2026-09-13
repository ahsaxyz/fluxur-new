# Fluxur Vault Contract (Robinhood Chain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and test, in isolation from the rest of the app, the on-chain time-lock vault that will replace the Solana Anchor `fluxur_timelock` program — the contract that becomes pons's `creatorFeeRecipient` for a launch and releases creator fees to the real creator only after an unlock time.

**Architecture:** A `FluxurVaultFactory` deploys one minimal-proxy (`EIP-1167`) `FluxurVault` clone per launch via `CREATE2`, so the vault's address is predictable off-chain before it's deployed (needed because that address must be passed into pons's `launchToken`/`launchAndBuy` as `creatorFeeRecipient`). Each vault is single-purpose: it is the *only* `creatorFeeRecipient` it will ever be, so once pons's Fee Escrow assigns fees to it, they're unambiguously this one creator's. `creator` is always `msg.sender` of the `createVault` call — never a parameter — so it can't be spoofed by a malicious frontend, mirroring the exact fix already applied to the Solana `fluxur_timelock` program (see `anchor/programs/fluxur_timelock`, "Creator enforced on-chain as signer, not user-supplied").

**Tech Stack:** Foundry (forge/cast/anvil v1.8.1, confirmed installable in this environment with no sudo — installed via `curl -L https://foundry.paradigm.xyz | bash && foundryup`, binaries land in `~/.foundry/bin`), Solidity `^0.8.24`, OpenZeppelin Contracts (`Clones`, `IERC20`, `SafeERC20`).

**Spec:** No separate spec doc — this plan is derived directly from the user-provided pivot brief (Fluxur moving from a Solana pump.fun fee-lock tool to a Robinhood Chain launchpad built on top of pons) plus live verification against pons's actual deployed contracts, done in-session on 2026-09-13. Key facts below were confirmed by calling the real contracts on Robinhood Chain mainnet via `cast`, not just read from docs (the docs at docs.ponsfamily.com/v2 are stale in at least one place — see Global Constraints).

## Global Constraints

- Robinhood Chain: chain id `4663`, public RPC `https://rpc.mainnet.chain.robinhood.com` (rate-limited, fine for occasional txs/tests, not for indexers).
- pons V2 Factory: `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` — confirmed live (24177 bytes of code).
- pons V2 Fee Escrow: `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` — confirmed live (1932 bytes). Fees are **pull-based**: `claim()` (native) or `claimToken(address token)` (custom-pair) must be called by/for the recipient to move accrued fees out of escrow. They are never pushed automatically.
- pons V2 Launch-and-buy router (separate from factory): `0xe33E9E479dF8802cb0866d5d05258bEc4cF62948` — confirmed live (4416 bytes). Not used by this plan (only the vault contract), but relevant to the later pons-integration plan.
- `canLaunch(address) view returns (bool)` on the factory returned `true` for four different arbitrary addresses tested live (including `0x0` and a `dEaD` burn address) on 2026-09-13, even though pons's own docs still say "Public launches are closed, so only whitelisted addresses can create a token for now." **Treat the docs' whitelist claim as stale** — the gate appears open — but re-check `canLaunch` for the actual deployer address before assuming this holds at execution time, since it could change back.
- pons V2 is **unaudited** as of 2026-09-13: three firms (SB Security, Dingbats, Pashov Audit Group) have reviews in progress, none closed. This vault holding real creator fee value against an unaudited upstream is a real risk — flag it to the user before any mainnet money moves through it, independent of whether this plan's own code is correct.
- Verified approved pair tokens on the factory (`approvedPairTokens(address) view returns (bool)`, checked live 2026-09-13): `SPY 0x117cc2133c37B721F49dE2A7a74833232B3B4C0C`, `NVDA 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC`, `TSLA 0x322F0929c4625eD5bAd873c95208D54E1c003b2d`, `AAPL 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9`, `MSFT 0xe93237C50D904957Cf27E7B1133b510C669c2e74`, `AMZN 0x12f190a9F9d7D37a250758b26824B97CE941bF54`, `GOOGL 0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3`, `META 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35`, `MSTR 0xec262a75e413fAfD0dF80480274532C79D42da09` — all confirmed `true`, all confirmed as real ERC-20s whose on-chain `symbol()` matches the ticker. `QCOM 0x0f17206447090e464C277571124dD2688E48AEA9` is a real, matching ERC-20 but **not** an approved pair token (`false`) — exclude it from any pair-token picker built later.
- This plan covers ONLY the vault contract (Subsystem 2 of the pivot). Three more subsystems are out of scope here and need their own plans before the pivot is complete: (1) replacing the Solana wallet-adapter layer with an EVM wallet stack for Robinhood Chain, (2) wiring pons's `launchToken`/`launchAndBuy` into the Create Commitment flow (reading `TokenParams`, `launchConfigId`, chosen `pairToken`), (3) porting the fee-lock status/withdraw UI and API routes (`/api/fee-locks/*`) to call this vault instead of the Anchor program.
- Do not delete or modify `anchor/` in this plan — it's preserved as the working Solana reference until the pivot is far enough along to retire it, and it's also safe in the `legacy-solana-pumpfun` git branch.

---

### Task 1: FluxurVault core contract

**Files:**
- Create: `evm/foundry.toml`
- Create: `evm/src/FluxurVault.sol`
- Create: `evm/test/FluxurVault.t.sol`
- Create: `evm/test/mocks/MockFeeEscrow.sol`
- Create: `evm/test/mocks/MockERC20.sol`

**Interfaces:**
- Produces: `FluxurVault.initialize(address _creator, uint256 _unlockAt)`, `FluxurVault.creator() view returns (address)`, `FluxurVault.unlockAt() view returns (uint256)`, `FluxurVault.isUnlocked() view returns (bool)`, `FluxurVault.claimFromEscrow(address feeEscrow, address token) external`, `FluxurVault.withdraw(address token) external` (token `address(0)` means native ETH). Errors: `AlreadyInitialized()`, `ZeroCreator()`, `NotCreator()`, `StillLocked()`. Events: `Initialized(address indexed creator, uint256 unlockAt)`, `Claimed(address indexed feeEscrow, address indexed token, uint256 amount)`, `Withdrawn(address indexed token, address indexed to, uint256 amount)`.
- Consumes: nothing from other tasks (this is the first task).

- [ ] **Step 1: Scaffold the Foundry project and install OpenZeppelin**

```bash
cd /home/wsl/fluxur-new
export PATH="$PATH:/home/wsl/.foundry/bin"
mkdir -p evm
cd evm
forge init --no-git --no-commit .
forge install OpenZeppelin/openzeppelin-contracts --no-git --no-commit
```

Then replace `evm/foundry.toml` with:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = ["@openzeppelin/=lib/openzeppelin-contracts/"]
solc_version = "0.8.24"

[rpc_endpoints]
robinhood = "https://rpc.mainnet.chain.robinhood.com"
```

Delete the default `evm/src/Counter.sol`, `evm/test/Counter.t.sol`, and `evm/script/Counter.s.sol` that `forge init` scaffolds — this plan doesn't use them.

- [ ] **Step 2: Write the failing test file**

```solidity
// evm/test/mocks/MockERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Pair Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

```solidity
// evm/test/mocks/MockFeeEscrow.sol
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
```

```solidity
// evm/test/FluxurVault.t.sol
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
```

- [ ] **Step 3: Run the tests to confirm they fail to compile**

```bash
cd /home/wsl/fluxur-new/evm
export PATH="$PATH:/home/wsl/.foundry/bin"
forge test --match-path test/FluxurVault.t.sol -vv
```

Expected: compilation error — `FluxurVault` doesn't exist yet.

- [ ] **Step 4: Implement `FluxurVault.sol`**

```solidity
// evm/src/FluxurVault.sol
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
```

- [ ] **Step 5: Run the tests to confirm they pass**

```bash
cd /home/wsl/fluxur-new/evm
export PATH="$PATH:/home/wsl/.foundry/bin"
forge test --match-path test/FluxurVault.t.sol -vv
```

Expected: all 8 tests in `FluxurVaultTest` PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/wsl/fluxur-new
git add evm/foundry.toml evm/src/FluxurVault.sol evm/test/FluxurVault.t.sol evm/test/mocks/MockFeeEscrow.sol evm/test/mocks/MockERC20.sol evm/.gitignore evm/remappings.txt
git commit -m "feat(evm): add FluxurVault time-lock contract with tests"
```

(`forge install` may also stage `evm/lib/openzeppelin-contracts` and `evm/.gitmodules` if git submodules are used — include those too if present: `git add evm/lib evm/.gitmodules`.)

---

### Task 2: FluxurVaultFactory (deterministic per-launch deployment)

**Files:**
- Create: `evm/src/FluxurVaultFactory.sol`
- Create: `evm/test/FluxurVaultFactory.t.sol`

**Interfaces:**
- Consumes: `FluxurVault` (Task 1) — deployed once as the clone implementation in the factory's constructor, then cloned per launch.
- Produces: `FluxurVaultFactory.implementation() view returns (address)`, `FluxurVaultFactory.createVault(uint256 unlockAt, bytes32 salt) external returns (address vault)`, `FluxurVaultFactory.predictVault(address deployer, bytes32 salt) external view returns (address)`. Event: `VaultCreated(address indexed creator, address indexed vault, uint256 unlockAt, bytes32 salt)`.

- [ ] **Step 1: Write the failing test file**

```solidity
// evm/test/FluxurVaultFactory.t.sol
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
```

- [ ] **Step 2: Run the tests to confirm they fail to compile**

```bash
cd /home/wsl/fluxur-new/evm
export PATH="$PATH:/home/wsl/.foundry/bin"
forge test --match-path test/FluxurVaultFactory.t.sol -vv
```

Expected: compilation error — `FluxurVaultFactory` doesn't exist yet.

- [ ] **Step 3: Implement `FluxurVaultFactory.sol`**

```solidity
// evm/src/FluxurVaultFactory.sol
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
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
cd /home/wsl/fluxur-new/evm
export PATH="$PATH:/home/wsl/.foundry/bin"
forge test --match-path test/FluxurVaultFactory.t.sol -vv
```

Expected: all 5 tests in `FluxurVaultFactoryTest` PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/wsl/fluxur-new
git add evm/src/FluxurVaultFactory.sol evm/test/FluxurVaultFactory.t.sol
git commit -m "feat(evm): add FluxurVaultFactory for deterministic per-launch vault deployment"
```

---

### Task 3: Live fork regression test against real pons contracts

**Files:**
- Create: `evm/test/PonsFactoryState.fork.t.sol`

**Interfaces:**
- Consumes: nothing from Task 1/2 — this test only reads live chain state through the real pons Factory ABI (declared locally as a minimal interface), to guard against the facts in Global Constraints silently going stale (e.g. pons re-closing the whitelist gate, or de-approving a pair token this plan's later work will rely on).
- Produces: nothing consumed by later tasks — this is a standalone regression guard, run manually or in CI against `--fork-url robinhood`, not part of the default `forge test` run (no RPC access in most CI/sandbox runs).

- [ ] **Step 1: Write the fork test**

```solidity
// evm/test/PonsFactoryState.fork.t.sol
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
```

- [ ] **Step 2: Run it against the live fork and confirm it passes**

```bash
cd /home/wsl/fluxur-new/evm
export PATH="$PATH:/home/wsl/.foundry/bin"
forge test --match-path test/PonsFactoryState.fork.t.sol --fork-url robinhood -vv
```

Expected: all 5 tests PASS (this is a regression/monitoring test, not new functionality — there's nothing to implement, it should pass immediately since it only asserts facts already verified live on 2026-09-13. If anything fails, stop and re-verify the relevant Global Constraint before continuing to the pons-integration plan).

- [ ] **Step 3: Commit**

```bash
cd /home/wsl/fluxur-new
git add evm/test/PonsFactoryState.fork.t.sol
git commit -m "test(evm): add live fork regression guard for pons factory assumptions"
```

---

## Self-Review Notes

- **Spec coverage:** Covers the vault contract subsystem end to end (lock, claim-from-escrow, unlock-gated withdraw, deterministic per-launch deployment) plus a regression guard on the three previously-unverified pons facts (whitelist gate, audit status — recorded in Global Constraints, not testable on-chain — and approved pair tokens). Does not cover: EVM wallet layer, pons launch-flow integration, or porting `/api/fee-locks/*` — called out explicitly as separate follow-on plans in Global Constraints, per the multi-subsystem scope-check rule.
- **Placeholder scan:** No TBDs; every function has real, complete logic; every test has concrete assertions with real addresses/values, not fixtures to fill in later.
- **Type consistency:** `withdraw(address token)` / `claimFromEscrow(address feeEscrow, address token)` use `address(0)` for native ETH consistently across `FluxurVault` and both test files. `FluxurVaultFactory.createVault`/`predictVault` both take `(address deployer_or_implicit_msgSender, bytes32 salt)` consistently.
