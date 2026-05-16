// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";

/**
 * @title MintContract
 * @notice Handles minting of pharmaceutical batch tokens.
 *         Only authorised manufacturers may mint new batches.
 *
 * @dev This is a simplified token registry (not a full ERC-721).
 *      Each batch gets a unique tokenId incremented from 1.
 *      The ControlContract reads from this contract to validate batches.
 */
/**
 * @title MintContract
 * @notice Layer 1 of OriginPharm — participant registration and batch token creation.
 *
 * The Owner (OriginPharm / TGA equivalent) registers every supply chain participant
 * with their verified wallet address and real-world name before any supply chain
 * activity is possible. Participants cannot self-report their own name.
 *
 * When a new batch of medicine is produced, the manufacturer calls mintBatch().
 * A unique batchId is assigned and the manufacturer's verified name is read
 * automatically from the registry — it is never passed as a parameter.
 *
 * Only ControlContract can update batch state via onlyControlContract modifier.
 * No external wallet can manipulate batch records directly.
 *
 * Deployment note:
 *   1. Deploy MintContract
 *   2. Deploy ControlContract with MintContract address
 *   3. Call setControlContract() on MintContract with ControlContract address
 */
contract MintContract {

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Owner wallet — TGA / OriginPharm platform.
    ///         Controls all participant registration. Has no supply chain write access.
    address public owner;

    /// @notice Address of the deployed ControlContract.
    ///         Set post-deployment via setControlContract(). Used for onlyControlContract.
    address public controlContractAddress;

    /// @notice Auto-incrementing batchId counter. Starts at 1.
    uint256 private _nextBatchId;

    /// @notice Maps batchId → BatchData for every minted batch.
    mapping(uint256 => BatchData) private _batches;

    /// @notice Registry of authorised manufacturers.
    ///         Stores owner-verified wallet address and real-world name.
    mapping(address => VerifiedParty) public authorisedManufacturers;

    // ─── Events ───────────────────────────────────────────────────────────────

    event ManufacturerAuthorised(address indexed manufacturer, string name);
    event ManufacturerRevoked(address indexed manufacturer);
    event ControlContractSet(address indexed controlContract);
    event BatchMinted(
        uint256 indexed batchId,
        address indexed manufacturer,
        string manufacturerName,
        string medicineName,
        string batchNumber,
        uint256 expiryDate
    );
    event BatchVerified(uint256 indexed batchId);

    // ─── Modifiers ────────────────────────────────────────────────────────────

    /// @notice Restricts function to the contract owner (TGA / OriginPharm).
    modifier onlyOwner() {
        require(msg.sender == owner, "MintContract: caller is not owner");
        _;
    }

    /// @notice Restricts function to authorised manufacturers only.
    modifier onlyManufacturer() {
        require(
            authorisedManufacturers[msg.sender].isAuthorised,
            "MintContract: caller is not an authorised manufacturer"
        );
        _;
    }

    /// @notice Restricts function to ControlContract only.
    ///         Prevents any external wallet from directly mutating batch state.
    modifier onlyControlContract() {
        require(
            msg.sender == controlContractAddress,
            "MintContract: caller is not the ControlContract"
        );
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
        _nextBatchId = 1;
    }

    // ─── Owner Functions ──────────────────────────────────────────────────────

    /**
     * @notice Sets the ControlContract address after deployment.
     *         Must be called once before any supply chain activity begins.
     *         Enables the onlyControlContract modifier on updateStatus() and setVerified().
     * @param _controlContractAddress Deployed address of ControlContract.
     */
    function setControlContract(address _controlContractAddress) external onlyOwner {
        require(_controlContractAddress != address(0), "MintContract: zero address");
        controlContractAddress = _controlContractAddress;
        emit ControlContractSet(_controlContractAddress);
    }

    /**
     * @notice Registers a manufacturer with their verified wallet address and real-world name.
     *         Name is set by the Owner — the manufacturer cannot self-report their identity.
     *         In practice, names are sourced from the TGA verified manufacturer database.
     * @param manufacturer Wallet address of the manufacturer.
     * @param name         Owner-verified real-world name e.g. "Pfizer Australia Pty Ltd".
     */
    function authoriseManufacturer(address manufacturer, string calldata name) external onlyOwner {
        require(manufacturer != address(0), "MintContract: zero address");
        require(bytes(name).length > 0, "MintContract: name cannot be empty");
        authorisedManufacturers[manufacturer] = VerifiedParty({ isAuthorised: true, name: name });
        emit ManufacturerAuthorised(manufacturer, name);
    }

    /**
     * @notice Revokes a manufacturer's authorisation.
     *         Revoked manufacturers can no longer call mintBatch().
     * @param manufacturer Wallet address to revoke.
     */
    function revokeManufacturer(address manufacturer) external onlyOwner {
        require(authorisedManufacturers[manufacturer].isAuthorised, "MintContract: not currently authorised");
        authorisedManufacturers[manufacturer].isAuthorised = false;
        emit ManufacturerRevoked(manufacturer);
    }

    // ─── Manufacturer Functions ───────────────────────────────────────────────

    /**
     * @notice Mints a batch token representing a newly produced pharmaceutical batch.
     *         Called by the manufacturer when a physical batch of medicine is produced.
     *         The manufacturer's verified name is read from the registry automatically —
     *         they do not pass their own name as a parameter.
     *
     * @param medicineName Human-readable name of the medicine e.g. "Amoxicillin 500mg".
     * @param batchNumber  Manufacturer's internal batch reference e.g. "BATCH-001".
     * @param expiryDate   Unix timestamp of the batch expiry date — must be in the future.
     * @return batchId     The unique ID assigned to this batch. Travels on the packing slip.
     */
    function mintBatch(
        string calldata medicineName,
        string calldata batchNumber,
        uint256 expiryDate
    ) external onlyManufacturer returns (uint256 batchId) {
        require(bytes(medicineName).length > 0, "MintContract: medicineName cannot be empty");
        require(bytes(batchNumber).length > 0,  "MintContract: batchNumber cannot be empty");
        require(expiryDate > block.timestamp,   "MintContract: expiry date must be in the future");

        batchId = _nextBatchId++;

        // Read manufacturer's verified name from the registry — never self-reported
        string memory verifiedName = authorisedManufacturers[msg.sender].name;

        _batches[batchId] = BatchData({
            batchId: batchId,
            medicineName: medicineName,
            batchNumber: batchNumber,
            manufacturerName: verifiedName,
            manufactureDate: block.timestamp,
            expiryDate: expiryDate,
            manufacturer: msg.sender,
            status: BatchStatus.Produced,
            verified: false
        });

        emit BatchMinted(batchId, msg.sender, verifiedName, medicineName, batchNumber, expiryDate);
    }

    // ─── ControlContract-Only Functions ──────────────────────────────────────

    /**
     * @notice Updates the status of a batch as it progresses through the supply chain.
     *         Called by ControlContract only — no external wallet can change batch state.
     * @param batchId   The batch to update.
     * @param newStatus The new BatchStatus value.
     */
    function updateStatus(uint256 batchId, BatchStatus newStatus) external onlyControlContract {
        require(batchExists(batchId), "MintContract: batch does not exist");
        _batches[batchId].status = newStatus;
    }

    /**
     * @notice Sets verified = true when receipt() closes the supply chain cycle.
     *         Called by ControlContract only after the pharmacist confirms delivery.
     *         Triggers the QR code generation event on the application layer.
     * @param batchId The batch to mark as verified.
     */
    function setVerified(uint256 batchId) external onlyControlContract {
        require(batchExists(batchId), "MintContract: batch does not exist");
        _batches[batchId].verified = true;
        emit BatchVerified(batchId);
    }

    // ─── Read Functions ───────────────────────────────────────────────────────

    /**
     * @notice Returns the full BatchData struct for a given batchId.
     *         Includes manufacturerName, verified flag, and current status.
     * @param batchId The batch to look up.
     */
    function getBatch(uint256 batchId) external view returns (BatchData memory) {
        require(batchExists(batchId), "MintContract: batch does not exist");
        return _batches[batchId];
    }

    /**
     * @notice Returns true if a batchId has been minted.
     * @param batchId The batch to check.
     */
    function batchExists(uint256 batchId) public view returns (bool) {
        return _batches[batchId].manufacturer != address(0);
    }

    /**
     * @notice Returns the verified name of a registered manufacturer.
     *         Used by ControlContract to display manufacturer identity in custody records.
     * @param manufacturer Wallet address of the manufacturer.
     */
    function getManufacturerName(address manufacturer) external view returns (string memory) {
        return authorisedManufacturers[manufacturer].name;
    }
}
