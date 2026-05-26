// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";
import "./MintContract.sol";

// CONTROL CONTRACT 
// Layer 2 of OriginPharm — the supply chain pipeline.
// Manages all custody transfers across the supply chain:
//     Manufacturer → release()  → Distributor
//     Distributor  → shipment() → Pharmacy
//     Pharmacy     → receipt()  → cycle closes, verified = true, QR code generated
 
//   Access is enforced through role-based modifiers:
//     onlyManufacturer → release()
//     onlyDistributor  → shipment()
//     onlyPharmacy     → receipt()

//   Custodian enforcement is applied across all three functions:
//     require(msg.sender == currentCustodian[batchId])
//     Only the current token holder can progress the batch.
 
contract ControlContract {
 
    MintContract public mintContract; // Reference to MintContract for batch lookups and state updates.
    address public owner; // Owner wallet — same deployer as MintContract.
    mapping(address => VerifiedParty) public authorisedDistributors; // Registry of authorised distributors with owner-verified names.
    mapping(address => VerifiedParty) public authorisedPharmacies;// Registry of authorised pharmacies with owner-verified names.
    mapping(uint256 => CustodyRecord[]) private _custodyHistory; // Full ordered custody trail per batch. Appended by each pipeline function.
    mapping(uint256 => address) public currentCustodian; // Current custodian (token holder) per batch.

// EVENTS
    event DistributorAuthorised(address indexed distributor, string name);
    event DistributorRevoked(address indexed distributor);
    event PharmacyAuthorised(address indexed pharmacy, string name);
    event PharmacyRevoked(address indexed pharmacy);

    event BatchReleased(uint256 indexed batchId, address indexed manufacturer, address indexed distributor, uint256 timestamp);
    event BatchShipped(uint256 indexed batchId, address indexed distributor, address indexed pharmacy, string  notes, uint256 timestamp);
    event BatchReceived(uint256 indexed batchId, address indexed pharmacy, uint256 timestamp);

    // MODIFIERS 
    // Restricts function to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "ControlContract: caller is not owner");
        _;
    } 
    // Restricts function to authorised manufacturers
    modifier onlyManufacturer() {
        (bool isAuth, ) = mintContract.authorisedManufacturers(msg.sender);
        require(isAuth, "ControlContract: caller is not an authorised manufacturer");
        _;
    }
    // Restricts function to authorised distributors.
    modifier onlyDistributor() {
        require(
            authorisedDistributors[msg.sender].isAuthorised,
            "ControlContract: caller is not an authorised distributor"
        );
        _;
    }
    // Restricts function to authorised pharmacies.
    modifier onlyPharmacy() {
        require(
            authorisedPharmacies[msg.sender].isAuthorised,
            "ControlContract: caller is not an authorised pharmacy"
        );
        _;
    }

    // CONSTRUCTOR

    // mintContractAddress Deployed address of MintContract.
    constructor(address mintContractAddress) {
        require(mintContractAddress != address(0), "ControlContract: zero address");
        owner = msg.sender;
        mintContract = MintContract(mintContractAddress);
    }

    // OWNER FUNCTIONS─── Owner Functions — Role Registration ──────────────────────────────────

    // Registers a distributor with their owner-verified name. 
    function authoriseDistributor(address distributor, string calldata name) external onlyOwner {
        require(distributor != address(0), "ControlContract: zero address");
        require(bytes(name).length > 0,   "ControlContract: name cannot be empty");
        authorisedDistributors[distributor] = VerifiedParty({ isAuthorised: true, name: name });
        emit DistributorAuthorised(distributor, name);
    }

    // Revokes a distributor's authorisation.
    function revokeDistributor(address distributor) external onlyOwner {
        require(authorisedDistributors[distributor].isAuthorised, "ControlContract: not currently authorised");
        authorisedDistributors[distributor].isAuthorised = false;
        emit DistributorRevoked(distributor);
    }
    // Registers a pharmacy with their owner-verified name.
    function authorisePharmacy(address pharmacy, string calldata name) external onlyOwner {
        require(pharmacy != address(0), "ControlContract: zero address");
        require(bytes(name).length > 0, "ControlContract: name cannot be empty");
        authorisedPharmacies[pharmacy] = VerifiedParty({ isAuthorised: true, name: name });
        emit PharmacyAuthorised(pharmacy, name);
    }
    // Revokes a pharmacy's authorisation.
    function revokePharmacy(address pharmacy) external onlyOwner {
        require(authorisedPharmacies[pharmacy].isAuthorised, "ControlContract: not currently authorised");
        authorisedPharmacies[pharmacy].isAuthorised = false;
        emit PharmacyRevoked(pharmacy);
    }

    //SUPPLY CHAIN PIPELINE  ─── Supply Chain Pipeline ────────────────────────────────────────────────

    // Step 1 — Manufacturer releases a produced batch to a distributor.
    //          The batchId travels on the packing slip accompanying the physical handover.
    //          Status: Produced -> Released.
    // batchId -> The batch being released.
    // distributor Wallet address of the receiving distributor — must be authorised.
    
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

    // Step 2 — Distributor records a shipment to the pharmacy.
    //           The batchId travels on the delivery documentation to the pharmacy.
    //           Status: Released → InTransit.
    //  batchId   The batch being shipped.
    //  pharmacy  Wallet address of the receiving pharmacy — must be authorised.
    //  notes     Optional carrier notes 
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

    // Step 3 — Pharmacy confirms delivery and closes the supply chain cycle.
    // Before calling this function, the pharmacist should call VerificationContract.batchStatus(batchId) to read the on-chain record and compare it against the physical delivery. 
    //           On success:
    //             - verified is set to true in MintContract
    //             - status moves to Received
    //             - BatchReceived event is emitted
    //             - The application layer detects the event and generates the printable QR code
    //  The pharmacist prints the QR code and attaches it to medication boxes
    // The QR code encodes only the batchId. All data lives on-chain. Consumers scan the QR and call batchStatus(batchId) to verify.
    
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

    // HELPER FUNCTIONS

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

    // READ FUNCTIONS

    // Returns the full ordered custody trail for a batch. Each record represents one handoff in the supply chain.
    function getCustodyHistory(uint256 batchId) external view returns (CustodyRecord[] memory) {
        return _custodyHistory[batchId];
    }
}
