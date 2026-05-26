// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BatchTypes.sol";
import "./MintContract.sol";
import "./ControlContract.sol";

// VerificationContract
//  Layer 3 of OriginPharm — read-only verification for all stakeholders.
//  This contract has no state of its own and no write functions. It reads from both MintContract and ControlContract and returns the complete batch record in a single call.
//   Used by:
//     - Pharmacy: calls batchStatus(batchId) before receipt() to verify the on-chain record matches the physical delivery (medicine name, manufacturer, batch number, expiry date). If matched, proceeds to call receipt().
//     - Consumer: scans QR code on medication box → reads batchId → calls batchStatus() to confirm the medicine completed the verified supply chain.
//     - Regulator/Auditor: calls batchStatus() with batchId to audit the full custody trail and verified status of any batch.
 
contract VerificationContract {
    // Reference to MintContract — source of batch data and verified status.
    MintContract public mintContract;
    // Reference to ControlContract — source of custody history and current custodian.
    ControlContract public controlContract;

    // CONSTRUCTORS

    // mintContractAddress    Deployed address of MintContract.
    // controlContractAddress Deployed address of ControlContract.
    constructor(address mintContractAddress, address controlContractAddress) {
        require(mintContractAddress != address(0), "VerificationContract: zero address");
        require(controlContractAddress != address(0), "VerificationContract: zero address");
        mintContract = MintContract(mintContractAddress);
        controlContract = ControlContract(controlContractAddress);
    }

    // helper to print status 
    function _statusLabel(BatchStatus status) internal pure returns (string memory) {
        if (status == BatchStatus.Produced)  return "Produced";
        if (status == BatchStatus.Released)  return "Released";
        if (status == BatchStatus.InTransit) return "InTransit";
        if (status == BatchStatus.Received)  return "Received";
        return "Unknown";
    }

    // VERIFICATION FUNCTIONS 

    // Returns the complete batch record for a given batchId. This is the single entry point for all stakeholders — pharmacy, consumer, and regulator/auditor.
            //   Callable at any point in the batch lifecycle:
            //     After mintBatch():  status=Produced,  verified=false, empty trail
            //     After release():    status=Released,  verified=false, 1 custody record
            //     After shipment():   status=InTransit, verified=false, 2 custody records
            //     After receipt():    status=Received,  verified=true,  full trail
     
            //   For consumers — only meaningful after the QR code exists on the box, which only happens after receipt() sets verified=true.     
    function batchStatus(uint256 batchId) external view returns (
            string memory medicineName,
            string memory batchNumber,
            string memory manufacturerName,
            address manufacturer,
            uint256 manufactureDate,
            uint256 expiryDate,
            string memory  status,
            bool verified,
            address currentOwner,
            CustodyRecord[] memory custodyTrail
        )
    {
        require(mintContract.batchExists(batchId), "VerificationContract: batch does not exist");

        BatchData memory batch = mintContract.getBatch(batchId);

        medicineName = batch.medicineName;
        batchNumber = batch.batchNumber;
        manufacturerName = batch.manufacturerName;
        manufacturer = batch.manufacturer;
        manufactureDate = batch.manufactureDate;
        expiryDate = batch.expiryDate;
        status = _statusLabel(batch.status);
        verified = batch.verified;
        currentOwner = controlContract.currentCustodian(batchId);
        custodyTrail = controlContract.getCustodyHistory(batchId);
    }
}
