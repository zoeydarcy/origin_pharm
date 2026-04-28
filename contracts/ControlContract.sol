// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";
import "./MintContract.sol";

/**
 * @title ControlContract
 * @notice Manages the internal supply chain pipeline for pharmaceutical batches.
 *         Handles custody transfers: Manufacturer → Distributor → Pharmacy/Hospital.
 *
 * Permitted actions per role:
 *   Manufacturer  → release()
 *   Distributor   → shipment()
 *   Pharmacy      → receipt()
 *
 * @dev Each state-changing function:
 *      1. Validates the caller's role
 *      2. Validates the batch is in the correct preceding state
 *      3. Updates the batch status via MintContract
 *      4. Appends a CustodyRecord to the batch history
 *      5. Emits an event
 */
contract ControlContract {

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Reference to the MintContract for batch lookups and status updates
    MintContract public mintContract;

    /// @notice Contract owner — manages role assignments
    address public owner;

    /// @notice Role mappings
    mapping(address => bool) public authorisedDistributors;
    mapping(address => bool) public authorisedPharmacies;

    /// @notice Maps tokenId → ordered list of custody records
    mapping(uint256 => CustodyRecord[]) private _custodyHistory;

    /// @notice Maps tokenId → current custodian address
    mapping(uint256 => address) public currentCustodian;

    // ─── Events ───────────────────────────────────────────────────────────────

    event BatchReleased(uint256 indexed tokenId, address indexed manufacturer, address indexed distributor, uint256 timestamp);
    event BatchShipped(uint256 indexed tokenId, address indexed distributor, address indexed recipient, string notes, uint256 timestamp);
    event BatchReceived(uint256 indexed tokenId, address indexed receiver, uint256 timestamp);

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "ControlContract: caller is not owner");
        _;
    }

    modifier onlyAuthorisedManufacturer() {
        require(
            mintContract.authorisedManufacturers(msg.sender),
            "ControlContract: caller is not an authorised manufacturer"
        );
        _;
    }

    modifier onlyDistributor() {
        require(
            authorisedDistributors[msg.sender],
            "ControlContract: caller is not an authorised distributor"
        );
        _;
    }

    modifier onlyPharmacy() {
        require(
            authorisedPharmacies[msg.sender],
            "ControlContract: caller is not an authorised pharmacy/hospital"
        );
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param mintContractAddress The deployed address of the MintContract.
     */
    constructor(address mintContractAddress) {
        owner = msg.sender;
        mintContract = MintContract(mintContractAddress);
    }

    // ─── Role Management ──────────────────────────────────────────────────────

    function authoriseDistributor(address distributor) external onlyOwner {
        // TODO: non-zero address check
        authorisedDistributors[distributor] = true;
    }

    function revokeDistributor(address distributor) external onlyOwner {
        authorisedDistributors[distributor] = false;
    }

    function authorisePharmacy(address pharmacy) external onlyOwner {
        // TODO: non-zero address check
        authorisedPharmacies[pharmacy] = true;
    }

    function revokePharmacy(address pharmacy) external onlyOwner {
        authorisedPharmacies[pharmacy] = false;
    }

    // ─── Supply Chain Functions ───────────────────────────────────────────────

    /**
     * @notice Step 1 — Manufacturer releases a produced batch to a distributor.
     * @param tokenId     The batch token being released.
     * @param distributor The distributor address receiving the batch.
     *
     * @dev Preconditions:
     *      - Batch must exist and have status Produced
     *      - msg.sender must be the original manufacturer of the batch
     *      - distributor must be an authorised distributor
     *
     * TODO: Validate that distributor address is authorised before proceeding.
     * TODO: Validate that msg.sender matches batch.manufacturer (not just any manufacturer).
     */
    function release(uint256 tokenId, address distributor)
        external
        onlyAuthorisedManufacturer
    {
        BatchData memory batch = mintContract.getBatch(tokenId);

        require(
            batch.status == BatchStatus.Produced,
            "ControlContract: batch must be in Produced state to release"
        );

        mintContract.updateStatus(tokenId, BatchStatus.Released);

        _appendCustody(tokenId, msg.sender, distributor, BatchStatus.Released, "");
        currentCustodian[tokenId] = distributor;

        emit BatchReleased(tokenId, msg.sender, distributor, block.timestamp);
    }

    /**
     * @notice Step 2 — Distributor records a shipment event.
     * @param tokenId   The batch token being shipped.
     * @param recipient The address of the pharmacy or hospital receiving the batch.
     * @param notes     Optional shipment notes (e.g. carrier ID, temperature log reference).
     *
     * TODO: Enforce that msg.sender == currentCustodian[tokenId].
     * TODO: Consider allowing multi-hop shipments (InTransit → InTransit).
     */
    function shipment(uint256 tokenId, address recipient, string calldata notes)
        external
        onlyDistributor
    {
        BatchData memory batch = mintContract.getBatch(tokenId);

        require(
            batch.status == BatchStatus.Released || batch.status == BatchStatus.InTransit,
            "ControlContract: batch must be Released or InTransit to ship"
        );

        mintContract.updateStatus(tokenId, BatchStatus.InTransit);

        _appendCustody(tokenId, msg.sender, recipient, BatchStatus.InTransit, notes);
        currentCustodian[tokenId] = recipient;

        emit BatchShipped(tokenId, msg.sender, recipient, notes, block.timestamp);
    }

    /**
     * @notice Step 3 — Pharmacy or hospital confirms receipt of a batch.
     * @param tokenId The batch token being received.
     *
     * TODO: Enforce that msg.sender == currentCustodian[tokenId].
     */
    function receipt(uint256 tokenId)
        external
        onlyPharmacy
    {
        BatchData memory batch = mintContract.getBatch(tokenId);

        require(
            batch.status == BatchStatus.InTransit,
            "ControlContract: batch must be InTransit to confirm receipt"
        );

        mintContract.updateStatus(tokenId, BatchStatus.Received);

        _appendCustody(tokenId, currentCustodian[tokenId], msg.sender, BatchStatus.Received, "");
        currentCustodian[tokenId] = msg.sender;

        emit BatchReceived(tokenId, msg.sender, block.timestamp);
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    function _appendCustody(
        uint256 tokenId,
        address from,
        address to,
        BatchStatus status,
        string memory notes
    ) internal {
        _custodyHistory[tokenId].push(CustodyRecord({
            from:      from,
            to:        to,
            status:    status,
            timestamp: block.timestamp,
            notes:     notes
        }));
    }

    // ─── Read Functions ───────────────────────────────────────────────────────

    /**
     * @notice Returns the full custody history array for a batch.
     * @param tokenId The batch to query.
     */
    function getCustodyHistory(uint256 tokenId)
        external
        view
        returns (CustodyRecord[] memory)
    {
        return _custodyHistory[tokenId];
    }
}