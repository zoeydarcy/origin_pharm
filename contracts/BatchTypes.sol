// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BatchTypes
 * @notice Shared data types used across all OriginPharm contracts.
 *         Import this file into any contract that needs access to these structs/enums.
 */

/// @notice Represents the current stage of a batch in the supply chain
enum BatchStatus {
    Produced,    // Minted by manufacturer; not yet released
    Released,    // Released to distributor
    InTransit,   // Being shipped between stakeholders
    Received    // Received at pharmacy/hospital
}

// ─── Structs ──────────────────────────────────────────────────────────────────

/**
 * @notice Stores the verified identity of a registered supply chain participant.
 *         Used for manufacturers, distributors, and pharmacies.
 *         The name is set by the Owner at registration — participants cannot
 *         self-report or change their own name in the system.
 */
struct VerifiedParty {
    bool   isAuthorised; // Whether this address is currently active
    string name;         // Owner-verified real-world name e.g. "Pfizer Australia Pty Ltd"
}

/**
 * @notice The digital identity of one pharmaceutical batch.
 *         Created by mintBatch() and updated as the batch progresses.
 *         manufacturerName is pulled from the VerifiedParty registry at mint —
 *         the manufacturer does not supply this themselves.
 */
struct BatchData {
    uint256 batchId;          // Unique identifier, auto-increments from 1
    string  medicineName;     // e.g. "Amoxicillin 500mg"
    string  batchNumber;      // Manufacturer's internal batch reference e.g. "BATCH-001"
    string  manufacturerName; // Owner-verified manufacturer name — read from registry at mint
    uint256 manufactureDate;  // Set automatically at mint (block.timestamp)
    uint256 expiryDate;       // Must be a future Unix timestamp — supplied by manufacturer
    address manufacturer;     // Wallet address of the minting manufacturer
    BatchStatus status;       // Current supply chain status — starts Produced
    bool    verified;         // Starts false — set true only when receipt() closes the cycle
}

/**
 * @notice A single entry in the custody trail of a batch.
 *         One record is appended by each of: release(), shipment(), receipt().
 *         Together they form the immutable audit trail readable via batchStatus().
 */
struct CustodyRecord {
    address from;        // Address that sent the batch (or zero address for initial mint)
    address to;          // Address that received the batch
    BatchStatus status;  // Batch status at the time of this handoff
    uint256 timestamp;   // Exact time of the event (block.timestamp)
    string  notes;       // Optional notes e.g. carrier reference, temperature log
}
