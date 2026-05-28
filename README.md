# OriginPharm

OriginPharm is a Solidity smart contract system that tracks pharmaceutical batches across the supply chain — from manufacturer to distributor to pharmacy. Each batch is represented by a unique on-chain token. As custody transfers between stakeholders, every handoff is recorded immutably, creating a verifiable audit trail. Regulators, pharmacies, and consumers can query any batch at any time to confirm it originates from an authorised manufacturer and has followed a legitimate supply chain pathway.

YouTube Demonstartion Video: https://youtu.be/0U0CtY93-aE

---

## How it works

Each batch moves through four states enforced on-chain:

**Produced → Released → InTransit → Received**

- The Owner registers authorised participants (manufacturers, distributors, pharmacies) by wallet address and verified name
- The Manufacturer mints a batch and releases it to an authorised distributor
- The Distributor records the shipment to an authorised pharmacy
- The Pharmacy confirms receipt — setting verified = true and generating a QR code
- Anyone can scan the QR or enter a Batch ID to verify the full custody trail

---

## Smart contracts

| Contract | Purpose |
|---|---|
| `BatchTypes.sol` | Shared structs and enums (BatchStatus, BatchData, CustodyRecord) |
| `MintContract.sol` | Participant registration, batch creation, status and verified flag |
| `ControlContract.sol` | Supply chain pipeline — release, shipment, receipt |
| `VerificationContract.sol` | Read-only batch status and custody trail for public verification |

---

## Frontend portals

| Page | Role | Access |
|---|---|---|
| `index.html` | Landing page | Public |
| `Owner.html` | Register and manage participants | Owner wallet only |
| `Manufacturer.html` | Mint and release batches | Authorised manufacturer |
| `Distributor.html` | Record shipments | Authorised distributor |
| `Pharmacy.html` | Confirm receipt, generate QR | Authorised pharmacy |
| `Consumer.html` | Verify any batch by ID or QR | Public, no wallet required |

---

## Prerequisites

- Node.js v18 or later — nodejs.org
- MetaMask browser extension — Chrome, Brave, Firefox, or Edge
- Remix IDE — remix.ethereum.org (browser-based, no install)
- Sepolia testnet ETH — sepolia-faucet.pk910.de

---

## Local setup

**1. Install dependencies**

From the project root:

```bash
npm init -y
npm install lite-server --save-dev
npm install moment --save-dev
```

**2. Update package.json scripts**

```json
"scripts": {
  "dev": "lite-server"
}
```

**3. Create bs-config.json in the project root**

```json
{
  "server": {
    "baseDir": "./contracts",
    "routes": {
      "/node_modules": "node_modules"
    }
  }
}
```

**4. Run**

```bash
npm run dev
```

Navigate to `http://localhost:3000`

---

## Contract deployment

Deploy via Remix IDE using Injected Provider - MetaMask on the Sepolia network. Use Account 1 (Owner) for all deployments.

1. Compile and deploy `MintContract` → save address as `MINT_ADDR`
2. Compile and deploy `ControlContract` → paste `MINT_ADDR` in constructor → save as `CONTROL_ADDR`
3. Compile and deploy `VerificationContract` → paste `MINT_ADDR` and `CONTROL_ADDR` in constructor → save as `VERIFY_ADDR`
4. In Remix, call `MintContract → setControlContract` → paste `CONTROL_ADDR` → Transact

---

## Paste contract addresses

Open each HTML file in `contracts/` and replace the placeholder strings with your deployed addresses:

```javascript
const mintContractAddress         = 'YOUR_MINT_ADDR';
const controlContractAddress      = 'YOUR_CONTROL_ADDR';
const verificationContractAddress = 'YOUR_VERIFY_ADDR';
```

Not every page uses all three — paste only what is present in each file.

---

## Test accounts

Create five named accounts in MetaMask. Fund the first four with Sepolia ETH via the faucet. Consumer is read-only and requires no funds.

| Account | Role | Needs ETH |
|---|---|---|
| Account 1 | Owner | Yes |
| Account 2 | Manufacturer | Yes |
| Account 3 | Distributor | Yes |
| Account 4 | Pharmacist | Yes |
| Account 5 | Consumer | No |

---

## Testing order

1. **Owner** — Wire up ControlContract, authorise all participants
2. **Manufacturer** — Mint a batch, release to distributor
3. **Distributor** — Record shipment to pharmacy
4. **Pharmacy** — Search batch, confirm receipt, print QR
5. **Consumer** — Enter Batch ID or scan QR to verify

---

## Network

Deployed on Sepolia testnet. All data is stored on-chain in the smart contracts — nothing is stored locally or in the browser beyond the UI files served by lite-server.
