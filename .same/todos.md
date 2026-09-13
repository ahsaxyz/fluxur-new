# Fluxur Todos

## Completed
- [x] Password gate on /create page (REMOVED in v100)
- [x] Signed wallet login with Phantom and Supabase
- [x] Nonce issuance, message signing, signature verification
- [x] User upsert and session cookie management
- [x] Global AuthProvider for auth state
- [x] Recent Activity on Dashboard (filtered by logged-in user)
- [x] Fix React hooks order errors
- [x] Make Dashboard activity cards clickable
- [x] Prevent repeated signing on route changes
- [x] Skip signing on /commit routes
- [x] Use refs instead of state for signing tracking (more reliable)
- [x] POST /api/vanity/reserve - atomically reserve vanity mints
- [x] POST /api/vanity/release - release reserved vanity mints
- [x] Lock Creator Fees flow on /commit/[id] page
- [x] Real Solana Keypair generation for vault addresses
- [x] Fee lock status polling and vault balance display
- [x] UI/UX cleanup tasks (Dashboard, Discover, Lock page, Docs, Create form)
- [x] Make Manual Lock mode fully functional
- [x] Fix Manual Lock verification using fee payer method
- [x] Simplify Manual Lock flow
- [x] Docs restructuring (Claiming Requirements moved to 2c)
- [x] Vanity mint system for launchpad - VERIFIED COMPLETE
- [x] Roadmap page with phases 1-6 and Top Holder Airdrops section (v103)
  - [x] Created /roadmap route with consistent Fluxur styling
  - [x] Added Map icon to navigation across all pages
  - [x] Phases 1-2: Green checkmark (completed)
  - [x] Phases 3-6: Animated spinner (in-progress)
  - [x] Top Holder Airdrops section with purple styling
  - [x] Goal statement at bottom
  - [x] Mobile responsive design
  - [x] Always use FLXR vanity mint (regardless of Auto-Lock toggle)
  - [x] Use reserve_vanity_mint() RPC function for atomic reservation
  - [x] Query vanity_mints table (NOT vanity_mints_public)
  - [x] Server-side signing with vanity mint keypair (secret keys NEVER sent to client)
  - [x] Show "Your token will have a FLXR address" always on launch form
  - [x] Friendly error messages (no raw errors exposed, except for column/function issues)
  - [x] Client releases vanity mint on user rejection
  - [x] Server releases vanity mint on build failures
  - [x] Removed random mint generation (Keypair.generate)
  - [x] No fallback queries - pure RPC approach
  - [x] Release: { status: "available", reserved_at: null }
  - [x] Mark used: { status: "used", used_at: new Date().toISOString() }

## Notes
- AuthProvider uses localStorage flag `fluxur_auth_verified` to prevent re-signing across tabs
- Uses useRef for hasAttemptedRef and signInProgressRef for reliable tracking
- /commit routes are excluded from auto-signing
- Manual mode verifies token creator via fee payer of oldest transaction
- Vanity mints use server-side signing - secret keys NEVER sent to client
- reserve_vanity_mint() RPC function uses FOR UPDATE SKIP LOCKED for atomicity
- All vanity mint operations use supabaseService (service role), never anon client
- Client only needs Phantom signature (wallet signature)

## Anchor Program: fluxur_timelock
- [x] Created Solana Anchor program in `anchor/` directory
- [x] Two PDAs: lock (metadata) and vault (holds SOL)
- [x] `initialize_lock` instruction with unlock time validation
- [x] `withdraw` instruction with time check, funds always go to creator
- [x] Comprehensive tests for all edge cases
- [x] README with usage instructions
- [x] SECURITY FIX: Creator enforced on-chain as signer, not user-supplied
  - Removed `creator` argument from `initialize_lock`
  - Creator set to `ctx.accounts.payer.key()` (the signer)
  - Prevents malicious frontends from locking funds to wrong wallets
- [x] CRITICAL FIX: Vault PDA now explicitly created during initialize_lock
  - Vault created via CPI to system_program::create_account
  - Vault is system-owned (owner = system_program::ID)
  - Withdrawals use system_program::transfer with PDA signer
  - Required for mainnet correctness

## Implementation Summary

### FLXR Vanity Mint Flow:
1. User fills form and clicks "Create Commitment"
2. Server calls `reserve_vanity_mint()` RPC to atomically reserve a mint
3. Server decodes secret_key_base58 to create Keypair
4. Server calls PumpPortal with the vanity mint public key
5. Server signs transaction with vanity mint keypair
6. Client receives partially-signed transaction
7. Client signs with Phantom wallet
8. Client sends transaction on-chain
9. On success: Client calls /api/vanity/mark-used
10. On failure/rejection: Client calls /api/vanity/release

### Error Handling:
- "does not exist" or "Could not find" errors: Show actual error message
- No available mints: "No FLXR addresses available right now. Please try again in a few minutes."
- Other errors: Generic friendly message

## Frontend Withdraw Integration
- [x] Updated lock page with withdraw functionality
  - anchorWallet construction from useWallet()
  - PDA computation (lockPda, vaultPda from mint)
  - handleWithdraw() function using Anchor program
  - Withdraw button shown when feesDetected && countdown.expired
  - Status box for withdrawing/success/error states
- [x] Created /api/fee-locks/withdraw route
  - Verifies logged-in user via sb_session cookie
  - Verifies user is the creator of the commitment
  - Updates fee_locks: status='withdrawn', withdrawn_at, withdraw_tx
- [x] Fixed RPC URL in /api/fee-locks/status to use NEXT_PUBLIC_SOLANA_RPC_URL
