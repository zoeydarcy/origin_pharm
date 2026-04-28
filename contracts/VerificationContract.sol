// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";
import "./MintContract.sol";
import "./ControlContract.sol";

/**
 * @title VerificationContract
 * @notice Read-only (view) contract for verifying pharmaceutical batch authenticity.
 *         Accessible by regulators, pharmacies, hospitals, and consumers.
 *
 * This contract does NOT write any state — all functions are `view`.
 *
 * Typical usage flow (e.g. consumer scans QR code):
 *   1. QR code on packaging encodes a tokenId
 *   2. Frontend calls verifyBatch(tokenId)    → confirms legitimacy + full history
 *   3. Frontend calls getBatchStatus(tokenId) → shows current owner + status
 */
contract VerificationContract {

    // ─── State ────────────────────────────────────────────────────────────────

    MintContract    public mintContract;
    ControlContract public controlContract;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param mintContractAddress    Deployed address of MintContract.
     * @param controlContractAddress Deployed address of ControlContract.
     */
    constructor(address mintContractAddress, address controlContractAddress) {
        mintContract    = MintContract(mintContractAddress);
        controlContract = ControlContract(controlContractAddress);
    }

    // ─── Verification Functions ───────────────────────────────────────────────

    /**
     * @notice Verifies the origin and full supply chain history of a batch.
     * @param tokenId The batch token to verify.
     * @return isValid       True if the batch was minted by an authorised manufacturer.
     * @return batch         The core batch data (medicine name, dates, manufacturer, etc.).
     * @return custodyTrail  Ordered list of custody records from mint to current holder.
     *
     * TODO: Consider storing a snapshot of authorised status at mint time inside BatchData
     *       so that legitimacy cannot be retroactively affected by revoking a manufacturer.
     * TODO: Add expiry date check: batch.expiryDate > block.timestamp
     */
    function verifyBatch(uint256 tokenId)
        external
        view
        returns (
            bool isValid,
            BatchData memory batch,
            CustodyRecord[] memory custodyTrail
        )
    {
        require(
            mintContract.batchExists(tokenId),
            "VerificationContract: batch does not exist"
        );

        batch        = mintContract.getBatch(tokenId);
        custodyTrail = controlContract.getCustodyHistory(tokenId);

        // Valid if minted by a currently-authorised manufacturer
        isValid = mintContract.authorisedManufacturers(batch.manufacturer);
    }

    /**
     * @notice Lightweight status check — intended for point-of-sale / consumer QR scanning.
     * @param tokenId The batch token to query.
     * @return currentOwner  Address of the current batch custodian.
     * @return status        Current BatchStatus enum value.
     * @return medicineName  Human-readable medicine name.
     */
    function getBatchStatus(uint256 tokenId)
        external
        view
        returns (
            address currentOwner,
            BatchStatus status,
            string memory medicineName
        )
    {
        require(
            mintContract.batchExists(tokenId),
            "VerificationContract: batch does not exist"
        );

        BatchData memory batch = mintContract.getBatch(tokenId);

        currentOwner = controlContract.currentCustodian(tokenId);
        status       = batch.status;
        medicineName = batch.medicineName;
    }
}