// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";
import "./MintContract.sol";

/**
 * @title ControlContract
 * @notice Layer 2 of OriginPharm — the supply chain pipeline.
 *
 * Manages all custody transfers across the supply chain:
 *   Manufacturer → release()  → Distributor
 *   Distributor  → shipment() → Pharmacy
 *   Pharmacy     → receipt()  → cycle closes, verified = true, QR code generated
 *
 * Access is enforced through role-based modifiers:
 *   onlyManufacturer → release()
 *   onlyDistributor  → shipment()
 *   onlyPharmacy     → receipt()
 *
 * Custodian enforcement is applied across all three functions:
 *   require(msg.sender == currentCustodian[batchId])
 *   Only the current token holder can progress the batch.
 *
 * All state changes in MintContract are routed through this contract only.
 * No external wallet can mutate batch state directly.
 *
 * Deployment note:
 *   Deploy after MintContract. Pass MintContract address to constructor.
 *   Then call MintContract.setControlContract(thisAddress) to complete the wiring.
 */
contract ControlContract {

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Reference to MintContract for batch lookups and state updates.
    MintContract public mintContract;

    /// @notice Owner wallet — same deployer as MintContract.
    address public owner;

    /// @notice Registry of authorised distributors with owner-verified names.
    mapping(address => VerifiedParty) public authorisedDistributors;

    /// @notice Registry of authorised pharmacies with owner-verified names.
    mapping(address => VerifiedParty) public authorisedPharmacies;

    /// @notice Full ordered custody trail per batch. Appended by each pipeline function.
    mapping(uint256 => CustodyRecord[]) private _custodyHistory;

    /// @notice Current custodian (token holder) per batch.
    ///         Updated by each pipeline function. Used for custodian enforcement.
    mapping(uint256 => address) public currentCustodian;

    // ─── Events ───────────────────────────────────────────────────────────────

    event DistributorAuthorised(address indexed distributor, string name);
    event DistributorRevoked(address indexed distributor);
    event PharmacyAuthorised(address indexed pharmacy, string name);
    event PharmacyRevoked(address indexed pharmacy);

    event BatchReleased(
        uint256 indexed batchId,
        address indexed manufacturer,
        address indexed distributor,
        uint256 timestamp
    );
    event BatchShipped(
        uint256 indexed batchId,
        address indexed distributor,
        address indexed pharmacy,
        string  notes,
        uint256 timestamp
    );
    event BatchReceived(
        uint256 indexed batchId,
        address indexed pharmacy,
        uint256 timestamp
    );

    // ─── Modifiers ────────────────────────────────────────────────────────────

    /// @notice Restricts function to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "ControlContract: caller is not owner");
        _;
    }

    /// @notice Restricts function to authorised manufacturers (verified in MintContract).
    modifier onlyManufacturer() {
        (bool isAuth, ) = mintContract.authorisedManufacturers(msg.sender);
        require(isAuth, "ControlContract: caller is not an authorised manufacturer");
        _;
    }

    /// @notice Restricts function to authorised distributors.
    modifier onlyDistributor() {
        require(
            authorisedDistributors[msg.sender].isAuthorised,
            "ControlContract: caller is not an authorised distributor"
        );
        _;
    }

    /// @notice Restricts function to authorised pharmacies.
    modifier onlyPharmacy() {
        require(
            authorisedPharmacies[msg.sender].isAuthorised,
            "ControlContract: caller is not an authorised pharmacy"
        );
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param mintContractAddress Deployed address of MintContract.
     */
    constructor(address mintContractAddress) {
        require(mintContractAddress != address(0), "ControlContract: zero address");
        owner = msg.sender;
        mintContract = MintContract(mintContractAddress);
    }

    // ─── Owner Functions — Role Registration ──────────────────────────────────

    /**
     * @notice Registers a distributor with their owner-verified name.
     *         In practice, names are sourced from the TGA verified participant database.
     * @param distributor Wallet address of the distributor.
     * @param name        Owner-verified real-world name e.g. "AusPost Logistics".
     */
    function authoriseDistributor(address distributor, string calldata name) external onlyOwner {
        require(distributor != address(0), "ControlContract: zero address");
        require(bytes(name).length > 0,   "ControlContract: name cannot be empty");
        authorisedDistributors[distributor] = VerifiedParty({ isAuthorised: true, name: name });
        emit DistributorAuthorised(distributor, name);
    }

    /**
     * @notice Revokes a distributor's authorisation.
     * @param distributor Wallet address to revoke.
     */
    function revokeDistributor(address distributor) external onlyOwner {
        require(authorisedDistributors[distributor].isAuthorised, "ControlContract: not currently authorised");
        authorisedDistributors[distributor].isAuthorised = false;
        emit DistributorRevoked(distributor);
    }

    /**
     * @notice Registers a pharmacy with their owner-verified name.
     * @param pharmacy Wallet address of the pharmacy.
     * @param name     Owner-verified real-world name e.g. "Terry White — George St".
     */
    function authorisePharmacy(address pharmacy, string calldata name) external onlyOwner {
        require(pharmacy != address(0), "ControlContract: zero address");
        require(bytes(name).length > 0, "ControlContract: name cannot be empty");
        authorisedPharmacies[pharmacy] = VerifiedParty({ isAuthorised: true, name: name });
        emit PharmacyAuthorised(pharmacy, name);
    }

    /**
     * @notice Revokes a pharmacy's authorisation.
     * @param pharmacy Wallet address to revoke.
     */
    function revokePharmacy(address pharmacy) external onlyOwner {
        require(authorisedPharmacies[pharmacy].isAuthorised, "ControlContract: not currently authorised");
        authorisedPharmacies[pharmacy].isAuthorised = false;
        emit PharmacyRevoked(pharmacy);
    }

    // ─── Supply Chain Pipeline ────────────────────────────────────────────────

    /**
     * @notice Step 1 — Manufacturer releases a produced batch to a distributor.
     *         The batchId travels on the packing slip accompanying the physical handover.
     *         Status: Produced → Released.
     *
     * @param batchId     The batch being released.
     * @param distributor Wallet address of the receiving distributor — must be authorised.
     */
    function release(uint256 batchId, address distributor) external onlyManufacturer {
        require(mintContract.batchExists(batchId), "ControlContract: batch does not exist");
        require(authorisedDistributors[distributor].isAuthorised, "ControlContract: distributor is not authorised");

        BatchData memory batch = mintContract.getBatch(batchId);

        require(batch.status == BatchStatus.Produced, "ControlContract: batch must be Produced to release");
        require(msg.sender == batch.manufacturer,     "ControlContract: caller is not the batch manufacturer");

        mintContract.updateStatus(batchId, BatchStatus.Released);

        _appendCustody(batchId, msg.sender, distributor, BatchStatus.Released, "");
        currentCustodian[batchId] = distributor;

        emit BatchReleased(batchId, msg.sender, distributor, block.timestamp);
    }

    /**
     * @notice Step 2 — Distributor records a shipment to the pharmacy.
     *         The batchId travels on the delivery documentation to the pharmacy.
     *         Status: Released → InTransit.
     *
     * @param batchId   The batch being shipped.
     * @param pharmacy  Wallet address of the receiving pharmacy — must be authorised.
     * @param notes     Optional carrier notes e.g. "AusPost Ref: AUS-993, Temp: 2-8°C".
     */
    function shipment(uint256 batchId, address pharmacy, string calldata notes) external onlyDistributor {
        require(mintContract.batchExists(batchId), "ControlContract: batch does not exist");
        require(authorisedPharmacies[pharmacy].isAuthorised, "ControlContract: pharmacy is not authorised");
        require(msg.sender == currentCustodian[batchId], "ControlContract: caller is not the current custodian");

        BatchData memory batch = mintContract.getBatch(batchId);

        require(
            batch.status == BatchStatus.Released || batch.status == BatchStatus.InTransit,
            "ControlContract: batch must be Released or InTransit to ship"
        );

        mintContract.updateStatus(batchId, BatchStatus.InTransit);

        _appendCustody(batchId, msg.sender, pharmacy, BatchStatus.InTransit, notes);
        currentCustodian[batchId] = pharmacy;

        emit BatchShipped(batchId, msg.sender, pharmacy, notes, block.timestamp);
    }

    /**
     * @notice Step 3 — Pharmacy confirms delivery and closes the supply chain cycle.
     *
     *         Before calling this function, the pharmacist should call
     *         VerificationContract.batchStatus(batchId) to read the on-chain record
     *         and compare it against the physical delivery. If the medicine name,
     *         manufacturer, batch number, and expiry date all match — proceed.
     *
     *         On success:
     *           - verified is set to true in MintContract
     *           - status moves to Received
     *           - BatchReceived event is emitted
     *           - The application layer detects the event and generates the printable QR code
     *           - The pharmacist prints the QR code and attaches it to medication boxes
     *
     *         The QR code encodes only the batchId. All data lives on-chain.
     *         Consumers scan the QR and call batchStatus(batchId) to verify.
     *
     * @param batchId The batch being received — taken from the packing slip.
     */
    function receipt(uint256 batchId) external onlyPharmacy {
        require(mintContract.batchExists(batchId), "ControlContract: batch does not exist");
        require(msg.sender == currentCustodian[batchId], "ControlContract: caller is not the current custodian");

        BatchData memory batch = mintContract.getBatch(batchId);

        require(batch.status == BatchStatus.InTransit, "ControlContract: batch must be InTransit to receive");

        // Close the cycle — set verified = true and status = Received
        mintContract.setVerified(batchId);
        mintContract.updateStatus(batchId, BatchStatus.Received);

        _appendCustody(batchId, currentCustodian[batchId], msg.sender, BatchStatus.Received, "");
        currentCustodian[batchId] = msg.sender;

        // Emitting BatchReceived signals the application layer to generate the printable QR code
        emit BatchReceived(batchId, msg.sender, block.timestamp);
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    function _appendCustody(
        uint256 batchId,
        address from,
        address to,
        BatchStatus status,
        string memory notes
    ) internal {
        _custodyHistory[batchId].push(CustodyRecord({
            from: from,
            to: to,
            status: status,
            timestamp: block.timestamp,
            notes: notes
        }));
    }

    // ─── Read Functions ───────────────────────────────────────────────────────

    /**
     * @notice Returns the full ordered custody trail for a batch.
     *         Each record represents one handoff in the supply chain.
     * @param batchId The batch to query.
     */
    function getCustodyHistory(uint256 batchId) external view returns (CustodyRecord[] memory) {
        return _custodyHistory[batchId];
    }
}
