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
    Received,    // Received at pharmacy/hospital
    Dispensed    // Distributed to a patient (end of lifecycle)
}

/// @notice Core data stored for each pharmaceutical batch
struct BatchData {
    uint256 tokenId;          // Unique batch identifier
    string  medicineName;     // e.g. "Amoxicillin 500mg"
    string  batchNumber;      // Manufacturer's internal batch ref
    uint256 manufactureDate;  // Unix timestamp
    uint256 expiryDate;       // Unix timestamp
    address manufacturer;     // Address of the minting manufacturer
    BatchStatus status;       // Current supply chain status
}

/// @notice A single entry in the custody history of a batch
struct CustodyRecord {
    address from;       // Sender address (zero for initial mint)
    address to;         // Receiver address
    BatchStatus status; // Status at the time of this transfer
    uint256 timestamp;  // Unix timestamp of the event
    string  notes;      // Optional notes (e.g. shipment ID, carrier)
}