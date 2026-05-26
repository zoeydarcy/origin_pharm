// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";

// MINT CONTRACT 

// Handles minting of pharmaceutical batch tokens.Only authorised manufacturers may mint new batches.
// Layer 1 of OriginPharm — participant registration and batch token creation.
// The Owner (OriginPharm) registers every supply chain participant with their verified wallet address and real-world name before any supply chain activity is possible. Participants cannot self-report their own name.
// When a new batch of medicine is produced, the manufacturer calls mintBatch().
// A unique batchId is assigned and the manufacturer's verified name is read automatically from the registry — it is never passed as a parameter.
// Only ControlContract can update batch state via onlyControlContract modifier. No external wallet can manipulate batch records directly.

contract MintContract {
    // Controls all participant registration. Has no supply chain write access.
    address public owner; // Owner wallet — OriginPharm platform.

    // Set post-deployment via setControlContract(). Used for onlyControlContract.
    address public controlContractAddress; // Address of the deployed ControlContract.

    // Auto-incrementing batchId counter. Starts at 1.
    uint256 private _nextBatchId;

    // Maps batchId → BatchData for every minted batch.
    mapping(uint256 => BatchData) private _batches;

    // Stores owner-verified wallet address and real-world name.
    mapping(address => VerifiedParty) public authorisedManufacturers;// Registry of authorised manufacturers.

    // EVENTS
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

    // MODIFIERS

    // Restricts function to the contract owner (OriginPharm).
    modifier onlyOwner() {
        require(msg.sender == owner, "MintContract: caller is not owner");
        _;
    }
    // Restricts function to authorised manufacturers only.
    modifier onlyManufacturer() {
        require(
            authorisedManufacturers[msg.sender].isAuthorised,
            "MintContract: caller is not an authorised manufacturer"
        );
        _;
    }

    // Restricts function to ControlContract only.
    // Prevents any external wallet from directly mutating batch state.
    modifier onlyControlContract() {
        require(
            msg.sender == controlContractAddress,
            "MintContract: caller is not the ControlContract"
        );
        _;
    }

    // CONSTRUCTORS

    constructor() {
        owner = msg.sender;
        _nextBatchId = 1;
    }

    // OWNER FUNCTIONS
    // Sets the ControlContract address after deployment. Must be called once before any supply chain activity begins.
    // Enables the onlyControlContract modifier on updateStatus() and setVerified().
    // _controlContractAddress Deployed address of ControlContract.
    function setControlContract(address _controlContractAddress) external onlyOwner {
        require(_controlContractAddress != address(0), "MintContract: zero address");
        controlContractAddress = _controlContractAddress;
        emit ControlContractSet(_controlContractAddress);
    }

    // Registers a manufacturer with their verified wallet address and real-world name.
    // Name is set by the Owner — the manufacturer cannot self-report their identity.
    // In practice, names are sourced from the TGA verified manufacturer database.
    // manufacturer Wallet address of the manufacturer.
    function authoriseManufacturer(address manufacturer, string calldata name) external onlyOwner {
        require(manufacturer != address(0), "MintContract: zero address");
        require(bytes(name).length > 0, "MintContract: name cannot be empty");
        authorisedManufacturers[manufacturer] = VerifiedParty({ isAuthorised: true, name: name });
        emit ManufacturerAuthorised(manufacturer, name);
    }

    // Revokes a manufacturer's authorisation.
    function revokeManufacturer(address manufacturer) external onlyOwner {
        require(authorisedManufacturers[manufacturer].isAuthorised, "MintContract: not currently authorised");
        authorisedManufacturers[manufacturer].isAuthorised = false;
        emit ManufacturerRevoked(manufacturer);
    }

    // MANUFACTURE FUNCTIONS

    // Mints a batch token representing a newly produced pharmaceutical batch.
    //  Called by the manufacturer when a physical batch of medicine is produced.
    //  The manufacturer's verified name is read from the registry automatically — they do not pass their own name as a parameter.
    function mintBatch(string calldata medicineName, string calldata batchNumber, uint256 expiryDate) external onlyManufacturer returns (uint256 batchId) {
        require(bytes(medicineName).length > 0, "MintContract: medicineName cannot be empty");
        require(bytes(batchNumber).length > 0,  "MintContract: batchNumber cannot be empty");
        require(expiryDate > block.timestamp,   "MintContract: expiry date must be in the future");
        
        batchId = _nextBatchId++;
       
        string memory verifiedName = authorisedManufacturers[msg.sender].name; // Read manufacturer's verified name from the registry 

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

    // CONTROL CONTRACT-ONLY FUNCTIONS 

    // Updates the status of a batch as it progresses through the supply chain.
    // Called by ControlContract only — no external wallet can change batch state.
    function updateStatus(uint256 batchId, BatchStatus newStatus) external onlyControlContract {
        require(batchExists(batchId), "MintContract: batch does not exist");
        _batches[batchId].status = newStatus;
    }

    // Sets verified = true when receipt() closes the supply chain cycle.
    // Called by ControlContract only after the pharmacist confirms delivery. Triggers the QR code generation event on the application layer.
    function setVerified(uint256 batchId) external onlyControlContract {
        require(batchExists(batchId), "MintContract: batch does not exist");
        _batches[batchId].verified = true;
        emit BatchVerified(batchId);
    }

    // READ FUNCTIONS

    // Returns the full BatchData struct for a given batchId. Includes manufacturerName, verified flag, and current status.
    // batchId The batch to look up.
    function getBatch(uint256 batchId) external view returns (BatchData memory) {
        require(batchExists(batchId), "MintContract: batch does not exist");
        return _batches[batchId];
    }

    // Returns true if a batchId has been minted.
    function batchExists(uint256 batchId) public view returns (bool) {
        return _batches[batchId].manufacturer != address(0);
    }

    // Returns the verified name of a registered manufacturer.
    function getManufacturerName(address manufacturer) external view returns (string memory) {
        return authorisedManufacturers[manufacturer].name;
    }
}
