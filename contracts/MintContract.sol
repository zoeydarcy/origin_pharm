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
contract MintContract {

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Contract owner — set in constructor, used to authorise manufacturers
    address public owner;

    /// @notice Auto-incrementing ID counter for batch tokens
    uint256 private _nextTokenId;

    /// @notice Maps tokenId → BatchData
    mapping(uint256 => BatchData) private _batches;

    /// @notice Tracks which addresses are authorised manufacturers
    mapping(address => bool) public authorisedManufacturers;

    // ─── Events ───────────────────────────────────────────────────────────────

    event ManufacturerAuthorised(address indexed manufacturer);
    event ManufacturerRevoked(address indexed manufacturer);
    event BatchMinted(
        uint256 indexed tokenId,
        address indexed manufacturer,
        string medicineName,
        string batchNumber,
        uint256 expiryDate
    );

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "MintContract: caller is not owner");
        _;
    }

    modifier onlyManufacturer() {
        require(
            authorisedManufacturers[msg.sender],
            "MintContract: caller is not an authorised manufacturer"
        );
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
        _nextTokenId = 1; // Token IDs start at 1
    }

    // ─── Owner Functions ──────────────────────────────────────────────────────

    /**
     * @notice Grants manufacturer role to an address.
     * @param manufacturer Address to authorise.
     */
    function authoriseManufacturer(address manufacturer) external onlyOwner {
        // TODO: add input validation (e.g. non-zero address check)
        authorisedManufacturers[manufacturer] = true;
        emit ManufacturerAuthorised(manufacturer);
    }

    /**
     * @notice Revokes manufacturer role from an address.
     * @param manufacturer Address to revoke.
     */
    function revokeManufacturer(address manufacturer) external onlyOwner {
        // TODO: check manufacturer is currently authorised before revoking
        authorisedManufacturers[manufacturer] = false;
        emit ManufacturerRevoked(manufacturer);
    }

    // ─── Manufacturer Functions ───────────────────────────────────────────────

    /**
     * @notice Mints a new batch token representing a pharmaceutical product batch.
     * @param medicineName  Human-readable name of the medicine.
     * @param batchNumber   Manufacturer's internal batch reference.
     * @param expiryDate    Unix timestamp of the batch expiry date.
     * @return tokenId      The ID assigned to the newly minted batch.
     *
     * @dev TODO: Add validation:
     *      - expiryDate must be in the future
     *      - medicineName and batchNumber must not be empty strings
     *      - Consider emitting a QR-code-friendly hash of the tokenId
     */
    function mintBatch(
        string calldata medicineName,
        string calldata batchNumber,
        uint256 expiryDate
    ) external onlyManufacturer returns (uint256 tokenId) {
        tokenId = _nextTokenId++;

        _batches[tokenId] = BatchData({
            tokenId:         tokenId,
            medicineName:    medicineName,
            batchNumber:     batchNumber,
            manufactureDate: block.timestamp,
            expiryDate:      expiryDate,
            manufacturer:    msg.sender,
            status:          BatchStatus.Produced
        });

        emit BatchMinted(tokenId, msg.sender, medicineName, batchNumber, expiryDate);
    }

    // ─── Read Functions ───────────────────────────────────────────────────────

    /**
     * @notice Returns the full BatchData struct for a given tokenId.
     * @param tokenId The batch token to look up.
     */
    function getBatch(uint256 tokenId) external view returns (BatchData memory) {
        // TODO: revert with a descriptive error if tokenId does not exist
        return _batches[tokenId];
    }

    /**
     * @notice Returns true if a tokenId has been minted (exists in the registry).
     * @param tokenId The batch token to check.
     */
    function batchExists(uint256 tokenId) external view returns (bool) {
        return _batches[tokenId].manufacturer != address(0);
    }

    /**
     * @notice Allows the ControlContract to update the status of a batch.
     * @param tokenId   The batch to update.
     * @param newStatus The new BatchStatus value.
     *
     * @dev TODO: Restrict this so only the ControlContract address can call it.
     *      One approach: store the ControlContract address in state and add a modifier.
     */
    function updateStatus(uint256 tokenId, BatchStatus newStatus) external {
        // TODO: access control — only ControlContract should be able to call this
        _batches[tokenId].status = newStatus;
    }
}