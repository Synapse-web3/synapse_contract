# Synapse Protocol — Base (EVM) Smart Contracts

Synapse Protocol is a **DeSci (Decentralized Science)** platform that brings research hypothesis management, IP-NFT minting, lab booking, and crowdfunding on-chain. This repository contains the complete Solidity implementation deployed on **Base** (an Ethereum L2 by Coinbase).

---

## Overview

The protocol is built around seven modules, all implemented in a single contract:

| Module | Description |
|--------|-------------|
| **ProtocolConfig** | One-time initialization; stores agent addresses and token references |
| **StakingPool** | Operators stake `$SYNAPSE`; 7-day cooldown unstake; slash to treasury |
| **HypothesisRegistry** | Commit-reveal scheme for research hypotheses; burns 10 SYNAPSE to commit |
| **IPNFTMinter** | Mints ERC-721 IP-NFTs from Grade A/B verified hypotheses; burns 50 SYNAPSE |
| **LabHardwareRegistry** | Register lab hardware; book time slots (USDC + SYNAPSE burn fee) |
| **CampaignEscrow** | USDC crowdfunding with milestone-gated escrow release |
| **TreasuryRouter** | Routes inference revenue (70/30) and data query revenue (80/20) |

---

## Token Stack on Base

| Token | Standard | Decimals | Address |
|-------|----------|----------|---------|
| `$SYNAPSE` | ERC-20 (burnable) | 6 | Deployed by this repo |
| `$USDC` | ERC-20 | 6 | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| IP-NFT | ERC-721 + ERC-2981 | — | Deployed by this repo |

---

## Repository Structure

```
src/
├── SynapseToken.sol          # ERC-20 SYNAPSE token (6 decimals, burnable, mintable)
├── SynapseIPNFT.sol          # ERC-721 IP-NFT with ERC-2981 royalty support
├── SynapseProtocol.sol       # Main protocol contract (all 7 modules)
└── lib/
    ├── SynapseConstants.sol  # Burn amounts, BPS splits, cooldown, size limits
    ├── SynapseErrors.sol     # 22 custom errors
    ├── SynapseEvents.sol     # All protocol events
    └── SynapseTypes.sol      # All structs, status constants, and calldata param types

script/
└── Deploy.s.sol              # Foundry deployment script (ordered deploy + init)

test/
└── SynapseProtocol.t.sol     # Forge test suite (11 tests, all passing)
```

---

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Install dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-git
forge install foundry-rs/forge-std --no-git
```

### Build

```bash
forge build
```

### Run tests

```bash
forge test -v
```

Expected output:
```
Ran 20 tests for test/SynapseProtocol.t.sol:SynapseProtocolTest
[PASS] test_AlreadyInitialized()
[PASS] test_AuthorityReleaseMilestone()
[PASS] test_CampaignLifecycle()
[PASS] test_CancelBooking()
[PASS] test_CommitRevealGrade()
[PASS] test_CooldownNotElapsed()
[PASS] test_DoubleBookingReverts()
[PASS] test_HashMismatch()
[PASS] test_MintIpnft()
[PASS] test_MintIpnftGradeInsufficient()
[PASS] test_NoPendingUnstake()
[PASS] test_PopsShieldFlaggedBlocksMint()
[PASS] test_PopsShieldPendingBlocksMint()
[PASS] test_RegisterAndBookLab()
[PASS] test_RequestAndWithdrawUnstake()
[PASS] test_RouteDataQueryRevenue()
[PASS] test_RouteInferenceRevenue()
[PASS] test_SlashOperator()
[PASS] test_StakeSynapse()
[PASS] test_SubmitExperimentResult()
20 passed
```

---

## Deployment

### 1. Set environment variables

Create a `.env` file:

```bash
PRIVATE_KEY=<your deployer private key>
EVIDENCE_GRADER=<grader EOA or multisig>
BIOSECURITY_AGENT=<biosecurity agent EOA>
TREASURY_WALLET=<treasury multisig>
MIN_LAB_STAKE=100000000
```

### 2. Deploy to Base Sepolia (testnet)

```bash
forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --broadcast
```

### 3. Deploy to Base Mainnet

```bash
forge script script/Deploy.s.sol \
  --rpc-url base_mainnet \
  --broadcast
```

### Deployment order (handled automatically by the script)

```
1. Deploy SynapseToken       → record SYNAPSE_TOKEN address
2. Deploy SynapseProtocol    → record PROTOCOL_ADDRESS
3. Deploy SynapseIPNFT       → wired to protocol address
4. Call setIpNftContract()
5. Call initializeProtocol()
6. Mint initial SYNAPSE supply
```

---

## Frontend Integration

### ABI files (generated after `forge build`)

```
out/SynapseProtocol.sol/SynapseProtocol.json
out/SynapseToken.sol/SynapseToken.json
out/SynapseIPNFT.sol/SynapseIPNFT.json
```

### Frontend environment variables

```
VITE_PROTOCOL_ADDRESS=0x...
VITE_SYNAPSE_TOKEN=0x...
VITE_IPNFT_ADDRESS=0x...
VITE_USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
VITE_CHAIN_ID=8453
```

> Solana PDA env vars (`VITE_CONFIG_PDA`, `VITE_STAKE_POOL_PDA`, etc.) are not used on EVM.
> All state lives in contract storage mappings — no separate account addresses needed.

### Key derivation (replaces Solana PDAs)

```ts
import { keccak256, encodePacked, toBytes } from "viem";

const hypothesisKey = (author: `0x${string}`, shortId: `0x${string}`) =>
  keccak256(encodePacked(["address", "bytes8"], [author, shortId]));

const labKey = (operator: `0x${string}`, labId: `0x${string}`) =>
  keccak256(encodePacked(["address", "bytes8"], [operator, labId]));

const campaignKey = (lead: `0x${string}`, id: `0x${string}`) =>
  keccak256(encodePacked(["address", "bytes16"], [lead, id]));

const bookingKey = (lKey: `0x${string}`, slotStart: bigint) =>
  keccak256(encodePacked(["bytes32", "int256"], [lKey, slotStart]));
```

### Commitment hash (keccak256 replaces SHA-256 from Solana)

```ts
const salt      = crypto.getRandomValues(new Uint8Array(32));
const plaintext = "My hypothesis text";

const saltedHash = keccak256(
  encodePacked(["bytes", "bytes"], [salt, toBytes(plaintext)])
);
```

---

## Key Differences vs. Original Solana / Anchor Program

| Aspect | Solana/Anchor | Base/Solidity |
|--------|--------------|---------------|
| Accounts | PDA (program-derived) | Mappings keyed by `keccak256` |
| Token burn | `token::burn` CPI | `ERC20Burnable.burnFrom()` |
| NFT | SPL Token (supply=1) | ERC-721 (`SynapseIPNFT`) |
| Royalty standard | Custom | ERC-2981 |
| Hash function | SHA-256 | keccak256 (native, cheaper on EVM) |
| Vault | PDA token account | Contract holds tokens directly |
| Rent | SOL rent per account | No rent — gas only |
| Token decimals | SYNAPSE=6, USDC=6 | Same |

---

## Security

- `ReentrancyGuard` on all token-moving functions
- `SafeERC20` wraps every external token call
- Solidity 0.8 checked arithmetic throughout
- `msg.sender`-only authorization — no `tx.origin`
- One-time protocol initialization (`AlreadyInitialized` guard)
- IP-NFT minted at most once per hypothesis key
- Campaign escrow isolated from staking vault

---

## License

MIT
