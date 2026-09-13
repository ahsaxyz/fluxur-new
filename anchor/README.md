# Fluxur Timelock - Solana Anchor Program

A SOL timelock vault program that enforces time-based withdrawals using program-owned PDA vaults.

## Overview

This program allows creators to lock SOL in a PDA vault that can only be withdrawn after a specified unlock time. No private keys are stored - the vault is entirely controlled by the program.

## Architecture

### PDAs
- **Lock PDA**: `seeds = ["lock", mint]` - Stores timelock metadata
- **Vault PDA**: `seeds = ["vault", mint]` - Holds the locked SOL

### Lock Account Structure
```rust
pub struct LockAccount {
    pub creator: Pubkey,    // Receives funds on withdrawal (ALWAYS the initializer)
    pub mint: Pubkey,       // Used as seed for PDAs
    pub unlock_ts: i64,     // Unix timestamp for unlock
    pub lock_bump: u8,      // Bump for lock PDA
    pub vault_bump: u8,     // Bump for vault PDA
}
```

**SECURITY**: The `creator` field is set to `ctx.accounts.payer.key()` during initialization. It cannot be supplied by the user, preventing malicious frontends from locking funds to wrong wallets.

## Instructions

### `initialize_lock(mint, unlock_ts)`
- Creates the lock PDA (program-owned, stores metadata)
- Creates the vault PDA via CPI (system-owned, holds SOL)
- Payer pays for rent AND becomes the creator
- **SECURITY**: Creator is always the signer - cannot be user-supplied
- Rejects if `unlock_ts <= current_time`

### `withdraw(mint)`
- Anyone can call (permissionless)
- Funds always go to `lock.creator`
- Only succeeds if `current_time >= unlock_ts`
- Can be called multiple times after unlock

## Setup

### Prerequisites
- Rust 1.70+
- Solana CLI 1.18+
- Anchor 0.30+
- Node.js 18+
- Yarn

### Install Dependencies
```bash
cd anchor
yarn install
```

### Build
```bash
anchor build
```

### Test (localnet)
```bash
anchor test
```

### Deploy to Devnet
```bash
anchor deploy --provider.cluster devnet
```

## Security Features

1. **No private keys stored** - Vault is a system-owned PDA
2. **Vault created on-chain** - Vault PDA is explicitly created via CPI during initialization
3. **Creator enforced on-chain** - Creator is ALWAYS the signer, never user-supplied
4. **Immutable creator** - Funds always go to the creator set at initialization
5. **Time enforcement** - On-chain clock prevents early withdrawal
6. **Deterministic PDAs** - Anyone can derive vault address from mint
7. **System-owned vault** - Withdrawals use system_program::transfer with PDA signer

## Usage Example

```typescript
import { PublicKey } from "@solana/web3.js";
import * as anchor from "@coral-xyz/anchor";

// Derive PDAs
const [lockPda] = PublicKey.findProgramAddressSync(
  [Buffer.from("lock"), mint.toBuffer()],
  programId
);
const [vaultPda] = PublicKey.findProgramAddressSync(
  [Buffer.from("vault"), mint.toBuffer()],
  programId
);

// Initialize lock (1 week from now)
// SECURITY: Creator is automatically set to the payer/signer
const unlockTime = Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60;
await program.methods
  .initializeLock(mint, new anchor.BN(unlockTime))
  .accounts({
    payer: wallet.publicKey, // This wallet becomes the creator
    lock: lockPda,
    vault: vaultPda,
    systemProgram: SystemProgram.programId,
  })
  .rpc();

// Anyone can deposit SOL to vault
await connection.sendTransaction(
  new Transaction().add(
    SystemProgram.transfer({
      fromPubkey: depositor,
      toPubkey: vaultPda,
      lamports: 1_000_000_000, // 1 SOL
    })
  ),
  [depositorKeypair]
);

// After unlock time, anyone can trigger withdrawal to creator
await program.methods
  .withdraw(mint)
  .accounts({
    caller: anyone.publicKey,
    lock: lockPda,
    vault: vaultPda,
    creator: lockAccount.creator,
    systemProgram: SystemProgram.programId,
  })
  .rpc();
```
